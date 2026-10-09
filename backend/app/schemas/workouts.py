import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator


class SetIn(BaseModel):
    exercise: str = Field(min_length=1, max_length=100)
    weight_kg: float | None = Field(default=None, ge=0, le=1000)
    reps: int | None = Field(default=None, ge=0, le=10000)
    duration_sec: int | None = Field(default=None, ge=0, le=86400)
    distance_m: float | None = Field(default=None, ge=0, le=1_000_000)

    @model_validator(mode="after")
    def _has_measure(self) -> "SetIn":
        if all(v is None for v in (self.weight_kg, self.reps, self.duration_sec, self.distance_m)):
            raise ValueError("set needs weight, reps, duration or distance")
        return self


class WorkoutIn(BaseModel):
    # По умолчанию — сегодня в часовом поясе пользователя.
    workout_date: date | None = None
    started_at: datetime | None = None
    ended_at: datetime | None = None
    title: str | None = Field(default=None, max_length=100)
    note: str | None = Field(default=None, max_length=4000)
    sets: list[SetIn] = Field(min_length=1, max_length=300)


class WorkoutUpdate(BaseModel):
    workout_date: date | None = None
    title: str | None = Field(default=None, max_length=100)
    note: str | None = Field(default=None, max_length=4000)
    # Если передан — заменяет все подходы.
    sets: list[SetIn] | None = Field(default=None, min_length=1, max_length=300)


class SetOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    exercise: str
    weight_kg: float | None
    reps: int | None
    duration_sec: int | None
    distance_m: float | None
    is_pr: bool


class WorkoutOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workout_date: date
    started_at: datetime | None
    ended_at: datetime | None
    title: str | None
    note: str | None
    sets: list[SetOut]
    capture_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime


class WorkoutResult(BaseModel):
    workout: WorkoutOut
    xp_gained: int = 0
    # Упражнения, в которых поставлен личный рекорд.
    records: list[str] = []


class ExercisePoint(BaseModel):
    date: date
    best_weight_kg: float | None
    best_reps: int | None
    volume_kg: float
    best_duration_sec: int | None
    best_distance_m: float | None


class ExerciseStats(BaseModel):
    key: str
    name: str
    sessions: int
    last_date: date
    best_weight_kg: float | None
    best_reps: int | None
    best_duration_sec: int | None
    best_distance_m: float | None
    history: list[ExercisePoint]
