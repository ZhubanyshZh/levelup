from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.schemas.user import UserOut, validate_timezone


class ClientInfo(BaseModel):
    """Что приложение сообщает о себе при входе. Используется только для нового аккаунта."""

    locale: str | None = Field(default=None, max_length=35)
    timezone: str | None = Field(default=None, max_length=64)
    device_name: str | None = Field(default=None, max_length=100)

    _check_timezone = field_validator("timezone")(validate_timezone)


class GoogleSignInRequest(ClientInfo):
    id_token: str = Field(min_length=20)


class LinkGoogleRequest(BaseModel):
    id_token: str = Field(min_length=20)


class DeviceSignInRequest(ClientInfo):
    # Случайный секрет, который приложение создаёт один раз и хранит в Keychain.
    device_secret: str = Field(min_length=32, max_length=256)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20)


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=20)


class TokenResponse(BaseModel):
    token_type: str = "bearer"
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime


class AuthResponse(TokenResponse):
    user: UserOut
    is_new_user: bool
