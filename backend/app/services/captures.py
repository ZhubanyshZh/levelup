"""Единый ввод: сырой текст → ИИ → предпросмотр → подтверждение → записи в модулях."""

import re
import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import date

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError
from app.core.time import utcnow
from app.models import (
    Capture,
    Goal,
    JournalEntry,
    ProfileFact,
    ShoppingItem,
    Task,
    Transaction,
    User,
    Workout,
)
from app.schemas.capture import (
    SUPPORTED_ITEM_TYPES,
    CaptureItem,
    ExerciseEntry,
    ParsedItem,
    ParseResult,
)
from app.schemas.common import format_hhmm, parse_hhmm
from app.schemas.daily import JournalIn, ShoppingIn
from app.schemas.finance import EXPENSE_CATEGORIES, INCOME_CATEGORIES, TransactionIn
from app.schemas.goals import GoalIn
from app.schemas.profile import ScheduleData
from app.schemas.task import Recurrence, TaskCreate
from app.schemas.workouts import SetIn, WorkoutIn
from app.services import ai_settings, daily, finance, goals, spheres, workouts
from app.services.ai.context import ContextBuilder, UserContext
from app.services.ai.providers import AIError, ProviderFactory
from app.services.profile import list_facts
from app.services.schedule import find_busy_conflict
from app.services.tasks import create_task

INBOX_STATUSES = ("failed", "parsed", "deferred")


@dataclass
class CreatedRecords:
    tasks: list[Task] = field(default_factory=list)
    facts: list[ProfileFact] = field(default_factory=list)
    journal: list[JournalEntry] = field(default_factory=list)
    shopping: list[ShoppingItem] = field(default_factory=list)
    transactions: list[Transaction] = field(default_factory=list)
    workouts: list[Workout] = field(default_factory=list)
    goals: list[Goal] = field(default_factory=list)
    xp_gained: int = 0

    @property
    def refs(self) -> list[dict[str, str]]:
        groups = (
            ("task", self.tasks),
            ("profile_fact", self.facts),
            ("journal", self.journal),
            ("shopping", self.shopping),
            ("transaction", self.transactions),
            ("workout", self.workouts),
            ("goal", self.goals),
        )
        return [{"type": kind, "id": str(row.id)} for kind, rows in groups for row in rows]


async def get_capture(db: AsyncSession, user_id: uuid.UUID, capture_id: uuid.UUID) -> Capture:
    capture = await db.get(Capture, capture_id)
    if capture is None or capture.user_id != user_id or capture.deleted_at is not None:
        raise AppError("capture_not_found", status_code=404)
    return capture


async def list_inbox(db: AsyncSession, user_id: uuid.UUID) -> list[Capture]:
    rows = await db.scalars(
        select(Capture)
        .where(
            Capture.user_id == user_id,
            Capture.deleted_at.is_(None),
            Capture.status.in_(INBOX_STATUSES),
        )
        .order_by(Capture.created_at.desc())
    )
    return list(rows)


async def parse_capture(
    db: AsyncSession,
    capture: Capture,
    user: User,
    factory: ProviderFactory,
    settings: Settings,
) -> None:
    """Разбирает ввод через ИИ. При ошибке ввод остаётся во «Входящих» с кодом причины."""
    resolved = await ai_settings.resolve(db, user)
    if resolved is None:
        _fail(capture, "ai_not_configured")
        return

    facts = await list_facts(db, user.id, active_only=True)
    context = UserContext.build(
        timezone=capture.timezone,
        locale=user.locale,
        facts=facts,
        currency=finance.user_currency(user),
        spheres=[(s.key, s.name) for s in await spheres.list_spheres(db, user)],
        goals=[g.title for g in await goals.list_goals(db, user.id) if g.status == "active"],
    )
    provider = factory(
        resolved.provider, resolved.api_key, resolved.model, settings.ai_timeout_seconds
    )
    capture.provider, capture.model = resolved.provider, provider.model

    try:
        result = await provider.parse(
            ContextBuilder(context).parse_instructions(), capture.text, ParseResult
        )
    except AIError as exc:
        _fail(capture, exc.code)
        return

    items = [annotate(normalize_item(raw), facts) for raw in result.items]
    capture.items = [item.model_dump(mode="json") for item in items]
    capture.reply = result.reply.strip()[:500] or None
    capture.status = "parsed"
    capture.error_code = None
    capture.parsed_at = utcnow()


