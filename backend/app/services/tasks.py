import uuid
from collections.abc import Callable, Sequence
from datetime import date
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.time import utcnow
from app.models import ProfileFact, Task, User
from app.schemas.common import parse_hhmm
from app.schemas.task import TaskCreate, TaskOut
from app.services import goals, recurrence, spheres, xp
from app.services.profile import list_facts
from app.services.schedule import compute_remind_at, upcoming_reminders

# Выполненные задачи показываем столько дней, дальше они уходят в архив.
DONE_VISIBLE_DAYS = 30

TaskPresenter = Callable[[Task], TaskOut]


async def get_task(db: AsyncSession, user_id: uuid.UUID, task_id: uuid.UUID) -> Task:
    task = await db.get(Task, task_id)
    if task is None or task.user_id != user_id or task.deleted_at is not None:
        raise AppError("task_not_found", status_code=404)
    return task


def create_task(
    db: AsyncSession, user: User, data: TaskCreate, *, capture_id: uuid.UUID | None = None
) -> Task:
    task = Task(id=uuid.uuid4(), user_id=user.id, capture_id=capture_id, status="todo")
    # Новые задачи — сверху колонки.
    task.position = -utcnow().timestamp()
    _apply_fields(task, data.model_dump(exclude={"status"}), user)
    if data.status != "todo":
        task.status = data.status
        task.completed_at = utcnow() if data.status == "done" else None
    db.add(task)
    return task


async def update_task(db: AsyncSession, user: User, task: Task, changes: dict[str, Any]) -> int:
    """Применяет изменения. Возвращает начисленный опыт (за выполнение)."""
    _apply_fields(task, changes, user)
    new_status = changes.get("status")
    if new_status is None or new_status == task.status:
        return 0

    if new_status == "done":
        occurrence = task.due_date or xp.local_today(user)
        gained = await xp.task_completed(db, user, task, occurrence)
        if task.recurrence and task.due_date:
            # Повторяющаяся задача не закрывается, а переезжает на следующий раз.
            after = max(task.due_date, xp.local_today(user))
            task.due_date = recurrence.next_after(task.recurrence, after)
            task.status = "todo"
            task.completed_at = None
            _refresh_remind_at(task, user)
        else:
            task.status = "done"
            task.completed_at = utcnow()
        return gained

    if task.status == "done":
        await xp.task_uncompleted(db, user, task, _completed_occurrence(task, user))
    task.status = new_status
    task.completed_at = None
    return 0


async def presenter(db: AsyncSession, user: User) -> TaskPresenter:
    """Превращает задачу в ответ API с напоминаниями, посчитанными по «Обо мне»."""
    facts = await list_facts(db, user.id, active_only=True)
    now = utcnow()
    return lambda task: present(task, user.timezone, facts, now)


def present(task: Task, timezone: str, facts: Sequence[ProfileFact], now) -> TaskOut:
    out = TaskOut.model_validate(task)
    out.reminders = upcoming_reminders(task, timezone, facts, now)
    out.remind_at = out.reminders[0] if out.reminders else None
    return out


async def check_links(db: AsyncSession, user: User, changes: dict[str, Any]) -> None:
    """Сфера и цель задачи должны принадлежать пользователю."""
    if changes.get("sphere") and await spheres.valid_key(db, user, changes["sphere"]) is None:
        raise AppError("sphere_not_found", status_code=422)
    if changes.get("goal_id"):
        await goals.get_goal(db, user.id, changes["goal_id"])


def _apply_fields(task: Task, changes: dict[str, Any], user: User) -> None:
    for field in (
        "title",
        "notes",
        "priority",
        "difficulty",
        "due_date",
        "remind",
        "sphere",
        "goal_id",
    ):
        if field in changes:
            setattr(task, field, changes[field])
    if "due_time" in changes:
        task.due_time = parse_hhmm(changes["due_time"])
    if changes.get("position") is not None:
        task.position = changes["position"]
    if "recurrence" in changes:
        if changes["recurrence"] and task.due_date is None:
            # Повтор без даты: первый раз — ближайший подходящий день, начиная с сегодня.
            rule = recurrence.normalize(changes["recurrence"], None)
            task.due_date = recurrence.first_on_or_after(rule, xp.local_today(user))
        task.recurrence = recurrence.normalize(changes["recurrence"], task.due_date)
    if task.remind is None:
        task.remind = False
    _refresh_remind_at(task, user)


def _completed_occurrence(task: Task, user: User) -> date:
    """Тот же день, за который начислялся опыт при выполнении."""
    if task.due_date:
        return task.due_date
    if task.completed_at:
        return task.completed_at.astimezone(ZoneInfo(user.timezone)).date()
    return xp.local_today(user)


def _refresh_remind_at(task: Task, user: User) -> None:
    task.remind_at = compute_remind_at(task.remind, task.due_date, task.due_time, user.timezone)
