import uuid

from fastapi import APIRouter, status

from app.api.deps import DB, CurrentUser
from app.core.time import utcnow
from app.schemas.daily import (
    JournalIn,
    JournalOut,
    JournalUpdate,
    ShoppingIn,
    ShoppingOut,
    ShoppingUpdate,
)
from app.services import daily

journal = APIRouter(prefix="/journal", tags=["journal"])
shopping = APIRouter(prefix="/shopping", tags=["shopping"])


# --- Дневник ---


@journal.get("")
async def list_journal(user: CurrentUser, db: DB) -> list[JournalOut]:
    return [JournalOut.model_validate(e) for e in await daily.list_journal(db, user.id)]


@journal.post("", status_code=status.HTTP_201_CREATED)
async def create_journal(body: JournalIn, user: CurrentUser, db: DB) -> JournalOut:
    entry, _ = await daily.create_journal(db, user, body)
    await db.commit()
    return JournalOut.model_validate(entry)


@journal.patch("/{entry_id}")
async def update_journal(
    entry_id: uuid.UUID, body: JournalUpdate, user: CurrentUser, db: DB
) -> JournalOut:
    entry = await daily.get_journal(db, user.id, entry_id)
    await daily.update_journal(db, user, entry, body.model_dump(exclude_unset=True))
    await db.commit()
    return JournalOut.model_validate(entry)


@journal.delete("/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_journal(entry_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    entry = await daily.get_journal(db, user.id, entry_id)
    await daily.delete_journal(db, user, entry)
    await db.commit()


# --- Покупки ---


@shopping.get("")
async def list_shopping(user: CurrentUser, db: DB) -> list[ShoppingOut]:
    return [ShoppingOut.model_validate(i) for i in await daily.list_shopping(db, user.id)]


@shopping.post("", status_code=status.HTTP_201_CREATED)
async def create_shopping(body: ShoppingIn, user: CurrentUser, db: DB) -> ShoppingOut:
    item = daily.create_shopping(db, user, body)
    await db.commit()
    return ShoppingOut.model_validate(item)


@shopping.post("/clear-bought", status_code=status.HTTP_204_NO_CONTENT)
async def clear_bought(user: CurrentUser, db: DB) -> None:
    """Убрать всё купленное из списка."""
    await daily.clear_bought(db, user.id)
    await db.commit()


@shopping.patch("/{item_id}")
async def update_shopping(
    item_id: uuid.UUID, body: ShoppingUpdate, user: CurrentUser, db: DB
) -> ShoppingOut:
    item = await daily.get_shopping(db, user.id, item_id)
    changes = body.model_dump(exclude_unset=True)
    if changes.get("name"):
        item.name = changes["name"].strip()
    if "quantity" in changes:
        item.quantity = (changes["quantity"] or "").strip() or None
    if "list_name" in changes:
        item.list_name = (changes["list_name"] or "").strip() or None
    if changes.get("position") is not None:
        item.position = changes["position"]
    if changes.get("is_bought") is not None:
        daily.set_bought(item, changes["is_bought"])
    await db.commit()
    return ShoppingOut.model_validate(item)


@shopping.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_shopping(item_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    item = await daily.get_shopping(db, user.id, item_id)
    item.deleted_at = utcnow()
    await db.commit()
