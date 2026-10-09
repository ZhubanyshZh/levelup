import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError, AuthError
from app.core.security import create_access_token, generate_refresh_token, hash_secret
from app.core.time import utcnow
from app.models import AuthIdentity, AuthProvider, RefreshToken, User
from app.schemas.auth import ClientInfo


@dataclass(frozen=True)
class TokenPair:
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime


@dataclass(frozen=True)
class IdentityClaims:
    provider: AuthProvider
    subject: str
    email: str | None = None
    display_name: str | None = None
    avatar_url: str | None = None


def normalize_locale(raw: str | None) -> str:
    return "en" if raw and raw.lower().startswith("en") else "ru"


async def sign_in_with_identity(
    db: AsyncSession, claims: IdentityClaims, client: ClientInfo
) -> tuple[User, bool]:
    """Находит пользователя по способу входа или создаёт нового. Возвращает (user, is_new)."""
    identity = await db.scalar(
        select(AuthIdentity).where(
            AuthIdentity.provider == claims.provider, AuthIdentity.subject == claims.subject
        )
    )
    now = utcnow()

    if identity is not None:
        user = await db.get(User, identity.user_id)
        if user is None or user.deleted_at is not None:
            raise AuthError("account_deleted")
        identity.last_login_at = now
        if claims.email:
            identity.email = claims.email
        return user, False

    user = User(
        display_name=claims.display_name,
        email=claims.email,
        avatar_url=claims.avatar_url,
        locale=normalize_locale(client.locale),
        timezone=client.timezone or "UTC",
    )
    db.add(user)
    await db.flush()
    db.add(
        AuthIdentity(
            user_id=user.id,
            provider=claims.provider,
            subject=claims.subject,
            email=claims.email,
            last_login_at=now,
        )
    )
    return user, True


async def link_identity(db: AsyncSession, user: User, claims: IdentityClaims) -> None:
    """Добавляет способ входа к текущему аккаунту (гость → Google). Данные не переносятся —
    аккаунт тот же, просто у него появляется второй ключ от двери."""
    identity = await db.scalar(
        select(AuthIdentity).where(
            AuthIdentity.provider == claims.provider, AuthIdentity.subject == claims.subject
        )
    )
    if identity is not None:
        if identity.user_id != user.id:
            raise AppError("identity_in_use", status_code=409)
        return
    db.add(
        AuthIdentity(
            user_id=user.id,
            provider=claims.provider,
            subject=claims.subject,
            email=claims.email,
            last_login_at=utcnow(),
        )
    )
    user.display_name = user.display_name or claims.display_name
    user.email = user.email or claims.email
    user.avatar_url = user.avatar_url or claims.avatar_url


def device_claims(device_secret: str) -> IdentityClaims:
    return IdentityClaims(provider=AuthProvider.DEVICE, subject=hash_secret(device_secret))


async def issue_tokens(
    db: AsyncSession,
    user: User,
    settings: Settings,
    *,
    family_id: uuid.UUID | None = None,
    device_name: str | None = None,
) -> tuple[TokenPair, RefreshToken]:
    access_token, access_expires_at = create_access_token(user.id, settings)
    raw_refresh = generate_refresh_token()
    refresh = RefreshToken(
        id=uuid.uuid4(),
        user_id=user.id,
        family_id=family_id or uuid.uuid4(),
        token_hash=hash_secret(raw_refresh),
        expires_at=utcnow() + timedelta(days=settings.refresh_token_ttl_days),
        device_name=device_name,
    )
    db.add(refresh)
    pair = TokenPair(access_token, access_expires_at, raw_refresh, refresh.expires_at)
    return pair, refresh


async def rotate_refresh_token(
    db: AsyncSession, raw_token: str, settings: Settings
) -> tuple[User, TokenPair]:
    """Меняет refresh-токен на новую пару. Срок нового — снова полный (скользящая сессия)."""
    token = await db.scalar(
        select(RefreshToken)
        .where(RefreshToken.token_hash == hash_secret(raw_token))
        .with_for_update()
    )
    if token is None:
        raise AuthError("invalid_refresh_token")

    now = utcnow()
    if token.revoked_at is not None:
        leeway = timedelta(seconds=settings.refresh_reuse_leeway_seconds)
        if token.revoked_reason != "rotated" or now - token.revoked_at > leeway:
            await _revoke_family(db, token.family_id, reason="reuse")
            await db.commit()
            raise AuthError("refresh_token_reused")
        # Клиент не получил ответ на прошлый обмен и повторил запрос: выданный тогда
        # токен отзываем, вместо него выдаём новый — активным в семье остаётся один.
        if token.replaced_by_id is not None:
            await db.execute(
                update(RefreshToken)
                .where(RefreshToken.id == token.replaced_by_id, RefreshToken.revoked_at.is_(None))
                .values(revoked_at=now, revoked_reason="superseded")
            )
    elif token.expires_at <= now:
        raise AuthError("refresh_token_expired")
    else:
        token.revoked_at = now
        token.revoked_reason = "rotated"

    user = await db.get(User, token.user_id)
    if user is None or user.deleted_at is not None:
        raise AuthError("account_deleted")

    pair, new_token = await issue_tokens(
        db, user, settings, family_id=token.family_id, device_name=token.device_name
    )
    # Сначала INSERT нового токена, иначе UPDATE со ссылкой на него нарушит внешний ключ.
    await db.flush()
    token.replaced_by_id = new_token.id
    return user, pair


async def revoke_refresh_token(db: AsyncSession, raw_token: str) -> None:
    token = await db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_secret(raw_token))
    )
    if token is not None:
        await _revoke_family(db, token.family_id, reason="logout")


async def _revoke_family(db: AsyncSession, family_id: uuid.UUID, *, reason: str) -> None:
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=utcnow(), revoked_reason=reason)
    )


async def auth_providers(db: AsyncSession, user_id: uuid.UUID) -> list[str]:
    rows = await db.scalars(
        select(AuthIdentity.provider)
        .where(AuthIdentity.user_id == user_id)
        .order_by(AuthIdentity.created_at)
    )
    return list(rows)
