"""ContextBuilder — единственное место, где собирается контекст для запросов к ИИ.

Правило проекта: любой вызов ИИ получает инструкции отсюда, чтобы дата, часовой пояс,
язык и факты «Обо мне» учитывались всегда, а не «где не забыли».
"""

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.core.time import utcnow
from app.models import ProfileFact
from app.schemas.common import WEEKDAYS

LANGUAGE_NAMES = {"ru": "Russian", "en": "English"}
WEEKDAY_NAMES = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

PARSE_RULES = """\
You are the input parser of "Level Up", a personal organizer app.
The user dictates or types free-form notes in Russian or English (often mixed, often with
speech-recognition mistakes). Split the input into separate items and classify each one.

Item types:
- task: something the user needs to do. A request to be reminded ("напомни ...") is a task
  with remind=true.
- profile_fact: a LASTING fact about the user that should shape future planning: recurring busy
  time (work hours, prayers, classes, sleep), preferences ("I train in the mornings"), health or
  diet constraints, finance facts (payday, budget), long-term focus or values, personal info.
  A one-off event is NOT a profile_fact (it is a task).
- journal: reflection about the user's day, mood or feelings.
- shopping: things to buy. One item per shopping list: put every product into products
  (name as on a shopping list, nominative case; quantity like "2", "1 кг" or null);
  title is a short summary of the list; shopping_list is a store or list name if the user
  named one ("в Магнуме", "для дачи"), else null.
- expense / income: money spent or received.
- workout: exercise the user performed.
- goal: a long-term objective.
- question: a question about the user's own data.
- note: anything else worth keeping.

Rules:
- Never invent items the user did not say. Keep the user's language in titles.
- Resolve relative dates ("завтра", "в пятницу", "через 2 часа") using the dates listed below.
  A weekday name means its nearest upcoming date (today if it is today and the time is still ahead).
- due_time only if a time was said; otherwise null. "утром" = 09:00, "днём" = 13:00,
  "вечером" = 19:00, "после обеда" = 14:00.
- title: a short imperative phrase without date/time words.
- remind: true if the user asked to be reminded or named an exact time for a task.
- priority: high for urgent/important ("срочно", "важно", "обязательно"), low for
  "когда-нибудь", otherwise normal.
- difficulty (tasks only): 1 = a few minutes, 2 = under an hour, 3 = a few hours, 4 = a day,
  5 = several days. Null for other types.
- Repeating tasks ("каждый понедельник", "ежедневно", "раз в месяц"): set recurrence
  (daily | weekly | monthly) and for weekly also recurrence_weekdays; due_date is the first
  occurrence. A request to "remind every Monday" is a repeating task with remind=true.
- journal: title is a one-line summary; details is the full entry in the user's own words
  (fix obvious speech-recognition errors, keep the meaning); due_date only if the user talks
  about another day ("вчера"). mood and energy 1-5 (1 = very bad, 5 = great) when they can be
  inferred, else null. tags: up to 3 short lowercase topics in the user's language.
- profile_fact: title is the fact as a short sentence; fill fact_category. For recurring time
  fill schedule_weekdays, schedule_start, schedule_end and schedule_busy (true if the user is
  unavailable then). Otherwise schedule fields are null.
- Fields that do not apply to an item are null (remind=false, priority=normal).
  A recurring busy time of the user (prayer, work hours) is a profile_fact, not a task.
- Take "About the user" into account when interpreting the input.
- reply: one short friendly sentence in {language} saying what you understood.
"""


@dataclass(frozen=True)
class UserContext:
    now: datetime
    timezone: str
    locale: str
    facts: Sequence[ProfileFact]

    @classmethod
    def build(
        cls,
        *,
        timezone: str,
        locale: str,
        facts: Sequence[ProfileFact],
        now: datetime | None = None,
    ) -> "UserContext":
        tz = ZoneInfo(timezone)
        return cls(
            now=(now or utcnow()).astimezone(tz),
            timezone=timezone,
            locale=locale,
            facts=[fact for fact in facts if fact.is_active and fact.deleted_at is None],
        )


class ContextBuilder:
    def __init__(self, context: UserContext) -> None:
        self.context = context

    @property
    def language(self) -> str:
        return LANGUAGE_NAMES.get(self.context.locale, "Russian")

    def parse_instructions(self) -> str:
        return PARSE_RULES.format(language=self.language) + "\n" + self.context_block()

    def context_block(self) -> str:
        now = self.context.now
        lines = [
            f"Now: {now:%Y-%m-%d} ({WEEKDAY_NAMES[now.weekday()]}), {now:%H:%M}, "
            f"timezone {self.context.timezone}.",
            f"Interface language: {self.language}.",
            "Upcoming dates: " + ", ".join(self._upcoming_dates()) + ".",
            "",
        ]
        if self.context.facts:
            lines.append("About the user (always respect this):")
            lines.extend(f"- {describe_fact(fact)}" for fact in self.context.facts)
        else:
            lines.append("About the user: nothing known yet.")
        return "\n".join(lines)

    def _upcoming_dates(self) -> list[str]:
        today = self.context.now.date()
        labels = []
        for offset in range(8):
            day = today + timedelta(days=offset)
            suffix = " today" if offset == 0 else " tomorrow" if offset == 1 else ""
            labels.append(f"{WEEKDAY_NAMES[day.weekday()][:3]} {day:%Y-%m-%d}{suffix}")
        return labels


def describe_fact(fact: ProfileFact) -> str:
    text = f"[{fact.category}] {fact.text}"
    schedule = fact.data or {}
    if schedule.get("weekdays"):
        days = ",".join(day for day in WEEKDAYS if day in schedule["weekdays"])
        busy = ", busy" if schedule.get("busy", True) else ""
        text += f" (every {days} {schedule['start']}-{schedule['end']}{busy})"
    return text
