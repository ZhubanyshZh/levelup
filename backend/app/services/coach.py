"""ИИ предлагает; код проверяет расписание и считает данные; пользователь принимает."""

import hashlib
import json
import uuid
from datetime import date, datetime, time, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError
from app.core.time import utcnow
from app.models import (
    Capture,
    CoachAnswer,
    CoachReport,
    Goal,
    JournalEntry,
    Quest,
    Task,
    Transaction,
    User,
    Workout,
    XPEvent,
)
from app.schemas.coach import (
    CoachAction,
    CoachDraft,
    CoachReportOut,
    QuestionAnswer,
    QuestionPlan,
    QuestionRequest,
)
from app.schemas.common import parse_hhmm
from app.schemas.task import TaskCreate
from app.services import ai_settings, captures, finance, goals, spheres, tasks, xp
from app.services.ai.context import ContextBuilder, UserContext
from app.services.ai.providers import AIError, ProviderFactory
from app.services.profile import list_facts
from app.services.schedule import find_busy_conflict


async def _lock(db: AsyncSession, key: str) -> None:
    # Защищает от двойных платных запросов при одновременном открытии экранов.
    number = int.from_bytes(hashlib.sha256(key.encode()).digest()[:8]) & ((1 << 63) - 1)
    await db.execute(select(func.pg_advisory_xact_lock(number)))


async def _context(db: AsyncSession, user: User) -> UserContext:
    return UserContext.build(
        timezone=user.timezone,
        locale=user.locale,
        facts=await list_facts(db, user.id, active_only=True),
        currency=finance.user_currency(user),
        spheres=[(s.key, s.name) for s in await spheres.list_spheres(db, user)],
        goals=[g.title for g in await goals.list_goals(db, user.id) if g.status == "active"],
    )


async def _provider(db: AsyncSession, user: User, factory: ProviderFactory, settings: Settings):
    resolved = await ai_settings.resolve(db, user)
    if resolved is None:
        raise AIError("ai_not_configured", status_code=400)
    return factory(resolved.provider, resolved.api_key, resolved.model, settings.ai_timeout_seconds)


def _date(value: str | None) -> date | None:
    try:
        return date.fromisoformat(value or "")
    except ValueError:
        return None


def report_out(report: CoachReport) -> CoachReportOut:
    actions = [CoachAction.model_validate(a) for a in report.content["actions"]]
    for action in actions:
        if str(action.id) in report.applied:
            action.applied_id = uuid.UUID(report.applied[str(action.id)])
    return CoachReportOut(
        id=report.id,
        kind=report.kind,
        period_start=report.period_start,
        goal_id=report.goal_id,
        created_at=report.created_at,
        **{k: v for k, v in report.content.items() if k != "actions"},
        actions=actions,
    )


async def list_reports(db: AsyncSession, user: User) -> list[CoachReportOut]:
    rows = await db.scalars(
        select(CoachReport)
        .where(
            CoachReport.user_id == user.id,
            CoachReport.locale == user.locale,
            CoachReport.timezone == user.timezone,
        )
        .order_by(CoachReport.created_at.desc())
        .limit(30)
    )
    return [report_out(row) for row in rows]


