"""Проверка пересечений с занятым временем из «Обо мне».

Делается кодом, а не только ИИ: модель может не заметить пересечение, код — нет.
"""

from collections.abc import Sequence
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from app.models import ProfileFact, Task
from app.schemas.capture import BusyConflict
from app.schemas.common import WEEKDAYS, parse_hhmm
from app.services import recurrence

DEFAULT_REMIND_TIME = time(9, 0)


def find_busy_conflict(
    due_date: date, due_time: time, facts: Sequence[ProfileFact]
) -> BusyConflict | None:
    for fact in facts:
        schedule = fact.data or {}
        if fact.category != "schedule" or not fact.is_active or not schedule.get("busy", True):
            continue
        start, end = parse_hhmm(schedule.get("start")), parse_hhmm(schedule.get("end"))
        if start is None or end is None:
            continue
        weekdays = schedule.get("weekdays") or []
        if start < end:
            hit = WEEKDAYS[due_date.weekday()] in weekdays and start <= due_time < end
        else:
            # Через полночь (сон 23:30–07:00): вечер этого дня или утро после него.
            previous = WEEKDAYS[(due_date - timedelta(days=1)).weekday()]
            hit = (WEEKDAYS[due_date.weekday()] in weekdays and due_time >= start) or (
                previous in weekdays and due_time < end
            )
        if hit:
            return BusyConflict(
                fact_id=fact.id, fact_text=fact.text, start=schedule["start"], end=schedule["end"]
            )
    return None


def compute_remind_at(
    remind: bool, due_date: date | None, due_time: time | None, timezone: str
) -> datetime | None:
    """Момент напоминания в UTC. Без времени — в 09:00 дня срока; без даты — не напоминаем."""
    if not remind or due_date is None:
        return None
    local = datetime.combine(due_date, due_time or DEFAULT_REMIND_TIME, ZoneInfo(timezone))
    return local.astimezone(ZoneInfo("UTC"))


# Напоминания считаем на неделю вперёд: телефон ставит их как локальные уведомления
# и пересчитывает при каждом открытии приложения.
REMINDER_WINDOW_DAYS = 7


def upcoming_reminders(
    task: Task, timezone: str, facts: Sequence[ProfileFact], now: datetime
) -> list[datetime]:
    """Ближайшие напоминания задачи в UTC.

    Повторяющаяся задача напоминает в каждый свой день, даже если прошлый раз не отмечен.
    Если время напоминания попадает на занятое время из «Обо мне», оно сдвигается на конец
    этого интервала — кроме важных задач.
    """
    if not task.remind or task.due_date is None or task.status == "done":
        return []
    tz = ZoneInfo(timezone)
    today = now.astimezone(tz).date()
    remind_time = task.due_time or DEFAULT_REMIND_TIME

    if task.recurrence:
        days = recurrence.occurrences(
            task.recurrence,
            max(task.due_date, today),
            today + timedelta(days=REMINDER_WINDOW_DAYS),
        )
    else:
        days = [task.due_date]

    result = []
    for day in days:
        at = remind_time
        if task.priority != "high":
            conflict = find_busy_conflict(day, at, facts)
            if conflict is not None:
                at = parse_hhmm(conflict.end) or at
        moment = datetime.combine(day, at, tz)
        if moment > now:
            result.append(moment.astimezone(ZoneInfo("UTC")))
    return result
