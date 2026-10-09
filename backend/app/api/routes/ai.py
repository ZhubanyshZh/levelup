from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import DB, AppSettings, CurrentUser
from app.core.errors import AppError
from app.schemas.ai import AIActiveIn, AICredentialIn, AISettingsOut, AITestOut
from app.schemas.common import AIProviderName
from app.services import ai_settings
from app.services.ai.providers import AIError, ProviderFactory, get_provider_factory

router = APIRouter(prefix="/me/ai", tags=["ai"])

Factory = Annotated[ProviderFactory, Depends(get_provider_factory)]


@router.get("")
async def get_ai_settings(user: CurrentUser, db: DB) -> AISettingsOut:
    return await ai_settings.settings_out(db, user)


@router.put("/active")
async def set_active_provider(body: AIActiveIn, user: CurrentUser, db: DB) -> AISettingsOut:
    await ai_settings.set_active(db, user, body.provider)
    await db.commit()
    return await ai_settings.settings_out(db, user)


@router.put("/{provider}")
async def save_provider(
    provider: AIProviderName, body: AICredentialIn, user: CurrentUser, db: DB
) -> AISettingsOut:
    await ai_settings.save_credential(db, user, provider, body)
    await db.commit()
    return await ai_settings.settings_out(db, user)


@router.delete("/{provider}")
async def delete_provider(provider: AIProviderName, user: CurrentUser, db: DB) -> AISettingsOut:
    await ai_settings.delete_credential(db, user, provider)
    await db.commit()
    return await ai_settings.settings_out(db, user)


@router.post("/{provider}/test")
async def test_provider(
    provider: AIProviderName, user: CurrentUser, db: DB, settings: AppSettings, factory: Factory
) -> AITestOut:
    """Проверяет ключ запросом списка моделей — это бесплатно и не тратит токены."""
    resolved = await ai_settings.resolve(db, user, provider)
    if resolved is None:
        return AITestOut(ok=False, error_code="ai_not_configured")
    client = factory(provider, resolved.api_key, resolved.model, settings.ai_timeout_seconds)
    try:
        models = await client.list_models()
    except AIError as exc:
        return AITestOut(ok=False, error_code=exc.code)
    return AITestOut(ok=True, model_available=resolved.model in models)


@router.get("/{provider}/models")
async def list_models(
    provider: AIProviderName, user: CurrentUser, db: DB, settings: AppSettings, factory: Factory
) -> list[str]:
    resolved = await ai_settings.resolve(db, user, provider)
    if resolved is None:
        raise AppError("ai_not_configured")
    client = factory(provider, resolved.api_key, resolved.model, settings.ai_timeout_seconds)
    return await client.list_models()
