import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class Transaction(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Доход или расход."""

    __tablename__ = "transactions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # expense | income
    kind: Mapped[str] = mapped_column(String(10))
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    currency: Mapped[str] = mapped_column(String(3))
    # Ключ категории: groceries, cafe, transport … (список — app.schemas.finance).
    category: Mapped[str] = mapped_column(String(30))
    note: Mapped[str | None] = mapped_column(String(300))
    # День операции в часовом поясе пользователя.
    occurred_on: Mapped[date] = mapped_column(index=True)
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )


class Budget(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Месячный лимит расходов: общий (category = null) или на категорию."""

    __tablename__ = "budgets"
    __table_args__ = (UniqueConstraint("user_id", "category", postgresql_nulls_not_distinct=True),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    category: Mapped[str | None] = mapped_column(String(30))
    monthly_limit: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    currency: Mapped[str] = mapped_column(String(3))
