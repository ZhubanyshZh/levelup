import asyncio
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.deps import DB, AppSettings, CurrentUser
from app.models import AuthProvider, User
from app.schemas.auth import (
    AuthResponse,
    DeviceSignInRequest,
    GoogleSignInRequest,
    LinkGoogleRequest,
    LogoutRequest,
    RefreshRequest,
    TokenResponse,
)
from app.schemas.user import UserOut
from app.services import auth as auth_service
from app.services.google import GoogleVerifier, get_google_verifier

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/google")
async def sign_in_with_google(
    body: GoogleSignInRequest,
    db: DB,
    settings: AppSettings,
    verify: Annotated[GoogleVerifier, Depends(get_google_verifier)],
) -> AuthResponse:
    profile = await asyncio.to_thread(verify, body.id_token)
    claims = auth_service.IdentityClaims(
        provider=AuthProvider.GOOGLE,
        subject=profile.subject,
        email=profile.email,
        display_name=profile.name,
        avatar_url=profile.picture,
    )
    return await _sign_in(db, settings, claims, body)


@router.post("/device")
async def sign_in_with_device(
    body: DeviceSignInRequest, db: DB, settings: AppSettings
) -> AuthResponse:
    """Вход без регистрации: аккаунт привязан к секрету, который хранится на устройстве."""
    return await _sign_in(db, settings, auth_service.device_claims(body.device_secret), body)


@router.post("/link/google")
async def link_google(
    body: LinkGoogleRequest,
    user: CurrentUser,
    db: DB,
    verify: Annotated[GoogleVerifier, Depends(get_google_verifier)],
) -> UserOut:
    """Подключить Google к текущему аккаунту (обычно — к аккаунту без регистрации)."""
    profile = await asyncio.to_thread(verify, body.id_token)
    claims = auth_service.IdentityClaims(
        provider=AuthProvider.GOOGLE,
        subject=profile.subject,
        email=profile.email,
        display_name=profile.name,
        avatar_url=profile.picture,
    )
    await auth_service.link_identity(db, user, claims)
    await db.commit()
    return await user_out(db, user)


@router.post("/refresh")
async def refresh(body: RefreshRequest, db: DB, settings: AppSettings) -> TokenResponse:
    _, pair = await auth_service.rotate_refresh_token(db, body.refresh_token, settings)
    await db.commit()
    return TokenResponse(**pair.__dict__)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: LogoutRequest, db: DB) -> None:
    await auth_service.revoke_refresh_token(db, body.refresh_token)
    await db.commit()


async def _sign_in(
    db: DB,
    settings: AppSettings,
    claims: auth_service.IdentityClaims,
    body: GoogleSignInRequest | DeviceSignInRequest,
) -> AuthResponse:
    user, is_new = await auth_service.sign_in_with_identity(db, claims, body)
    pair, _ = await auth_service.issue_tokens(db, user, settings, device_name=body.device_name)
    await db.commit()
    return AuthResponse(**pair.__dict__, user=await user_out(db, user), is_new_user=is_new)


async def user_out(db: DB, user: User) -> UserOut:
    out = UserOut.model_validate(user)
    out.auth_providers = await auth_service.auth_providers(db, user.id)
    return out