async def confirm_capture(
    db: AsyncSession, user: User, capture: Capture, items: Sequence[CaptureItem]
) -> CreatedRecords:
    if capture.status != "parsed":
        raise AppError("capture_not_confirmable", status_code=409)

    existing_facts = await list_facts(db, user.id, active_only=True)
    annotated = [annotate(item, existing_facts) for item in items]
    created = await _create_records(
        db, user, capture, [i for i in annotated if i.include and i.supported]
    )

    capture.items = [item.model_dump(mode="json") for item in annotated]
    capture.created_refs = created.refs
    has_deferred = any(item.include and not item.supported for item in annotated)
    capture.status = "deferred" if has_deferred else "confirmed"
    capture.confirmed_at = utcnow()
    return created


async def resolve_deferred(db: AsyncSession, user: User) -> None:
    """Записи, которые ждали своих разделов, раскладываются, как только раздел появился.

    Пользователь их уже подтвердил — спрашивать второй раз не нужно.
    """
    rows = await db.scalars(
        select(Capture).where(
            Capture.user_id == user.id,
            Capture.deleted_at.is_(None),
            Capture.status == "deferred",
        )
    )
    for capture in rows:
        items = [CaptureItem.model_validate(item) for item in capture.items]
        ready = [i for i in items if i.include and not i.supported and is_ready(i)]
        if not ready:
            continue
        created = await _create_records(db, user, capture, ready)
        for item in ready:
            item.supported = True
        capture.items = [item.model_dump(mode="json") for item in items]
        capture.created_refs = [*capture.created_refs, *created.refs]
        if not any(item.include and not item.supported for item in items):
            capture.status = "confirmed"


async def undo_capture(db: AsyncSession, user: User, capture: Capture) -> None:
    if capture.status not in ("confirmed", "deferred"):
        raise AppError("capture_not_undoable", status_code=409)
    now = utcnow()
    models = {
        "task": Task,
        "profile_fact": ProfileFact,
        "shopping": ShoppingItem,
        "transaction": Transaction,
        "goal": Goal,
    }
    for ref in capture.created_refs:
        ref_id = uuid.UUID(ref["id"])
        if ref["type"] == "journal":
            entry = await db.get(JournalEntry, ref_id)
            if entry is not None and entry.deleted_at is None:
                await daily.delete_journal(db, user, entry)
            continue
        if ref["type"] == "workout":
            workout = await db.get(Workout, ref_id)
            if workout is not None and workout.deleted_at is None:
                await workouts.delete_workout(db, user, workout)
            continue
        row = await db.get(models[ref["type"]], ref_id)
        if row is not None and row.deleted_at is None:
            row.deleted_at = now
    capture.status = "undone"


