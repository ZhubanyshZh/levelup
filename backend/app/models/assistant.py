import uuid
from datetime import date, datetime, time
from typing import Any

from sqlalchemy import (
    Boolean,
    Float,
    ForeignKey,
    Index,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    func,
    literal_column,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class AICredential(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Ключ пользователя к провайдеру ИИ. Хранится только зашифрованным."""

    __tablename__ = "ai_credentials"
    __table_args__ = (UniqueConstraint("user_id", "provider"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    provider: Mapped[str] = mapped_column(String(20))
    encrypted_key: Mapped[str] = mapped_column(Text)
    key_hint: Mapped[str] = mapped_column(String(12))
    model: Mapped[str | None] = mapped_column(String(100))


class Capture(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Сырой ввод пользователя. Сохраняется до обращения к ИИ — ничего не теряется."""

    __tablename__ = "captures"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    text: Mapped[str] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(10))
    timezone: Mapped[str] = mapped_column(String(64))
    # failed → parsed → confirmed | deferred; undone — после отмены.
    status: Mapped[str] = mapped_column(String(20), index=True)
    error_code: Mapped[str | None] = mapped_column(String(40))
    provider: Mapped[str | None] = mapped_column(String(20))
    model: Mapped[str | None] = mapped_column(String(100))
    reply: Mapped[str | None] = mapped_column(Text)
    items: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, default=list)
    created_refs: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, default=list)
    parsed_at: Mapped[datetime | None]
    confirmed_at: Mapped[datetime | None]


class ProfileFact(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Факт «Обо мне», который ИИ учитывает в каждом запросе."""

    __tablename__ = "profile_facts"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    category: Mapped[str] = mapped_column(String(20))
    text: Mapped[str] = mapped_column(String(500))
    # Для category=schedule: {"weekdays": ["FRI"], "start": "12:30", "end": "14:00", "busy": true}
    data: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )


class Task(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "tasks"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(300))
    notes: Mapped[str | None] = mapped_column(Text)
    # Колонка канбана: todo | doing | done
    status: Mapped[str] = mapped_column(String(10), default="todo", server_default="todo")
    priority: Mapped[str] = mapped_column(String(10), default="normal", server_default="normal")
    # Срок — в часовом поясе пользователя; время необязательно.
    due_date: Mapped[date | None]
    due_time: Mapped[time | None]
    remind: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    remind_at: Mapped[datetime | None]
    difficulty: Mapped[int | None] = mapped_column(SmallInteger)
    position: Mapped[float] = mapped_column(Float, default=0, server_default="0")
    completed_at: Mapped[datetime | None]
    # Повтор: {"freq": "daily" | "weekly" | "monthly", "weekdays": ["MON"], "monthday": 15}.
    # У повторяющейся задачи due_date — ближайший раз; после выполнения она сдвигается вперёд.
    recurrence: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    # Сфера жизни, в которую идёт опыт (оценивает ИИ или пользователь).
    sphere: Mapped[str | None] = mapped_column(String(40))
    goal_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("goals.id", ondelete="SET NULL"), index=True
    )
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )


# Те же выражения используются в ORDER BY, курсорах и индексах.
def task_state_key():
    return literal_column("(CASE WHEN status = 'done' THEN 1 ELSE 0 END)")


def task_due_key():
    return func.coalesce(Task.due_date, literal_column("DATE 'infinity'"))


def task_time_key():
    return func.coalesce(Task.due_time, literal_column("TIME '23:59:59'"))


def task_search_key():
    return func.lower(
        Task.title + literal_column("' '") + func.coalesce(Task.notes, literal_column("''"))
    )


_live_tasks = Task.deleted_at.is_(None)
Index(
    "ix_tasks_live_due",
    Task.user_id,
    task_state_key(),
    task_due_key(),
    task_time_key(),
    Task.position,
    Task.id,
    postgresql_where=_live_tasks,
)
Index("ix_tasks_live_date", Task.user_id, Task.due_date, postgresql_where=_live_tasks)
Index(
    "ix_tasks_live_status_position",
    Task.user_id,
    Task.status,
    Task.position,
    Task.id,
    postgresql_where=_live_tasks,
)
Index("ix_tasks_live_priority", Task.user_id, Task.priority, postgresql_where=_live_tasks)
Index("ix_tasks_live_sphere", Task.user_id, Task.sphere, postgresql_where=_live_tasks)
Index(
    "ix_tasks_open_due",
    Task.user_id,
    task_state_key(),
    task_due_key(),
    task_time_key(),
    Task.position,
    Task.id,
    postgresql_where=_live_tasks & (Task.status != "done"),
)
Index(
    "ix_tasks_done_completed",
    Task.user_id,
    Task.completed_at,
    postgresql_where=_live_tasks & (Task.status == "done"),
)
Index(
    "ix_tasks_reminder_date",
    Task.user_id,
    Task.due_date,
    postgresql_where=_live_tasks & Task.remind.is_(True) & (Task.status != "done"),
)
Index(
    "ix_tasks_live_search",
    task_search_key().label("search_text"),
    postgresql_using="gin",
    postgresql_ops={"search_text": "gin_trgm_ops"},
    postgresql_where=_live_tasks,
)
