import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


def _clean_tags(tags: list[str]) -> list[str]:
    seen: list[str] = []
    for tag in tags:
        value = tag.strip().lower()[:30]
        if value and value not in seen:
            seen.append(value)
    return seen[:10]


class JournalIn(BaseModel):
    # По умолчанию — сегодня в часовом поясе пользователя.
    entry_date: date | None = None
    text: str = Field(min_length=1, max_length=10000)
    mood: int | None = Field(default=None, ge=1, le=5)
    energy: int | None = Field(default=None, ge=1, le=5)
    tags: list[str] = Field(default_factory=list, max_length=20)

    _tags = field_validator("tags")(_clean_tags)


class JournalUpdate(BaseModel):
    entry_date: date | None = None
    text: str | None = Field(default=None, min_length=1, max_length=10000)
    mood: int | None = Field(default=None, ge=1, le=5)
    energy: int | None = Field(default=None, ge=1, le=5)
    tags: list[str] | None = Field(default=None, max_length=20)

    @field_validator("tags")
    @classmethod
    def _tags(cls, value: list[str] | None) -> list[str] | None:
        return _clean_tags(value) if value is not None else None


class JournalOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entry_date: date
    text: str
    summary: str | None
    mood: int | None
    energy: int | None
    tags: list[str]
    capture_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime


class ShoppingIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    quantity: str | None = Field(default=None, max_length=50)
    list_name: str | None = Field(default=None, max_length=100)


class ShoppingUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    quantity: str | None = Field(default=None, max_length=50)
    list_name: str | None = Field(default=None, max_length=100)
    is_bought: bool | None = None
    position: float | None = None


class ShoppingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    quantity: str | None
    list_name: str | None
    is_bought: bool
    bought_at: datetime | None
    position: float
    created_at: datetime
    updated_at: datetime
