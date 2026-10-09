import uuid

from fastapi import APIRouter, status

from app.api.deps import DB, CurrentUser
from app.core.time import utcnow
from app.models import ProfileFact
from app.schemas.profile import ProfileFactIn, ProfileFactOut, ProfileFactUpdate
from app.services.profile import get_fact, list_facts

router = APIRouter(prefix="/profile/facts", tags=["profile"])


@router.get("")
async def get_facts(user: CurrentUser, db: DB) -> list[ProfileFactOut]:
    return [ProfileFactOut.model_validate(fact) for fact in await list_facts(db, user.id)]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_fact(body: ProfileFactIn, user: CurrentUser, db: DB) -> ProfileFactOut:
    fact = ProfileFact(
        id=uuid.uuid4(),
        user_id=user.id,
        category=body.category,
        text=body.text.strip(),
        data=body.schedule.model_dump() if body.schedule else None,
        is_active=body.is_active,
    )
    db.add(fact)
    await db.commit()
    return ProfileFactOut.model_validate(fact)


@router.patch("/{fact_id}")
async def update_fact(
    fact_id: uuid.UUID, body: ProfileFactUpdate, user: CurrentUser, db: DB
) -> ProfileFactOut:
    fact = await get_fact(db, user.id, fact_id)
    changes = body.model_dump(exclude_unset=True)
    if changes.get("category") is not None:
        fact.category = changes["category"]
    if changes.get("text") is not None:
        fact.text = changes["text"].strip()
    if "schedule" in changes:
        fact.data = body.schedule.model_dump() if body.schedule else None
    if changes.get("is_active") is not None:
        fact.is_active = changes["is_active"]
    await db.commit()
    return ProfileFactOut.model_validate(fact)


@router.delete("/{fact_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_fact(fact_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    fact = await get_fact(db, user.id, fact_id)
    fact.deleted_at = utcnow()
    await db.commit()
