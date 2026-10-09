import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

QuestKind = Literal["tasks", "journal", "workouts", "goal_steps", "comeback"]


class SphereIn(BaseModel):
    name: str = Field(min_length=1, max_length=50)
    icon: str = Field(default="⭐", min_length=1, max_length=10)


class SphereUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=50)
    icon: str | None = Field(default=None, min_length=1, max_length=10)
    position: float | None = None


class SphereOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    key: str
    name: str
    icon: str
    position: float
    is_custom: bool = False
    level: int = 1
    xp_in_level: int = 0
    xp_for_next_level: int = 100
    total_xp: int = 0


class QuestOut(BaseModel):
    id: uuid.UUID
    period: Literal["day", "week"]
    period_start: date
    # Последний день задания (включительно).
    period_end: date
    kind: QuestKind
    target: int
    progress: int
    reward: int
    sphere: str | None
    completed_at: datetime | None


class AchievementOut(BaseModel):
    code: str
    achieved_at: datetime | None


class XPEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    source_type: str
    amount: int
    title: str
    sphere: str | None
    created_at: datetime


class ProgressOut(BaseModel):
    level: int
    xp_in_level: int
    xp_for_next_level: int
    total_xp: int
    today_xp: int
    recent: list[XPEventOut]
    spheres: list[SphereOut] = []
    # Дней подряд с опытом; один пропуск серию не рвёт.
    streak_days: int = 0
    quests: list[QuestOut] = []
    # Весь каталог по порядку: achieved_at = null — ещё не получено.
    achievements: list[AchievementOut] = []
