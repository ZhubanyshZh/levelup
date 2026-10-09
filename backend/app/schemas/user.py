import uuid
from datetime import datetime
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator

Locale = Literal["ru", "en"]


def validate_timezone(value: str | None) -> str | None:
    if value is None:
        return None
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ValueError("unknown timezone") from exc
    return value


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    display_name: str | None
    email: str | None
    avatar_url: str | None
    locale: str
    timezone: str
    currency: str | None
    auth_providers: list[str] = []
    created_at: datetime


class UserUpdate(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=100)
    locale: Locale | None = None
    timezone: str | None = None
    currency: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")

    _check_timezone = field_validator("timezone")(validate_timezone)
