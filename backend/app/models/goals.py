import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Float, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class Goal(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Цель: шаги, метрика прогресса и дедлайн."""

    __tablename__ = "goals"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    why: Mapped[str | None] = mapped_column(Text)
    deadline: Mapped[date | None]
    # Метрика: «пробежать 10 км» → unit «км», target 10. Без метрики прогресс — по шагам.
    metric_unit: Mapped[str | None] = mapped_column(String(30))
    start_value: Mapped[float | None] = mapped_column(Float)
    current_value: Mapped[float | None] = mapped_column(Float)
    target_value: Mapped[float | None] = mapped_column(Float)
    sphere: Mapped[str | None] = mapped_column(String(40))
    # active | done
    status: Mapped[str] = mapped_column(String(10), default="active", server_default="active")
    completed_at: Mapped[datetime | None]
    position: Mapped[float] = mapped_column(Float, default=0, server_default="0")
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )

    steps: Mapped[list["GoalStep"]] = relationship(
        back_populates="goal",
        cascade="all, delete-orphan",
        order_by="GoalStep.position",
        lazy="selectin",
    )


class GoalStep(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "goal_steps"

    goal_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("goals.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(300))
    is_done: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    done_at: Mapped[datetime | None]
    position: Mapped[float] = mapped_column(Float, default=0, server_default="0")

    goal: Mapped[Goal] = relationship(back_populates="steps")