async def _create_records(
    db: AsyncSession, user: User, capture: Capture, items: Sequence[CaptureItem]
) -> CreatedRecords:
    created = CreatedRecords()
    for item in items:
        if item.type == "task":
            data = _task_data(item)
            data.sphere = await spheres.valid_key(db, user, item.sphere)
            created.tasks.append(create_task(db, user, data, capture_id=capture.id))
        elif item.type == "profile_fact":
            fact = ProfileFact(
                id=uuid.uuid4(),
                user_id=user.id,
                category=item.fact_category or ("schedule" if item.schedule else "personal"),
                text=item.title,
                data=item.schedule.model_dump() if item.schedule else None,
                is_active=True,
                capture_id=capture.id,
            )
            db.add(fact)
            created.facts.append(fact)
        elif item.type == "journal":
            entry, gained = await daily.create_journal(
                db,
                user,
                JournalIn(
                    entry_date=item.due_date,
                    text=item.details or item.title,
                    mood=item.mood,
                    energy=item.energy,
                    tags=item.tags,
                ),
                summary=item.title if item.details else None,
                capture_id=capture.id,
            )
            created.journal.append(entry)
            created.xp_gained += gained
        elif item.type == "shopping":
            for product in products_of(item):
                created.shopping.append(
                    daily.create_shopping(db, user, product, capture_id=capture.id)
                )
        elif item.type in ("expense", "income") and item.amount:
            created.transactions.append(
                finance.create_transaction(
                    db,
                    user,
                    TransactionIn(
                        kind=item.type,
                        amount=item.amount,
                        currency=item.currency,
                        category=item.category
                        or ("other" if item.type == "expense" else "other_income"),
                        note=item.details or item.title,
                        occurred_on=item.due_date,
                    ),
                    capture_id=capture.id,
                )
            )
        elif item.type == "workout" and item.exercises:
            workout, gained, _ = await workouts.create_workout(
                db,
                user,
                WorkoutIn(
                    workout_date=item.due_date,
                    title=item.title[:100],
                    note=item.details,
                    sets=sets_of(item.exercises),
                ),
                capture_id=capture.id,
            )
            created.workouts.append(workout)
            created.xp_gained += gained
        elif item.type == "goal":
            created.goals.append(
                goals.create_goal(
                    db,
                    user,
                    GoalIn(
                        title=item.title[:200],
                        why=item.details,
                        deadline=item.due_date,
                        metric_unit=item.metric_unit,
                        target_value=item.target_value,
                    ),
                    sphere=await spheres.valid_key(db, user, item.sphere),
                    capture_id=capture.id,
                )
            )
    return created


def sets_of(exercises: Sequence[ExerciseEntry]) -> list[SetIn]:
    """«Присед 3 по 8 с 80» → три одинаковых подхода."""
    result = []
    for exercise in exercises:
        if all(
            v is None
            for v in (exercise.reps, exercise.weight_kg, exercise.duration_sec, exercise.distance_m)
        ):
            continue
        for _ in range(exercise.sets):
            result.append(
                SetIn(
                    exercise=exercise.name,
                    reps=exercise.reps,
                    weight_kg=exercise.weight_kg,
                    duration_sec=exercise.duration_sec,
                    distance_m=exercise.distance_m,
                )
            )
    return result[:300]


