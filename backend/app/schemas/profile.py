import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.schemas.common import HHMM_PATTERN, FactCategory, Weekday


class ScheduleData(BaseModel):
    """Регулярное время. Если end раньше start — интервал переходит через полночь (сон)."""

    weekdays: list[Weekday] = Field(min_length=1, max_length=7)
    start: str = Field(pattern=HHMM_PATTERN)
    end: str = Field(pattern=HHMM_PATTERN)
    busy: bool = True

    @model_validator(mode="after")
    def _check_interval(self) -> "ScheduleData":
        if self.start == self.end:
            raise ValueError("start and end must differ")
        self.weekdays = sorted(set(self.weekdays), key=_weekday_order)
        return self


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
