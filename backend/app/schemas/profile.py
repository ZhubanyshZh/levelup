import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.schemas.common import HHMM_PATTERN, FactCategory, Weekday


class DayInterval(BaseModel):
    weekday: Weekday
    start: str = Field(pattern=HHMM_PATTERN)
    end: str = Field(pattern=HHMM_PATTERN)

    @model_validator(mode="after")
    def _check_interval(self) -> "DayInterval":
        if self.start == self.end:
            raise ValueError("start and end must differ")
        return self


class ScheduleData(BaseModel):
    """Регулярное время. Если end раньше start — интервал переходит через полночь (сон)."""

    weekdays: list[Weekday] = Field(min_length=1, max_length=7)
    start: str = Field(pattern=HHMM_PATTERN)
    end: str = Field(pattern=HHMM_PATTERN)
    busy: bool = True
    day_intervals: list[DayInterval] = Field(default_factory=list, max_length=7)

    @model_validator(mode="after")
    def _check_interval(self) -> "ScheduleData":
        if self.start == self.end:
            raise ValueError("start and end must differ")
        self.weekdays = sorted(set(self.weekdays), key=_weekday_order)
        days = [interval.weekday for interval in self.day_intervals]
        if len(days) != len(set(days)):
            raise ValueError("day intervals must have unique weekdays")
        if not set(days).issubset(self.weekdays):
            raise ValueError("day intervals must belong to selected weekdays")
        self.day_intervals.sort(key=lambda interval: _weekday_order(interval.weekday))
        return self

    def intervals(self) -> list[DayInterval]:
        overrides = {interval.weekday: interval for interval in self.day_intervals}
        return [
            overrides.get(day) or DayInterval(weekday=day, start=self.start, end=self.end)
            for day in self.weekdays
        ]


def _weekday_order(day: str) -> int:
    return ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"].index(day)


class ProfileFactIn(BaseModel):
    category: FactCategory
    text: str = Field(min_length=1, max_length=500)
    schedule: ScheduleData | None = None
    is_active: bool = True


class ProfileFactUpdate(BaseModel):
    category: FactCategory | None = None
    text: str | None = Field(default=None, min_length=1, max_length=500)
    schedule: ScheduleData | None = None
    is_active: bool | None = None


class ProfileFactOut(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: uuid.UUID
    category: FactCategory
    text: str
    # В базе поле называется data (JSONB), наружу — schedule.
    schedule: ScheduleData | None = Field(validation_alias="data")
    is_active: bool
    created_at: datetime
    updated_at: datetime
