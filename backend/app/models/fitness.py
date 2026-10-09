import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class Workout(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Тренировка: набор подходов за одно занятие."""

    __tablename__ = "workouts"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # День тренировки в часовом поясе пользователя.
    workout_date: Mapped[date] = mapped_column(index=True)
    started_at: Mapped[datetime | None]
    ended_at: Mapped[datetime | None]
    title: Mapped[str | None] = mapped_column(String(100))
    note: Mapped[str | None] = mapped_column(Text)
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )

    sets: Mapped[list["WorkoutSet"]] = relationship(
        back_populates="workout",
        cascade="all, delete-orphan",
        order_by="WorkoutSet.position",
        lazy="selectin",
    )


class WorkoutSet(UUIDPrimaryKeyMixin, Base):
    """Подход: вес × повторы, время или дистанция."""

    __tablename__ = "workout_sets"

    workout_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("workouts.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    exercise: Mapped[str] = mapped_column(String(100))
    # Название для сравнения: «Жим лёжа» и «жим лежа » — одно упражнение.
    exercise_key: Mapped[str] = mapped_column(String(100), index=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    weight_kg: Mapped[float | None] = mapped_column(Float)
    reps: Mapped[int | None] = mapped_column(Integer)
    duration_sec: Mapped[int | None] = mapped_column(Integer)
    distance_m: Mapped[float | None] = mapped_column(Float)
    # Личный рекорд на момент тренировки.
    is_pr: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")

    workout: Mapped[Workout] = relationship(back_populates="sets")
