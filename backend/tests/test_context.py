import uuid
from datetime import UTC, date, datetime, time

from openai.lib._pydantic import to_strict_json_schema

from app.models import ProfileFact
from app.schemas.capture import ParseResult
from app.services.ai.context import ContextBuilder, UserContext
from app.services.schedule import find_busy_conflict


def _fact(text: str, weekdays: list[str], start: str, end: str, **extra) -> ProfileFact:
    return ProfileFact(
        id=uuid.uuid4(),
        category="schedule",
        text=text,
        data={"weekdays": weekdays, "start": start, "end": end, "busy": True},
        is_active=extra.get("is_active", True),
        deleted_at=None,
    )


def test_instructions_contain_dates_language_and_facts() -> None:
    juma = _fact("Пятница — жума", ["FRI"], "12:30", "14:00")
    disabled = _fact("Старый график", ["MON"], "09:00", "18:00", is_active=False)
    context = UserContext.build(
        timezone="Asia/Almaty",
        locale="ru",
        facts=[juma, disabled],
        now=datetime(2026, 10, 9, 17, 53, tzinfo=UTC),  # 22:53 в Алматы, пятница
    )

    text = ContextBuilder(context).parse_instructions()

    assert "Now: 2026-10-09 (Friday), 22:53, timezone Asia/Almaty." in text
    assert "Sat 2026-10-10 tomorrow" in text
    assert "[schedule] Пятница — жума (every FRI 12:30-14:00, busy)" in text
    assert "Старый график" not in text
    assert "reply: one short friendly sentence in Russian" in text


def test_english_interface_asks_for_english_reply() -> None:
    context = UserContext.build(timezone="UTC", locale="en", facts=[])

    text = ContextBuilder(context).parse_instructions()

    assert "in English saying" in text
    assert "About the user: nothing known yet." in text


def test_busy_conflict_handles_regular_and_overnight_slots() -> None:
    juma = _fact("Жума", ["FRI"], "12:30", "14:00")
    sleep = _fact("Сон", ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], "23:30", "07:00")
    friday, saturday = date(2026, 10, 16), date(2026, 10, 17)

    assert find_busy_conflict(friday, time(13, 0), [juma]).end == "14:00"
    assert find_busy_conflict(friday, time(14, 0), [juma]) is None
    assert find_busy_conflict(saturday, time(13, 0), [juma]) is None
    assert find_busy_conflict(friday, time(23, 45), [sleep]) is not None
    assert find_busy_conflict(saturday, time(6, 30), [sleep]) is not None
    assert find_busy_conflict(saturday, time(8, 0), [sleep]) is None


def test_fact_without_schedule_does_not_block_tasks() -> None:
    fact = _fact("Гибкий график", ["MON"], "09:00", "18:00")
    fact.data = None
    assert find_busy_conflict(date(2026, 10, 12), time(10), [fact]) is None


def test_parse_schema_is_accepted_by_openai_strict_mode() -> None:
    schema = to_strict_json_schema(ParseResult)

    item = schema["$defs"]["ParsedItem"]
    assert item["additionalProperties"] is False
    assert set(item["required"]) == set(item["properties"])


def test_individual_day_intervals_drive_context_and_conflicts() -> None:
    fact = _fact("Работа", ["MON", "FRI"], "09:00", "18:00")
    fact.data["day_intervals"] = [{"weekday": "FRI", "start": "12:30", "end": "14:00"}]
    monday, friday = date(2026, 10, 12), date(2026, 10, 16)

    assert find_busy_conflict(monday, time(10), [fact]).end == "18:00"
    assert find_busy_conflict(friday, time(10), [fact]) is None
    assert find_busy_conflict(friday, time(13), [fact]).end == "14:00"
    assert find_busy_conflict(friday, time(14), [fact]) is None
    context = UserContext.build(timezone="UTC", locale="ru", facts=[fact])
    assert "every MON 09:00-18:00; FRI 12:30-14:00, busy" in ContextBuilder(context).context_block()


def test_individual_overnight_interval_uses_previous_days_times() -> None:
    fact = _fact("Сон", ["FRI", "SAT"], "23:30", "07:00")
    fact.data["day_intervals"] = [{"weekday": "SAT", "start": "22:00", "end": "09:00"}]
    saturday, sunday = date(2026, 10, 17), date(2026, 10, 18)

    assert find_busy_conflict(saturday, time(6, 30), [fact]).end == "07:00"
    assert find_busy_conflict(saturday, time(8), [fact]) is None
    assert find_busy_conflict(sunday, time(8), [fact]).end == "09:00"
    assert find_busy_conflict(sunday, time(9), [fact]) is None


def test_reminders_use_individual_day_end_including_next_morning() -> None:
    from app.models import Task
    from app.services.schedule import upcoming_reminders

    fact = _fact("Работа", ["MON", "FRI"], "09:00", "18:00")
    fact.data["day_intervals"] = [{"weekday": "FRI", "start": "12:30", "end": "14:00"}]
    task = Task(
        remind=True,
        status="todo",
        priority="normal",
        due_date=date(2026, 10, 16),
        due_time=time(13),
        recurrence=None,
    )
    now = datetime(2026, 10, 16, tzinfo=UTC)
    assert upcoming_reminders(task, "UTC", [fact], now) == [datetime(2026, 10, 16, 14, tzinfo=UTC)]
    fact.data["day_intervals"] = [{"weekday": "FRI", "start": "23:00", "end": "07:00"}]
    task.due_time = time(23, 30)
    assert upcoming_reminders(task, "UTC", [fact], now) == [datetime(2026, 10, 17, 7, tzinfo=UTC)]
