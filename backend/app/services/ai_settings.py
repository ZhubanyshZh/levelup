import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.crypto import DecryptionError, get_secret_box
from app.core.errors import AppError
from app.models import AICredential, User
from app.schemas.ai import AICredentialIn, AIProviderOut, AISettingsOut
from app.services.ai.providers import DEFAULT_MODELS


@dataclass(frozen=True)
class ResolvedAI:
    provider: str
    api_key: str
    model: str


def _crypto_context(user_id: uuid.UUID, provider: str) -> str:
    return f"ai-key:{user_id}:{provider}"


async def _credentials(db: AsyncSession, user_id: uuid.UUID) -> dict[str, AICredential]:
    rows = await db.scalars(select(AICredential).where(AICredential.user_id == user_id))
    return {row.provider: row for row in rows}


async def settings_out(db: AsyncSession, user: User) -> AISettingsOut:
    credentials = await _credentials(db, user.id)
    providers = []
    for provider, default_model in DEFAULT_MODELS.items():
        credential = credentials.get(provider)
        providers.append(
            AIProviderOut(
                provider=provider,  # type: ignore[arg-type]
                has_key=credential is not None,
                key_hint=credential.key_hint if credential else None,
                model=(credential.model if credential else None) or default_model,
                default_model=default_model,
            )
        )
    return AISettingsOut(active_provider=user.ai_provider, providers=providers)  # type: ignore[arg-type]


async def save_credential(
    db: AsyncSession, user: User, provider: str, body: AICredentialIn
) -> None:
    credential = (await _credentials(db, user.id)).get(provider)
    if credential is None:
        if not body.api_key:
            raise AppError("ai_key_required")
        credential = AICredential(user_id=user.id, provider=provider)
        db.add(credential)
    if body.api_key:
        credential.encrypted_key = get_secret_box().encrypt(
            body.api_key, context=_crypto_context(user.id, provider)
        )
        credential.key_hint = f"…{body.api_key[-4:]}"
    if body.model is not None:
        credential.model = body.model
    if user.ai_provider is None:
        user.ai_provider = provider


async def delete_credential(db: AsyncSession, user: User, provider: str) -> None:
    credentials = await _credentials(db, user.id)
    credential = credentials.pop(provider, None)
    if credential is not None:
        await db.delete(credential)
    if user.ai_provider == provider:
        user.ai_provider = next(iter(credentials), None)


async def set_active(db: AsyncSession, user: User, provider: str) -> None:
    if provider not in await _credentials(db, user.id):
        raise AppError("ai_not_configured")
    user.ai_provider = provider


async def resolve(db: AsyncSession, user: User, provider: str | None = None) -> ResolvedAI | None:
    """Ключ и модель для запроса к ИИ. None — ИИ не настроен (или ключ не расшифровать)."""
    provider = provider or user.ai_provider
    if provider is None:
        return None
    credential = (await _credentials(db, user.id)).get(provider)
    if credential is None:
        return None
    try:
        api_key = get_secret_box().decrypt(
            credential.encrypted_key, context=_crypto_context(user.id, provider)
        )
    except DecryptionError:
        return None
    return ResolvedAI(provider, api_key, credential.model or DEFAULT_MODELS[provider])