async def generate(
    db: AsyncSession,
    user: User,
    kind: str,
    goal_id: uuid.UUID | None,
    factory: ProviderFactory,
    settings: Settings,
) -> CoachReport:
    goal = await goals.get_goal(db, user.id, goal_id) if goal_id else None
    if (kind == "goal") != (goal is not None):
        raise AppError("coach_goal_required", status_code=422)
    if goal and goal.status != "active":
        raise AppError("coach_goal_completed", status_code=409)
    today = xp.local_today(user)
    period = today - timedelta(days=today.weekday() + 7) if kind == "weekly" else today
    suffix = json.dumps(goals.present(goal).model_dump(mode="json"), sort_keys=True) if goal else ""
    key = hashlib.sha256(
        f"{kind}:{period}:{user.locale}:{user.timezone}{suffix}".encode()
    ).hexdigest()
    await _lock(db, f"coach:{user.id}:{key}")
    existing = await db.scalar(
        select(CoachReport).where(CoachReport.user_id == user.id, CoachReport.cache_key == key)
    )
    if existing:
        return existing
    provider = await _provider(db, user, factory, settings)
    context = await _context(db, user)
    open_tasks = list(
        await db.scalars(
            select(Task)
            .where(Task.user_id == user.id, Task.deleted_at.is_(None), Task.status != "done")
            .order_by(Task.due_date.asc().nulls_last(), Task.position)
            .limit(40)
        )
    )
    start, end = (period, period + timedelta(days=6)) if kind == "weekly" else (today, today)
    payload = {
        "period_start": str(start),
        "period_end": str(end),
        "statistics": await _stats(db, user, start, end),
        "tasks": [
            {
                "id": str(t.id),
                "title": t.title,
                "priority": t.priority,
                "due_date": str(t.due_date) if t.due_date else None,
                "due_time": t.due_time.strftime("%H:%M") if t.due_time else None,
                "goal_id": str(t.goal_id) if t.goal_id else None,
            }
            for t in open_tasks
        ],
        "goals": [
            goals.present(g).model_dump(mode="json")
            for g in await goals.list_goals(db, user.id)
            if g.status == "active"
        ][:20],
        "selected_goal": goals.present(goal).model_dump(mode="json") if goal else None,
        "journal": [
            {"date": str(j.entry_date), "text": j.text[:1500], "mood": j.mood, "energy": j.energy}
            for j in await db.scalars(
                select(JournalEntry)
                .where(
                    JournalEntry.user_id == user.id,
                    JournalEntry.deleted_at.is_(None),
                    JournalEntry.entry_date.between(start, end),
                )
                .order_by(JournalEntry.created_at.desc())
                .limit(10)
            )
        ],
        "quests": [
            {"kind": q.kind, "target": q.target, "period": q.period, "sphere": q.sphere}
            for q in await db.scalars(
                select(Quest).where(
                    Quest.user_id == user.id,
                    Quest.completed_at.is_(None),
                    Quest.period_start >= today - timedelta(days=today.weekday()),
                )
            )
        ],
        "previous_statistics": await _stats(
            db, user, start - timedelta(days=7), end - timedelta(days=7)
        )
        if kind == "weekly"
        else None,
    }
    draft = await provider.parse(
        ContextBuilder(context).coach_instructions(kind),
        json.dumps(payload, ensure_ascii=False),
        CoachDraft,
    )
    actions = []
    seen = {s.title.casefold().strip() for s in goal.steps} if goal else set()
    known_tasks = {str(t.id): t for t in open_tasks}
    for raw in draft.actions[
        : 8 if kind == "goal" else 5 if kind == "morning" else 3 if kind == "weekly" else 0
    ]:
        identity = raw.task_id or raw.title.casefold().strip()
        if not raw.title.strip() or identity in seen:
            continue
        seen.add(identity)
        linked = known_tasks.get(raw.task_id) if raw.task_id else None
        if raw.task_id and linked is None:
            continue
        if kind == "goal" and raw.task_id:
            continue
        day = _date(raw.due_date)
        at = parse_hhmm(raw.due_time)
        if kind == "morning":
            day = today
        if kind == "goal":
            day, at = None, None
        if day is None:
            at = None
        if day and day < today:
            day, at = today, None
        duration = min(max(raw.duration_minutes, 5), 120)
        # Проверяем весь интервал, включая конец подхода к занятому времени и ночь.
        conflict = interval_conflict(day, at, duration, context.facts) if day and at else None
        if day and at:
            local = datetime.combine(day, at, context.now.tzinfo)
            if (
                local < context.now
                or any(overlaps(day, at, duration, a) for a in actions)
                or await _task_conflict(
                    db, user.id, day, at, duration, linked.id if linked else None
                )
            ):
                at = None
        action = CoachAction(
            id=uuid.uuid4(),
            title=raw.title.strip()[:300],
            notes=(raw.notes or "").strip()[:2000] or None,
            due_date=day,
            due_time=at.strftime("%H:%M") if at else None,
            duration_minutes=duration,
            difficulty=min(max(raw.difficulty, 1), 5),
            sphere=await spheres.valid_key(db, user, raw.sphere),
            task_id=linked.id if linked else None,
            conflict=conflict if at else None,
        )
        actions.append(action)
    report = CoachReport(
        id=uuid.uuid4(),
        user_id=user.id,
        kind=kind,
        period_start=period,
        cache_key=key,
        locale=user.locale,
        timezone=user.timezone,
        goal_id=goal_id,
        provider=provider.name,
        model=provider.model,
        applied={},
        content={
            "title": draft.title.strip()[:120],
            "message": draft.message.strip()[:2000],
            "highlights": [h.strip()[:500] for h in draft.highlights[:5] if h.strip()],
            "reflection_question": (draft.reflection_question or "").strip()[:500]
            or (
                "Что сегодня получилось и что помогло тебе?"
                if user.locale == "ru"
                else "What went well today, and what helped you?"
            )
            if kind == "evening"
            else None,
            "actions": [a.model_dump(mode="json") for a in actions],
        },
    )
    db.add(report)
    await db.flush()
    return report


def interval_conflict(day: date, at: time, duration: int, facts):
    start = datetime.combine(day, at)
    for minute in range(duration):
        moment = start + timedelta(minutes=minute)
        conflict = find_busy_conflict(moment.date(), moment.time(), facts)
        if conflict:
            return conflict
    return None


def overlaps(day: date, at: time, duration: int, action: CoachAction) -> bool:
    if action.due_date is None or action.due_time is None:
        return False
    start = datetime.combine(day, at)
    other = datetime.combine(action.due_date, parse_hhmm(action.due_time))
    return start < other + timedelta(minutes=action.duration_minutes) and other < start + timedelta(
        minutes=duration
    )


async def _task_conflict(
    db: AsyncSession,
    user_id: uuid.UUID,
    day: date,
    at: time,
    duration: int,
    exclude: uuid.UUID | None,
) -> bool:
    start = datetime.combine(day, at)
    end = start + timedelta(minutes=duration)
    query = select(Task).where(
        Task.user_id == user_id,
        Task.deleted_at.is_(None),
        Task.status != "done",
        Task.due_date.between(day, end.date()),
        Task.due_time.is_not(None),
    )
    if exclude:
        query = query.where(Task.id != exclude)
    # У обычных задач нет длительности: защищаем их записанное время начала.
    return any(
        start <= datetime.combine(t.due_date, t.due_time) < end for t in await db.scalars(query)
    )


async def apply_action(
    db: AsyncSession,
    user: User,
    report_id: uuid.UUID,
    action_id: uuid.UUID,
    unscheduled: bool = False,
):
    report = await db.scalar(
        select(CoachReport)
        .where(CoachReport.id == report_id, CoachReport.user_id == user.id)
        .with_for_update()
    )
    if report is None:
        raise AppError("coach_report_not_found", status_code=404)
    action = next((a for a in report_out(report).actions if a.id == action_id), None)
    if action is None:
        raise AppError("coach_action_not_found", status_code=404)
    if report.goal_id:
        await db.execute(
            select(Goal.id)
            .where(Goal.id == report.goal_id, Goal.user_id == user.id)
            .with_for_update()
        )
    goal = await goals.get_goal(db, user.id, report.goal_id) if report.goal_id else None
    if action.applied_id:
        task = await tasks.get_task(db, user.id, action.applied_id) if goal is None else None
        return report, task, goal
    if goal:
        if goal.status != "active":
            raise AppError("coach_goal_completed", status_code=409)
        step = next(
            (
                s
                for s in goal.steps
                if s.title.strip().casefold() == action.title.strip().casefold()
            ),
            None,
        )
        step = step or goals.add_step(goal, action.title)
        created_id, task = step.id, None
    else:
        if unscheduled:
            action.due_time, action.conflict = None, None
            if action.due_date and action.due_date < xp.local_today(user):
                action.due_date = xp.local_today(user)
            report.content = {
                **report.content,
                "actions": [
                    action.model_dump(mode="json") if a["id"] == str(action.id) else a
                    for a in report.content["actions"]
                ],
            }
        facts = await list_facts(db, user.id, active_only=True)
        if action.due_date and action.due_time:
            if interval_conflict(
                action.due_date, parse_hhmm(action.due_time), action.duration_minutes, facts
            ) or await _task_conflict(
                db,
                user.id,
                action.due_date,
                parse_hhmm(action.due_time),
                action.duration_minutes,
                action.task_id,
            ):
                raise AppError("coach_busy_conflict", status_code=409)
            if (
                datetime.combine(
                    action.due_date,
                    parse_hhmm(action.due_time),
                    UserContext.build(
                        timezone=user.timezone, locale=user.locale, facts=[]
                    ).now.tzinfo,
                )
                < utcnow()
            ):
                raise AppError("coach_plan_expired", status_code=409)
        data = TaskCreate(
            title=action.title,
            notes=action.notes,
            due_date=action.due_date,
            due_time=action.due_time,
            difficulty=action.difficulty,
            sphere=action.sphere,
            remind=action.due_time is not None,
        )
        data.sphere = await spheres.valid_key(db, user, data.sphere)
        if action.task_id:
            task = await tasks.get_task(db, user.id, action.task_id)
            if task.status == "done":
                raise AppError("coach_task_changed", status_code=409)
            # План меняет только расписание, сохраняя текст, приоритет и связь с целью.
            await tasks.update_task(
                db,
                user,
                task,
                {"due_date": data.due_date, "due_time": data.due_time, "remind": data.remind},
            )
        else:
            task = tasks.create_task(db, user, data)
        created_id = task.id
    report.applied = {**report.applied, str(action_id): str(created_id)}
    await db.flush()
    return report, task, goal


async def _stats(db: AsyncSession, user: User, start: date, end: date) -> dict:
    result = {}
    for metric in ("expense", "income", "workouts", "journal_days", "tasks_done", "xp"):
        result[metric] = await count_data(
            db, user, metric, start, end, None, finance.user_currency(user), None
        )
    result["currency"] = finance.user_currency(user)
    return result


async def count_data(
    db: AsyncSession,
    user: User,
    metric: str,
    start: date,
    end: date,
    category: str | None,
    currency: str,
    search: str | None,
) -> float | None:
    if metric in ("expense", "income"):
        query = select(func.coalesce(func.sum(Transaction.amount), 0)).where(
            Transaction.user_id == user.id,
            Transaction.deleted_at.is_(None),
            Transaction.kind == metric,
            Transaction.currency == currency,
            Transaction.occurred_on.between(start, end),
        )
        if category:
            query = query.where(Transaction.category == category)
        if search:
            query = query.where(Transaction.note.icontains(search, autoescape=True))
    elif metric == "workouts":
        query = (
            select(func.count())
            .select_from(Workout)
            .where(
                Workout.user_id == user.id,
                Workout.deleted_at.is_(None),
                Workout.workout_date.between(start, end),
            )
        )
        if search:
            from app.models import WorkoutSet

            query = query.where(
                Workout.id.in_(
                    select(WorkoutSet.workout_id).where(
                        WorkoutSet.user_id == user.id,
                        WorkoutSet.exercise.icontains(search, autoescape=True),
                    )
                )
            )
    elif metric == "journal_days":
        query = select(func.count(func.distinct(JournalEntry.entry_date))).where(
            JournalEntry.user_id == user.id,
            JournalEntry.deleted_at.is_(None),
            JournalEntry.entry_date.between(start, end),
        )
        if search:
            query = query.where(JournalEntry.text.icontains(search, autoescape=True))
    elif metric in ("tasks_done", "xp"):
        measure = (
            func.count() if metric == "tasks_done" else func.coalesce(func.sum(XPEvent.amount), 0)
        )
        query = (
            select(measure)
            .select_from(XPEvent)
            .where(
                XPEvent.user_id == user.id,
                XPEvent.created_at >= xp.start_of_day(user, start),
                XPEvent.created_at < xp.start_of_day(user, end + timedelta(days=1)),
            )
        )
        if metric == "tasks_done":
            query = query.where(XPEvent.source_type == "task")
        if search:
            query = query.where(XPEvent.title.icontains(search, autoescape=True))
    else:
        return None
    return round(float(await db.scalar(query) or 0), 2)


