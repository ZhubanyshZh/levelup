"""Прокачка: сферы жизни, квесты, достижения."""

import uuid
from datetime import date, datetime

from sqlalchemy import Float, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.time import utcnow
from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class Sphere(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Сфера жизни со своим уровнем. Пять стандартных создаются сами, свои можно добавить."""

    __tablename__ = "spheres"
    __table_args__ = (UniqueConstraint("user_id", "key"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # body | mind | finance | discipline | balance | c-<…> для своих. Опыт привязан к ключу,
    # поэтому переименование сферы его не теряет.
    key: Mapped[str] = mapped_column(String(40))
    name: Mapped[str] = mapped_column(String(50))
    icon: Mapped[str] = mapped_column(String(10))
    position: Mapped[float] = mapped_column(Float, default=0, server_default="0")


class Quest(UUIDPrimaryKeyMixin, Base):
    """Задание на день или неделю. Прогресс считает код по журналу опыта."""

    __tablename__ = "quests"
    __table_args__ = (UniqueConstraint("user_id", "period", "period_start", "kind"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # day | week
    period: Mapped[str] = mapped_column(String(10))
    period_start: Mapped[date]
    # tasks | journal | workouts | goal_steps | comeback
    kind: Mapped[str] = mapped_column(String(20))
    target: Mapped[int] = mapped_column(Integer)
    reward: Mapped[int] = mapped_column(Integer)
    sphere: Mapped[str | None] = mapped_column(String(40))
    completed_at: Mapped[datetime | None]
    created_at: Mapped[datetime] = mapped_column(default=utcnow, server_default=func.now())


class UserAchievement(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "user_achievements"
    __table_args__ = (UniqueConstraint("user_id", "code"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    code: Mapped[str] = mapped_column(String(40))
    achieved_at: Mapped[datetime] = mapped_column(default=utcnow, server_default=func.now())
