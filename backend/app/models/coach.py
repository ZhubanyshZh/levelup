import uuid
from datetime import date
from typing import Any

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class CoachReport(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """План/обзор и его принятые предложения. Повторное принятие не создаёт дубликатов."""

    __tablename__ = "coach_reports"
    __table_args__ = (UniqueConstraint("user_id", "cache_key"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(20))
    period_start: Mapped[date]
    cache_key: Mapped[str] = mapped_column(String(160))
    locale: Mapped[str] = mapped_column(String(10))
    timezone: Mapped[str] = mapped_column(String(64))
    goal_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("goals.id", ondelete="CASCADE"), index=True
    )
    provider: Mapped[str] = mapped_column(String(20))
    model: Mapped[str] = mapped_column(String(100))
    content: Mapped[dict[str, Any]] = mapped_column(JSONB)
    # action_id → task/goal_step id. JSON заменяется целиком при изменении.
    applied: Mapped[dict[str, str]] = mapped_column(JSONB, default=dict)


class CoachAnswer(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "coach_answers"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    capture_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("captures.id", ondelete="CASCADE"), index=True
    )
    content: Mapped[dict[str, Any]] = mapped_column(JSONB)
