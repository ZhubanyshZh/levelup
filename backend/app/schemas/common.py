from datetime import time
from typing import Literal

HHMM_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"

Weekday = Literal["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
WEEKDAYS: tuple[Weekday, ...] = ("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")

Priority = Literal["low", "normal", "high"]
TaskStatus = Literal["todo", "doing", "done"]
FactCategory = Literal["schedule", "preference", "health", "finance", "focus", "personal"]
AIProviderName = Literal["openai", "gemini"]


def parse_hhmm(value: str | None) -> time | None:
    if not value:
        return None
    try:
        hours, minutes = value.strip().split(":")[:2]
        return time(int(hours), int(minutes))
    except (ValueError, TypeError):
        return None


def format_hhmm(value: time | None) -> str | None:
    return value.strftime("%H:%M") if value else None
