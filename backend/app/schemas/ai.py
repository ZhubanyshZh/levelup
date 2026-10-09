from pydantic import BaseModel, Field, field_validator

from app.schemas.common import AIProviderName


class AIProviderOut(BaseModel):
    provider: AIProviderName
    has_key: bool
    key_hint: str | None
    model: str
    default_model: str


class AISettingsOut(BaseModel):
    active_provider: AIProviderName | None
    providers: list[AIProviderOut]


class AICredentialIn(BaseModel):
    """Ключ только на запись: обратно сервер его никогда не отдаёт."""

    api_key: str | None = Field(default=None, min_length=20, max_length=400)
    model: str | None = Field(default=None, min_length=1, max_length=100)

    @field_validator("api_key", "model")
    @classmethod
    def _strip(cls, value: str | None) -> str | None:
        return value.strip() if value else value


class AIActiveIn(BaseModel):
    provider: AIProviderName


class AITestOut(BaseModel):
    ok: bool
    error_code: str | None = None
    # false — ключ рабочий, но выбранной модели у провайдера нет.
    model_available: bool | None = None
