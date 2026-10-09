from functools import lru_cache
from typing import Annotated

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    environment: str = "development"
    database_url: str = "postgresql+asyncpg://levelup:levelup@localhost:5433/levelup"

    jwt_secret: str = Field(min_length=32)
    jwt_algorithm: str = "HS256"
    jwt_issuer: str = "levelup"
    access_token_ttl_minutes: int = 60
    refresh_token_ttl_days: int = 180
    # Повторное использование уже обменянного refresh-токена в этом окне не считается атакой:
    # так бывает, когда ответ на /auth/refresh потерялся в сети и клиент повторил запрос.
    refresh_reuse_leeway_seconds: int = 60

    # Client ID из Google Cloud Console (iOS-клиент), через запятую.
    google_client_ids: Annotated[list[str], NoDecode] = []

    # 32 байта в base64 — шифрует ключи ИИ пользователей (AES-GCM).
    # Если его потерять, пользователям придётся ввести ключи заново.
    encryption_key: str = Field(min_length=43)
    ai_timeout_seconds: float = 40

    @field_validator("google_client_ids", mode="before")
    @classmethod
    def _split_client_ids(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
