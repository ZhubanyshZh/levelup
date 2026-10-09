import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Float,
    ForeignKey,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.time import utcnow
from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class JournalEntry(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Запись дневника. За день их может быть несколько — голосовые заметки в течение дня."""

    __tablename__ = "journal_entries"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    entry_date: Mapped[date] = mapped_column(index=True)
    text: Mapped[str] = mapped_column(Text)
    # Однострочное резюме от ИИ (для записей, пришедших через ввод).
    summary: Mapped[str | None] = mapped_column(String(300))
    mood: Mapped[int | None] = mapped_column(SmallInteger)
    energy: Mapped[int | None] = mapped_column(SmallInteger)
    tags: Mapped[list[str]] = mapped_column(JSONB, default=list)
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )


class ShoppingItem(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "shopping_items"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(200))
    quantity: Mapped[str | None] = mapped_column(String(50))
    # null — основной список; иначе название магазина или повода («Дача»).
    list_name: Mapped[str | None] = mapped_column(String(100))
    is_bought: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    bought_at: Mapped[datetime | None]
    position: Mapped[float] = mapped_column(Float, default=0, server_default="0")
    capture_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("captures.id", ondelete="SET NULL")
    )


class XPEvent(UUIDPrimaryKeyMixin, Base):
    """Журнал начислений опыта. Уровень всегда считается из него.

    source_key делает начисление идемпотентным: одна задача (в один день повтора)
    или один день дневника дают опыт ровно один раз.
    """

    __tablename__ = "xp_events"
    __table_args__ = (UniqueConstraint("user_id", "source_key"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    source_type: Mapped[str] = mapped_column(String(20))
    source_key: Mapped[str] = mapped_column(String(120))
    amount: Mapped[int]
    # Название на момент начисления — для истории «за что».
    title: Mapped[str] = mapped_column(String(300))
    created_at: Mapped[datetime] = mapped_column(default=utcnow, server_default=func.now())
