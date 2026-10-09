"""Опыт и уровень. Начисляет код по фиксированным правилам — не ИИ."""

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import Date, cast, delete, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.time import utcnow
from app.models import Task, User, XPEvent
from app.services.spheres import SOURCE_SPHERES

# Опыт за задачу по сложности (её оценивает ИИ или пользователь). Без оценки — как за 2.
TASK_XP = {1: 5, 2: 10, 3: 15, 4: 20, 5: 30}
DEFAULT_TASK_XP = TASK_XP[2]
JOURNAL_XP = 15
WORKOUT_XP = 25
PR_XP = 50
BUDGET_WEEK_XP = 50
GOAL_STEP_XP = 100
GOAL_XP = 500
# Ограничения, чтобы опыт нельзя было «нафармить».
SMALL_TASKS_PER_DAY = 10
WORKOUTS_PER_DAY = 2
GOAL_STEPS_PER_DAY = 3


def xp_for_next_level(level: int) -> int:
    """Сколько опыта нужно, чтобы с уровня N перейти на N+1: 100 × N^1.5."""
    return round(100 * level**1.5)


def level_for(total_xp: int) -> tuple[int, int, int]:
    """(уровень, опыт внутри уровня, сколько нужно до следующего)."""
    level, remaining = 1, max(total_xp, 0)
    while remaining >= xp_for_next_level(level):
        remaining -= xp_for_next_level(level)
        level += 1
    return level, remaining, xp_for_next_level(level)


def local_today(user: User) -> date:
    return utcnow().astimezone(ZoneInfo(user.timezone)).date()


def start_of_day(user: User, day: date) -> datetime:
    return datetime.combine(day, time.min, ZoneInfo(user.timezone))


def streak(days: set[date], today: date) -> int:
    """Серия дней подряд. Один пропущенный день её не рвёт («заморозка»), два подряд — рвут.

    Сегодняшний день ещё не кончился, поэтому его отсутствие пропуском не считается.
    """
    cursor = today if today in days else today - timedelta(days=1)
    count, missed = 0, 0
    for _ in range(800):
        if cursor in days:
            count += 1
            missed = 0
        else:
            missed += 1
            if missed > 1:
                break
        cursor -= timedelta(days=1)
    return count


# --- Начисления ---


def task_key(task: Task, occurrence: date) -> str:
    return f"task:{task.id}:{occurrence.isoformat()}"


async def task_completed(db: AsyncSession, user: User, task: Task, occurrence: date) -> int:
    amount = TASK_XP.get(task.difficulty or 0, DEFAULT_TASK_XP)
    if amount == TASK_XP[1] and await _count_today(db, user, "task", amount) >= SMALL_TASKS_PER_DAY:
        return 0
    return await award(
        db, user, "task", task_key(task, occurrence), amount, task.title, sphere=task.sphere
    )


async def task_uncompleted(db: AsyncSession, user: User, task: Task, occurrence: date) -> None:
    await revoke(db, user, task_key(task, occurrence))


async def journal_written(db: AsyncSession, user: User, entry_date: date, title: str) -> int:
    """15 XP за день дневника. За давние дни не начисляем — задним числом не прокачаться."""
    if entry_date < local_today(user) - timedelta(days=1):
        return 0
    return await award(db, user, "journal", f"journal:{entry_date.isoformat()}", JOURNAL_XP, title)


async def journal_day_cleared(db: AsyncSession, user: User, entry_date: date) -> None:
    await revoke(db, user, f"journal:{entry_date.isoformat()}")


async def award(
    db: AsyncSession,
    user: User,
    source_type: str,
    key: str,
    amount: int,
    title: str,
    *,
    sphere: str | None = None,
) -> int:
    """Начисляет опыт один раз на ключ. Возвращает начисленное (0, если уже было)."""
    inserted = await db.scalar(
        insert(XPEvent)
        .values(
            user_id=user.id,
            source_type=source_type,
            source_key=key,
            amount=amount,
            title=title[:300],
            sphere=sphere or SOURCE_SPHERES.get(source_type),
        )
        .on_conflict_do_nothing(index_elements=["user_id", "source_key"])
        .returning(XPEvent.amount)
    )
    return int(inserted or 0)


async def revoke(db: AsyncSession, user: User, key: str) -> None:
    await db.execute(delete(XPEvent).where(XPEvent.user_id == user.id, XPEvent.source_key == key))


async def count_today(db: AsyncSession, user: User, source_type: str) -> int:
    return await _count_today(db, user, source_type, None)


async def _count_today(db: AsyncSession, user: User, source_type: str, amount: int | None) -> int:
    query = select(func.count()).where(
        XPEvent.user_id == user.id,
        XPEvent.source_type == source_type,
        XPEvent.created_at >= start_of_day(user, local_today(user)),
    )
    if amount is not None:
        query = query.where(XPEvent.amount == amount)
    return int(await db.scalar(query) or 0)


# --- Чтение ---


async def total(db: AsyncSession, user: User) -> int:
    value = await db.scalar(
        select(func.coalesce(func.sum(XPEvent.amount), 0)).where(XPEvent.user_id == user.id)
    )
    return int(value or 0)


async def today_total(db: AsyncSession, user: User) -> int:
    value = await db.scalar(
        select(func.coalesce(func.sum(XPEvent.amount), 0)).where(
            XPEvent.user_id == user.id,
            XPEvent.created_at >= start_of_day(user, local_today(user)),
        )
    )
    return int(value or 0)


async def by_sphere(db: AsyncSession, user: User) -> dict[str, int]:
    rows = await db.execute(
        select(XPEvent.sphere, func.sum(XPEvent.amount))
        .where(XPEvent.user_id == user.id)
        .group_by(XPEvent.sphere)
    )
    return {sphere: int(amount) for sphere, amount in rows if sphere}


async def recent(db: AsyncSession, user: User, limit: int = 20) -> list[XPEvent]:
    rows = await db.scalars(
        select(XPEvent)
        .where(XPEvent.user_id == user.id)
        .order_by(XPEvent.created_at.desc())
        .limit(limit)
    )
    return list(rows)


async def active_days(db: AsyncSession, user: User, since: date) -> set[date]:
    """Дни (по часам пользователя), в которые был получен хоть какой-то опыт."""
    local = cast(func.timezone(user.timezone, XPEvent.created_at), Date)
    rows = await db.scalars(
        select(local)
        .where(XPEvent.user_id == user.id, XPEvent.created_at >= start_of_day(user, since))
        .distinct()
    )
    return set(rows)


async def count_since(
    db: AsyncSession, user: User, source_types: tuple[str, ...], since: datetime
) -> int:
    value = await db.scalar(
        select(func.count()).where(
            XPEvent.user_id == user.id,
            XPEvent.source_type.in_(source_types),
            XPEvent.created_at >= since,
        )
    )
    return int(value or 0)