async def answer_question(
    db: AsyncSession,
    user: User,
    request: QuestionRequest,
    factory: ProviderFactory,
    settings: Settings,
) -> QuestionAnswer:
    user_id = user.id
    question_index = None
    identifier = request.capture_id or request.request_id or uuid.uuid4()
    await _lock(db, f"question:{user_id}:{identifier}")
    capture = await db.scalar(select(Capture).where(Capture.id == identifier))
    if capture:
        if capture.user_id != user_id:
            raise AppError("capture_not_found", status_code=404)
        previous = await _previous_answer(db, user_id, identifier, request.text)
        if previous:
            return previous
    if request.capture_id:
        capture = await captures.get_capture(db, user_id, request.capture_id)
        if capture.status not in ("deferred", "failed"):
            raise AppError("capture_not_confirmable", status_code=409)
        indices = [
            n
            for n, i in enumerate(capture.items)
            if i.get("type") == "question" and i.get("include", True)
        ]
        question_index = (
            request.question_index
            if request.question_index is not None
            else next(iter(indices), None)
        )
        if (capture.status == "deferred" or capture.items) and question_index not in indices:
            raise AppError("coach_question_required", status_code=422)
    elif capture is not None:
        if capture.text != request.text or capture.status != "failed":
            raise AppError("coach_question_changed", status_code=409)
        question_index = 0
    else:
        capture = Capture(
            id=identifier,
            user_id=user.id,
            text=request.text,
            source=request.source,
            timezone=user.timezone,
            status="failed",
            error_code=None,
            items=[
                {
                    "type": "question",
                    "title": request.text[:300],
                    "include": True,
                    "supported": False,
                }
            ],
            created_refs=[],
        )
        db.add(capture)
    # Сырой вопрос переживает ошибку сети/провайдера.
    await db.commit()
    capture_id = capture.id
    await _lock(db, f"question:{user_id}:{capture_id}")
    await db.refresh(capture)
    previous = await _previous_answer(db, user_id, capture_id, request.text)
    if previous:
        return previous
    try:
        provider = await _provider(db, user, factory, settings)
        context = await _context(db, user)
        plan = await provider.parse(
            ContextBuilder(context).question_instructions(), request.text, QuestionPlan
        )
        today = context.now.date()
        start = _date(plan.start_date) if plan.start_date else today.replace(day=1)
        end = _date(plan.end_date) if plan.end_date else today
        if start is None or end is None:
            raise AIError("ai_bad_response")
        if start.year < 1900 or end < start or (end - start).days > 3660 or end == date.max:
            raise AIError("ai_bad_response")
        currency = (plan.currency or context.currency).strip().upper()
        if len(currency) != 3 or not currency.isascii() or not currency.isalpha():
            currency = context.currency
        value = await count_data(
            db,
            user,
            plan.metric,
            start,
            end,
            plan.category,
            currency,
            (plan.search or "").strip()[:100] or None,
        )
        answer = QuestionAnswer(
            id=uuid.uuid4(),
            capture_id=capture_id,
            question=request.text,
            metric=plan.metric,
            start_date=start,
            end_date=end,
            value=value,
            currency=currency if plan.metric in ("expense", "income") else None,
            explanation=plan.explanation.strip()[:1000],
        )
        capture.provider, capture.model = provider.name, provider.model
        db.add(
            CoachAnswer(
                id=answer.id,
                user_id=user_id,
                capture_id=capture_id,
                content=answer.model_dump(mode="json"),
            )
        )
        capture.reply = answer.explanation
        # Отвечаем только на выбранный вопрос. Другие вопросы и заметки остаются во входящих.
        capture.items = [
            {**i, "include": False} if n == (question_index if request.capture_id else 0) else i
            for n, i in enumerate(capture.items)
        ]
        capture.status = (
            "deferred"
            if any(i.get("include", True) and not i.get("supported", False) for i in capture.items)
            else "confirmed"
        )
        capture.error_code = None
        capture.confirmed_at = utcnow()
        await db.commit()
        return answer
    except AIError as exc:
        await db.rollback()
        capture = await captures.get_capture(db, user_id, capture_id)
        capture.error_code = exc.code
        await db.commit()
        raise


async def list_answers(db: AsyncSession, user: User) -> list[QuestionAnswer]:
    rows = await db.scalars(
        select(CoachAnswer)
        .where(CoachAnswer.user_id == user.id)
        .order_by(CoachAnswer.created_at.desc())
        .limit(30)
    )
    return [QuestionAnswer.model_validate(row.content) for row in rows]


async def _previous_answer(
    db: AsyncSession, user_id: uuid.UUID, capture_id: uuid.UUID, text: str
) -> QuestionAnswer | None:
    row = await db.scalar(
        select(CoachAnswer).where(
            CoachAnswer.user_id == user_id,
            CoachAnswer.capture_id == capture_id,
            CoachAnswer.content["question"].astext == text,
        )
    )
    return QuestionAnswer.model_validate(row.content) if row else None