def normalize_item(raw: ParsedItem) -> CaptureItem:
    """Ответ ИИ → строгая запись. Всё, что ИИ вернул криво, превращается в null, а не в ошибку."""
    is_task = raw.type == "task"
    is_journal = raw.type == "journal"
    schedule = None
    if raw.type == "profile_fact" and raw.schedule_weekdays and raw.schedule_start:
        try:
            schedule = ScheduleData(
                weekdays=raw.schedule_weekdays,
                start=format_hhmm(parse_hhmm(raw.schedule_start)) or "",
                end=format_hhmm(parse_hhmm(raw.schedule_end)) or "",
                busy=raw.schedule_busy if raw.schedule_busy is not None else True,
            )
        except ValidationError:
            schedule = None

    recurrence = None
    if is_task and raw.recurrence:
        recurrence = Recurrence(freq=raw.recurrence, weekdays=raw.recurrence_weekdays or [])

    item = CaptureItem(
        type=raw.type,
        title=(raw.title or "").strip()[:300] or "…",
        details=(raw.details or "").strip()[:4000] or None,
        due_date=_parse_date(raw.due_date),
        due_time=format_hhmm(parse_hhmm(raw.due_time)),
        remind=bool(raw.remind) and is_task,
        priority=raw.priority,
        difficulty=_clamp(raw.difficulty) if is_task else None,
        fact_category=(raw.fact_category or ("schedule" if schedule else "personal"))
        if raw.type == "profile_fact"
        else None,
        schedule=schedule,
        recurrence=recurrence,
        mood=_clamp(raw.mood) if is_journal else None,
        energy=_clamp(raw.energy) if is_journal else None,
        tags=[t.strip().lower()[:30] for t in (raw.tags or []) if t.strip()][:3]
        if is_journal
        else [],
        list_name=((raw.shopping_list or "").strip()[:100] or None)
        if raw.type == "shopping"
        else None,
    )
    if raw.type in ("expense", "income"):
        item.amount = raw.amount if raw.amount and raw.amount > 0 else None
        item.currency = (raw.currency or "").strip().upper()[:3] or None
        if item.currency and not re.fullmatch(r"[A-Z]{3}", item.currency):
            item.currency = None
        allowed = EXPENSE_CATEGORIES if raw.type == "expense" else INCOME_CATEGORIES
        item.category = raw.category if raw.category in allowed else allowed[-1]
    if raw.type == "workout":
        item.exercises = [
            ExerciseEntry(
                name=e.name.strip()[:100],
                sets=min(max(e.sets or 1, 1), 50),
                reps=_within(e.reps, 10000),
                weight_kg=_within(e.weight_kg, 1000),
                duration_sec=_within(e.duration_sec, 86400),
                distance_m=_within(e.distance_m, 1_000_000),
            )
            for e in raw.exercises or []
            if e.name and e.name.strip()
        ]
    if raw.type == "goal":
        item.target_value = raw.target_value
        item.metric_unit = (raw.metric_unit or "").strip()[:30] or None
    if raw.type in ("task", "goal"):
        item.sphere = raw.sphere
    if raw.type == "shopping":
        item.products = [
            ShoppingIn(name=p.name.strip()[:200], quantity=(p.quantity or "").strip()[:50] or None)
            for p in raw.products or []
            if p.name and p.name.strip()
        ]
    return item


def products_of(item: CaptureItem) -> list[ShoppingIn]:
    """Продукты записи о покупках. Если ИИ их не разделил — делим название по запятым."""
    if item.products:
        return [
            p.model_copy(update={"list_name": p.list_name or item.list_name}) for p in item.products
        ]
    names = [n.strip() for n in re.split(r",|;|\sи\s|\sand\s", item.title) if n.strip()]
    return [
        ShoppingIn(name=(n[:1].upper() + n[1:])[:200], list_name=item.list_name)
        for n in names or [item.title]
    ]


def annotate(item: CaptureItem, facts: Sequence[ProfileFact]) -> CaptureItem:
    conflict = None
    due_time = parse_hhmm(item.due_time)
    if item.type == "task" and item.due_date and due_time:
        conflict = find_busy_conflict(item.due_date, due_time, facts)
    return item.model_copy(update={"supported": is_ready(item), "conflict": conflict})


def is_ready(item: CaptureItem) -> bool:
    """Можно ли сохранить запись в раздел: тип поддержан и данных хватает.

    Трата без суммы или тренировка без упражнений ждут во «Входящих» — их можно поправить.
    """
    if item.type not in SUPPORTED_ITEM_TYPES:
        return False
    if item.type in ("expense", "income"):
        return bool(item.amount)
    if item.type == "workout":
        return bool(sets_of(item.exercises))
    return True


def _task_data(item: CaptureItem) -> TaskCreate:
    return TaskCreate(
        title=item.title,
        notes=item.details,
        priority=item.priority,
        due_date=item.due_date,
        due_time=item.due_time,
        remind=item.remind,
        difficulty=item.difficulty,
        recurrence=item.recurrence,
    )


def _within[N: (int, float)](value: N | None, high: N) -> N | None:
    """Число от 0 до high, иначе null: ИИ мог ошибиться в единицах."""
    return value if value is not None and 0 <= value <= high else None


def _clamp(value: int | None) -> int | None:
    return min(max(value, 1), 5) if value is not None else None


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value.strip()[:10])
    except ValueError:
        return None


def _fail(capture: Capture, code: str) -> None:
    capture.status = "failed"
    capture.error_code = code
