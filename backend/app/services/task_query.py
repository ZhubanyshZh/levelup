"""Ограниченная выборка задач с курсором вместо OFFSET и без COUNT всей выборки."""

import base64
import hashlib
import json
import uuid
from datetime import date, time, timedelta
from typing import Literal

from pydantic import BaseModel, Field, FiniteFloat, ValidationError
from sqlalchemy import and_, literal_column, or_, select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.time import utcnow
from app.models import Task, User
from app.models.assistant import task_due_key, task_search_key, task_state_key, task_time_key
from app.schemas.task import TaskPage, TaskQuery
from app.services import tasks, xp


class Cursor(BaseModel):
    version: Literal[1] = 1
    fingerprint: str
    bucket: int = Field(ge=0, le=1)
    due_date: date
    due_time: time
    position: FiniteFloat
    id: uuid.UUID


def _fingerprint(user: User, query: TaskQuery, today: date) -> str:
    values = query.model_dump(mode="json", exclude={"cursor", "limit"})
    values.update(user_id=str(user.id), today=str(today), timezone=user.timezone)
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()


def _decode_cursor(raw: str, fingerprint: str) -> Cursor:
    try:
        data = base64.b64decode(raw + "=" * (-len(raw) % 4), altchars=b"-_", validate=True)
        cursor = Cursor.model_validate_json(data)
        if cursor.fingerprint != fingerprint:
            raise ValueError("cursor belongs to another query")
        return cursor
    except (ValueError, ValidationError) as error:
        raise AppError("invalid_task_cursor", status_code=422) from error


def _encode_cursor(task: Task, fingerprint: str) -> str:
    value = Cursor(
        fingerprint=fingerprint,
        bucket=1 if task.status == "done" else 0,
        due_date=task.due_date or date.max,
        due_time=task.due_time or time(23, 59, 59),
        position=task.position,
        id=task.id,
    )
    return base64.urlsafe_b64encode(value.model_dump_json().encode()).decode().rstrip("=")


def task_statement(user: User, query: TaskQuery, today: date):
    statement = select(Task).where(Task.user_id == user.id, Task.deleted_at.is_(None))
    # Сохраняем прежнюю политику архива выполненных задач.
    statement = statement.where(
        or_(
            Task.status != literal_column("'done'"),
            and_(
                Task.status == literal_column("'done'"),
                Task.completed_at >= utcnow() - timedelta(days=tasks.DONE_VISIBLE_DAYS),
            ),
        )
    )
    if query.status:
        statement = statement.where(Task.status == query.status)
    if query.priority:
        statement = statement.where(Task.priority == query.priority)
    if query.sphere:
        statement = statement.where(Task.sphere == query.sphere)
    if query.goal_id:
        statement = statement.where(Task.goal_id == query.goal_id)
    match query.due:
        case "overdue":
            statement = statement.where(
                Task.status != literal_column("'done'"), Task.due_date < today
            )
        case "today":
            statement = statement.where(Task.due_date == today)
        case "tomorrow":
            statement = statement.where(Task.due_date == today + timedelta(days=1))
        case "nextSevenDays":
            statement = statement.where(Task.due_date.between(today, today + timedelta(days=6)))
        case "noDate":
            statement = statement.where(Task.due_date.is_(None))
    if query.view == "today":
        statement = statement.where(
            Task.status != literal_column("'done'"),
            or_(Task.due_date <= today, and_(Task.due_date.is_(None), Task.status == "doing")),
        )
    elif query.view == "widgets":
        statement = statement.where(
            or_(
                Task.due_date <= today + timedelta(days=7),
                and_(Task.due_date.is_(None), Task.status == "doing"),
            )
        )
    elif query.view == "reminders":
        statement = statement.where(
            Task.remind.is_(True),
            Task.status != literal_column("'done'"),
            Task.due_date <= today + timedelta(days=7),
            or_(Task.due_date >= today - timedelta(days=1), Task.recurrence.is_not(None)),
        )
    for word in query.q.split():
        # Пользовательский '%' или '_' — буквальный символ, а не SQL wildcard.
        pattern = word.lower().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        statement = statement.where(task_search_key().like(f"%{pattern}%", escape="\\"))
    if query.cursor:
        cursor = _decode_cursor(query.cursor, _fingerprint(user, query, today))
        if query.sort == "position":
            statement = statement.where(
                tuple_(Task.position, Task.id) > tuple_(cursor.position, cursor.id)
            )
        else:
            statement = statement.where(
                tuple_(task_state_key(), task_due_key(), task_time_key(), Task.position, Task.id)
                > tuple_(
                    cursor.bucket, cursor.due_date, cursor.due_time, cursor.position, cursor.id
                )
            )
    if query.sort == "position":
        statement = statement.order_by(Task.position, Task.id)
    else:
        statement = statement.order_by(
            task_state_key(), task_due_key(), task_time_key(), Task.position, Task.id
        )
    return statement.limit(query.limit + 1)


async def page_tasks(db: AsyncSession, user: User, query: TaskQuery) -> TaskPage:
    today = xp.local_today(user)
    rows = list(await db.scalars(task_statement(user, query, today)))
    more = len(rows) > query.limit
    rows = rows[: query.limit]
    present = await tasks.presenter(db, user)
    return TaskPage(
        items=[present(task) for task in rows],
        next_cursor=_encode_cursor(rows[-1], _fingerprint(user, query, today)) if more else None,
    )
