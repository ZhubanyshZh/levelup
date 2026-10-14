import uuid
from datetime import date, datetime, time
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, FiniteFloat, field_validator

from app.schemas.common import HHMM_PATTERN, Priority, TaskStatus, Weekday, format_hhmm


class Recurrence(BaseModel):
    """Повтор задачи. Для weekly без дней недели берётся день недели срока."""

    freq: Literal["daily", "weekly", "monthly"]
    weekdays: list[Weekday] = Field(default_factory=list, max_length=7)
    # День месяца для monthly; заполняет сервер из срока.
    monthday: int | None = Field(default=None, ge=1, le=31)


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=300)
    notes: str | None = Field(default=None, max_length=4000)
    status: TaskStatus = "todo"
    priority: Priority = "normal"
    due_date: date | None = None
    due_time: str | None = Field(default=None, pattern=HHMM_PATTERN)
    remind: bool = False
    difficulty: int | None = Field(default=None, ge=1, le=5)
    recurrence: Recurrence | None = None
    position: FiniteFloat | None = None
    sphere: str | None = Field(default=None, max_length=40)
    goal_id: uuid.UUID | None = None


class TaskUpdate(BaseModel):
    """Частичное обновление: передаются только меняющиеся поля, null очищает значение."""

    title: str | None = Field(default=None, min_length=1, max_length=300)
    notes: str | None = Field(default=None, max_length=4000)
    status: TaskStatus | None = None
    priority: Priority | None = None
    due_date: date | None = None
    due_time: str | None = Field(default=None, pattern=HHMM_PATTERN)
    remind: bool | None = None
    difficulty: int | None = Field(default=None, ge=1, le=5)
    recurrence: Recurrence | None = None
    position: FiniteFloat | None = None
    sphere: str | None = Field(default=None, max_length=40)
    goal_id: uuid.UUID | None = None


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    notes: str | None
    status: TaskStatus
    priority: Priority
    due_date: date | None
    due_time: str | None
    remind: bool
    # Ближайшее напоминание и все напоминания на неделю вперёд — с учётом повторов
    # и занятого времени из «Обо мне». Телефон ставит по ним локальные уведомления.
    remind_at: datetime | None
    reminders: list[datetime] = []
    recurrence: Recurrence | None
    difficulty: int | None
    sphere: str | None = None
    goal_id: uuid.UUID | None = None
    position: float
    completed_at: datetime | None
    capture_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime

    @field_validator("due_time", mode="before")
    @classmethod
    def _format_time(cls, value: object) -> object:
        return format_hhmm(value) if isinstance(value, time) else value


class TaskQuery(BaseModel):
    """Фильтры исполняются в SQL; limit ограничивает любую выдачу."""

    due: Literal["any", "overdue", "today", "tomorrow", "nextSevenDays", "noDate"] = "any"
    priority: Priority | None = None
    sphere: str | None = Field(default=None, max_length=40)
    goal_id: uuid.UUID | None = None
    status: TaskStatus | None = None
    q: str = Field(default="", max_length=200)
    view: Literal["all", "today", "widgets", "reminders"] = "all"
    sort: Literal["due", "position"] = "due"
    limit: int = Field(default=50, ge=1, le=100)
    cursor: str | None = Field(default=None, max_length=2048)

    @field_validator("q")
    @classmethod
    def _normalize_query(cls, value: str) -> str:
        return " ".join(value.split())


class TaskPage(BaseModel):
    items: list[TaskOut]
    next_cursor: str | None = None
