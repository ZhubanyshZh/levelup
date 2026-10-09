"""Повторяющиеся задачи: ближайшие даты по правилу daily / weekly / monthly."""

import calendar
from datetime import date, timedelta
from typing import Any

from app.schemas.common import WEEKDAYS


def normalize(recurrence: dict[str, Any] | None, due_date: date | None) -> dict[str, Any] | None:
    """Дополняет правило тем, что следует из срока: день недели или число месяца."""
    if not recurrence:
        return None
    rule = {"freq": recurrence["freq"], "weekdays": list(recurrence.get("weekdays") or [])}
    if rule["freq"] == "weekly" and not rule["weekdays"] and due_date:
        rule["weekdays"] = [WEEKDAYS[due_date.weekday()]]
    if rule["freq"] == "monthly":
        rule["monthday"] = recurrence.get("monthday") or (due_date.day if due_date else 1)
    return rule


def matches(rule: dict[str, Any], day: date) -> bool:
    freq = rule["freq"]
    if freq == "daily":
        return True
    if freq == "weekly":
        return WEEKDAYS[day.weekday()] in (rule.get("weekdays") or [])
    if freq == "monthly":
        last = calendar.monthrange(day.year, day.month)[1]
        return day.day == min(rule.get("monthday") or 1, last)
    return False


def first_on_or_after(rule: dict[str, Any], start: date) -> date:
    day = start
    # Самый длинный цикл — месяц: за 62 дня совпадение найдётся всегда.
    for _ in range(62):
        if matches(rule, day):
            return day
        day += timedelta(days=1)
    return start


def next_after(rule: dict[str, Any], after: date) -> date:
    return first_on_or_after(rule, after + timedelta(days=1))


def occurrences(rule: dict[str, Any], start: date, until: date) -> list[date]:
    days = []
    day = start
    while day <= until:
        if matches(rule, day):
            days.append(day)
        day += timedelta(days=1)
    return days
