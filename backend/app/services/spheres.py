"""Сферы жизни. Пять стандартных создаются у каждого пользователя при первом обращении."""

import uuid

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.models import Sphere, User

# Ключ → (иконка, название ru, название en). Ключи стандартных сфер не меняются:
# по ним ИИ относит действия к сфере.
DEFAULT_SPHERES: dict[str, tuple[str, str, str]] = {
    "body": ("💪", "Тело", "Body"),
    "mind": ("🧠", "Разум", "Mind"),
    "finance": ("💰", "Финансы", "Finance"),
    "discipline": ("⚙️", "Дисциплина", "Discipline"),
    "balance": ("🌿", "Баланс", "Balance"),
}
# Куда идёт опыт, если сфера не указана.
SOURCE_SPHERES = {
    "task": "discipline",
    "journal": "balance",
    "workout": "body",
    "pr": "body",
    "budget": "finance",
    "goal_step": "discipline",
    "goal": "discipline",
}


async def list_spheres(db: AsyncSession, user: User) -> list[Sphere]:
    await ensure_defaults(db, user)
    rows = await db.scalars(
        select(Sphere)
        .where(Sphere.user_id == user.id, Sphere.deleted_at.is_(None))
        .order_by(Sphere.position, Sphere.created_at)
    )
    return list(rows)


async def ensure_defaults(db: AsyncSession, user: User) -> None:
    english = user.locale == "en"
    await db.execute(
        insert(Sphere)
        .values(
            [
                {
                    "id": uuid.uuid4(),
                    "user_id": user.id,
                    "key": key,
                    "icon": icon,
                    "name": name_en if english else name_ru,
                    "position": index,
                }
                for index, (key, (icon, name_ru, name_en)) in enumerate(DEFAULT_SPHERES.items())
            ]
        )
        .on_conflict_do_nothing(index_elements=["user_id", "key"])
    )


async def get_sphere(db: AsyncSession, user_id: uuid.UUID, sphere_id: uuid.UUID) -> Sphere:
    sphere = await db.get(Sphere, sphere_id)
    if sphere is None or sphere.user_id != user_id or sphere.deleted_at is not None:
        raise AppError("sphere_not_found", status_code=404)
    return sphere


def create_sphere(db: AsyncSession, user: User, name: str, icon: str, position: float) -> Sphere:
    sphere = Sphere(
        id=uuid.uuid4(),
        user_id=user.id,
        key=f"c-{uuid.uuid4().hex[:12]}",
        name=name.strip(),
        icon=icon.strip() or "⭐",
        position=position,
    )
    db.add(sphere)
    return sphere


async def valid_key(db: AsyncSession, user: User, key: str | None) -> str | None:
    """Ключ сферы, если такая есть у пользователя; иначе None (ИИ мог ошибиться)."""
    if not key:
        return None
    if key in DEFAULT_SPHERES:
        return key
    keys = {sphere.key for sphere in await list_spheres(db, user)}
    return key if key in keys else None
