import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.common import HHMM_PATTERN, FactCategory, Priority, Weekday
from app.schemas.daily import JournalOut, ShoppingIn, ShoppingOut
from app.schemas.profile import ProfileFactOut, ScheduleData
from app.schemas.task import Recurrence, TaskOut
from app.schemas.user import validate_timezone

ItemType = Literal[
    "task",
    "profile_fact",
    "journal",
    "shopping",
    "expense",
    "income",
    "workout",
    "goal",
    "question",
    "note",
]
# Типы, которые уже сохраняются в модули. Остальные ждут во «Входящих» своего этапа.
SUPPORTED_ITEM_TYPES: frozenset[str] = frozenset({"task", "profile_fact", "journal", "shopping"})

CaptureSource = Literal["text", "voice", "siri"]
CaptureStatus = Literal["failed", "parsed", "confirmed", "deferred", "undone"]


class ParsedProduct(BaseModel):
    name: str = Field(description="Product as written on a shopping list, nominative case.")
    quantity: str | None = Field(description='Amount like "2", "1 кг", "6 шт", or null.')


class ParsedItem(BaseModel):
    """Схема ответа ИИ.

    Плоская, без значений по умолчанию (null вместо пропуска): так её одинаково строго
    соблюдают OpenAI (strict structured outputs) и Gemini (response_schema).
    """

    type: ItemType
    title: str = Field(
        description="Short title in the user's language without date words. "
        "For profile_fact: the fact itself as a short sentence."
    )
    details: str | None = Field(description="Extra details the user said, or null.")
    due_date: str | None = Field(description="YYYY-MM-DD in the user's timezone, or null.")
    due_time: str | None = Field(description="HH:MM 24h, or null if no time was said.")
    remind: bool = Field(description="True if the user asked to be reminded.")
    priority: Priority
    difficulty: int | None = Field(description="Task effort 1-5, null for other types.")
    fact_category: FactCategory | None = Field(description="Only for profile_fact.")
    schedule_weekdays: list[Weekday] | None = Field(
        description="profile_fact with recurring time: days of week, else null."
    )
    schedule_start: str | None = Field(description="HH:MM start of recurring time, or null.")
    schedule_end: str | None = Field(description="HH:MM end of recurring time, or null.")
    schedule_busy: bool | None = Field(
        description="True if the user is unavailable during that recurring time."
    )
    recurrence: Literal["daily", "weekly", "monthly"] | None = Field(
        description="task: how the task repeats, or null."
    )
    recurrence_weekdays: list[Weekday] | None = Field(
        description="task with weekly recurrence: days of week, else null."
    )
    mood: int | None = Field(description="journal: mood 1-5 if it can be inferred, else null.")
    energy: int | None = Field(description="journal: energy 1-5 if it can be inferred, else null.")
    tags: list[str] | None = Field(
        description="journal: up to 3 short lowercase topics in the user's language, else null."
    )
    products: list[ParsedProduct] | None = Field(
        description="shopping: every product separately, else null."
    )
    shopping_list: str | None = Field(
        description="shopping: list or store name if the user named one, else null."
    )


class ParseResult(BaseModel):
    items: list[ParsedItem]
    reply: str = Field(
        description="One short sentence in the interface language summarizing what you understood."
    )


class BusyConflict(BaseModel):
    fact_id: uuid.UUID
    fact_text: str
    start: str
    end: str


class CaptureItem(BaseModel):
    """Запись в предпросмотре. Клиент может её поправить и прислать обратно в /confirm."""

    type: ItemType
    title: str = Field(min_length=1, max_length=300)
    details: str | None = Field(default=None, max_length=4000)
    due_date: date | None = None
    due_time: str | None = Field(default=None, pattern=HHMM_PATTERN)
    remind: bool = False
    priority: Priority = "normal"
    difficulty: int | None = Field(default=None, ge=1, le=5)
    fact_category: FactCategory | None = None
    schedule: ScheduleData | None = None
    recurrence: Recurrence | None = None
    mood: int | None = Field(default=None, ge=1, le=5)
    energy: int | None = Field(default=None, ge=1, le=5)
    tags: list[str] = Field(default_factory=list, max_length=10)
    products: list[ShoppingIn] = Field(default_factory=list, max_length=100)
    list_name: str | None = Field(default=None, max_length=100)
    include: bool = True
    # Заполняет сервер; присланные клиентом значения пересчитываются.
    supported: bool = False
    conflict: BusyConflict | None = None


class CreatedRef(BaseModel):
    type: Literal["task", "profile_fact", "journal", "shopping"]
    id: uuid.UUID


class CaptureCreate(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    source: CaptureSource = "text"
    # Часовой пояс устройства сейчас — чтобы «завтра» считалось там, где пользователь.
    timezone: str | None = None
    # Для Siri: сохранить сразу, без предпросмотра.
    autosave: bool = False

    _check_timezone = field_validator("timezone")(validate_timezone)

    @field_validator("text")
    @classmethod
    def _strip(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("empty text")
        return stripped


class CaptureConfirm(BaseModel):
    items: list[CaptureItem] = Field(max_length=50)


class CaptureOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    text: str
    source: CaptureSource
    status: CaptureStatus
    error_code: str | None
    reply: str | None
    provider: str | None
    model: str | None
    items: list[CaptureItem]
    created: list[CreatedRef] = Field(validation_alias="created_refs")
    created_at: datetime


class CaptureResult(BaseModel):
    capture: CaptureOut
    tasks: list[TaskOut] = []
    facts: list[ProfileFactOut] = []
    journal: list[JournalOut] = []
    shopping: list[ShoppingOut] = []
    # Опыт, полученный при сохранении (например, за запись в дневнике).
    xp_gained: int = 0
