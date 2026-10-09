import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

GoalStatus = Literal["active", "done"]


class GoalIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    why: str | None = Field(default=None, max_length=2000)
    deadline: date | None = None
    metric_unit: str | None = Field(default=None, max_length=30)
    start_value: float | None = None
    current_value: float | None = None
    target_value: float | None = None
    sphere: str | None = Field(default=None, max_length=40)
    steps: list[str] = Field(default_factory=list, max_length=50)


class GoalUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    why: str | None = Field(default=None, max_length=2000)
    deadline: date | None = None
    metric_unit: str | None = Field(default=None, max_length=30)
    start_value: float | None = None
    current_value: float | None = None
    target_value: float | None = None
    sphere: str | None = Field(default=None, max_length=40)
    status: GoalStatus | None = None
    position: float | None = None


class StepIn(BaseModel):
    title: str = Field(min_length=1, max_length=300)


class StepUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=300)
    is_done: bool | None = None
    position: float | None = None


class StepOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    is_done: bool
    done_at: datetime | None
    position: float


class GoalOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    why: str | None
    deadline: date | None
    metric_unit: str | None
    start_value: float | None
    current_value: float | None
    target_value: float | None
    sphere: str | None
    status: GoalStatus
    completed_at: datetime | None
    position: float
    steps: list[StepOut]
    # 0…1: по метрике, если она задана, иначе по шагам.
    progress: float = 0
    capture_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
