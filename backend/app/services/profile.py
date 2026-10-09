import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models import ProfileFact


async def list_facts(
    db: AsyncSession, user_id: uuid.UUID, *, active_only: bool = False
) -> list[ProfileFact]:
    query = select(ProfileFact).where(
        ProfileFact.user_id == user_id, ProfileFact.deleted_at.is_(None)
    )
    if active_only:
        query = query.where(ProfileFact.is_active.is_(True))
    rows = await db.scalars(query.order_by(ProfileFact.category, ProfileFact.created_at))
    return list(rows)


async def get_fact(db: AsyncSession, user_id: uuid.UUID, fact_id: uuid.UUID) -> ProfileFact:
    fact = await db.get(ProfileFact, fact_id)
    if fact is None or fact.user_id != user_id or fact.deleted_at is not None:
        raise AppError("fact_not_found", status_code=404)
    return fact
