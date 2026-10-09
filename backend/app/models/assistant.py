import uuid
from datetime import date, datetime, time
from typing import Any

from sqlalchemy import Boolean, Float, ForeignKey, SmallInteger, String, Text, UniqueConstraint
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
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )
