"""Дневник и покупки."""

import uuid
from datetime import date
from typing import Any

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.time import utcnow
from app.models import JournalEntry, ShoppingItem, User
from app.schemas.daily import JournalIn, ShoppingIn
from app.services import xp

# --- Дневник ---


async def list_journal(
    db: AsyncSession, user_id: uuid.UUID, limit: int = 300
) -> list[JournalEntry]:
    rows = await db.scalars(
        select(JournalEntry)
        .where(JournalEntry.user_id == user_id, JournalEntry.deleted_at.is_(None))
        .order_by(JournalEntry.entry_date.desc(), JournalEntry.created_at.desc())
        .limit(limit)
    )
    return list(rows)


async def get_journal(db: AsyncSession, user_id: uuid.UUID, entry_id: uuid.UUID) -> JournalEntry:
    entry = await db.get(JournalEntry, entry_id)
    if entry is None or entry.user_id != user_id or entry.deleted_at is not None:
        raise AppError("journal_not_found", status_code=404)
    return entry


async def create_journal(
    db: AsyncSession,
    user: User,
    data: JournalIn,
    *,
    summary: str | None = None,
    capture_id: uuid.UUID | None = None,
) -> tuple[JournalEntry, int]:
    """Создаёт запись и начисляет опыт за день дневника (один раз в день)."""
    entry = JournalEntry(
        id=uuid.uuid4(),
        user_id=user.id,
        entry_date=data.entry_date or xp.local_today(user),
        text=data.text.strip(),
        summary=(summary or "").strip()[:300] or None,
        mood=data.mood,
        energy=data.energy,
        tags=data.tags,
        capture_id=capture_id,
    )
    db.add(entry)
    gained = await xp.journal_written(db, user, entry.entry_date, entry.summary or entry.text[:80])
    return entry, gained


async def update_journal(
    db: AsyncSession, user: User, entry: JournalEntry, changes: dict[str, Any]
) -> None:
    """Перенос записи на другой день переносит и опыт за день дневника."""
    old_date = entry.entry_date
    for field, value in changes.items():
        if field in ("entry_date", "text") and value is None:
            continue
        setattr(entry, field, value.strip() if field == "text" else value)
    if entry.entry_date != old_date:
        await _clear_day_if_empty(db, user, old_date, without=entry)
        await xp.journal_written(db, user, entry.entry_date, entry.summary or entry.text[:80])


async def delete_journal(db: AsyncSession, user: User, entry: JournalEntry) -> None:
    entry.deleted_at = utcnow()
    await _clear_day_if_empty(db, user, entry.entry_date, without=entry)


async def _clear_day_if_empty(
    db: AsyncSession, user: User, day: date, *, without: JournalEntry
) -> None:
    """Опыт за день дневника снимается, когда за этот день не осталось записей."""
    others = await db.scalar(
        select(func.count()).where(
            JournalEntry.user_id == user.id,
            JournalEntry.entry_date == day,
            JournalEntry.deleted_at.is_(None),
            JournalEntry.id != without.id,
        )
    )
    if not others:
        await xp.journal_day_cleared(db, user, day)


# --- Покупки ---


async def list_shopping(db: AsyncSession, user_id: uuid.UUID) -> list[ShoppingItem]:
    rows = await db.scalars(
        select(ShoppingItem)
        .where(ShoppingItem.user_id == user_id, ShoppingItem.deleted_at.is_(None))
        .order_by(ShoppingItem.is_bought, ShoppingItem.position, ShoppingItem.created_at)
    )
    return list(rows)


async def get_shopping(db: AsyncSession, user_id: uuid.UUID, item_id: uuid.UUID) -> ShoppingItem:
    item = await db.get(ShoppingItem, item_id)
    if item is None or item.user_id != user_id or item.deleted_at is not None:
        raise AppError("shopping_item_not_found", status_code=404)
    return item


def create_shopping(
    db: AsyncSession, user: User, data: ShoppingIn, *, capture_id: uuid.UUID | None = None
) -> ShoppingItem:
    item = ShoppingItem(
        id=uuid.uuid4(),
        user_id=user.id,
        name=data.name.strip(),
        quantity=(data.quantity or "").strip() or None,
        list_name=(data.list_name or "").strip() or None,
        is_bought=False,
        position=utcnow().timestamp(),
        capture_id=capture_id,
    )
    db.add(item)
    return item


def set_bought(item: ShoppingItem, is_bought: bool) -> None:
    if item.is_bought != is_bought:
        item.is_bought = is_bought
        item.bought_at = utcnow() if is_bought else None


async def clear_bought(db: AsyncSession, user_id: uuid.UUID) -> None:
    await db.execute(
        update(ShoppingItem)
        .where(
            ShoppingItem.user_id == user_id,
            ShoppingItem.is_bought.is_(True),
            ShoppingItem.deleted_at.is_(None),
        )
        .values(deleted_at=utcnow())
    )
