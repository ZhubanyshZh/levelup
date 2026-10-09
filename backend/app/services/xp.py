"""Опыт и уровень. Начисляет код по фиксированным правилам — не ИИ."""

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.time import utcnow
from app.models import Task, User, XPEvent
from app.schemas.daily import ProgressOut, XPEventOut

# Опыт за задачу по сложности (её оценивает ИИ или пользователь). Без оценки — как за 2.
TASK_XP = {1: 5, 2: 10, 3: 15, 4: 20, 5: 30}
DEFAULT_TASK_XP = TASK_XP[2]
JOURNAL_XP = 15
# Мелочи (сложность 1) приносят опыт не больше стольких раз в день — чтобы не «фармить».
SMALL_TASKS_PER_DAY = 10


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


def task_key(task: Task, occurrence: date) -> str:
    return f"task:{task.id}:{occurrence.isoformat()}"


async def task_completed(db: AsyncSession, user: User, task: Task, occurrence: date) -> int:
    amount = TASK_XP.get(task.difficulty or 0, DEFAULT_TASK_XP)
    if amount == TASK_XP[1] and await _small_tasks_today(db, user) >= SMALL_TASKS_PER_DAY:
        return 0
    return await _award(db, user, "task", task_key(task, occurrence), amount, task.title)


async def task_uncompleted(db: AsyncSession, user: User, task: Task, occurrence: date) -> None:
    await db.execute(
        delete(XPEvent).where(
            XPEvent.user_id == user.id, XPEvent.source_key == task_key(task, occurrence)
        )
    )


async def journal_written(db: AsyncSession, user: User, entry_date: date, title: str) -> int:
    """15 XP за день дневника. За давние дни не начисляем — задним числом не прокачаться."""
    if entry_date < local_today(user) - timedelta(days=1):
        return 0
    return await _award(db, user, "journal", f"journal:{entry_date.isoformat()}", JOURNAL_XP, title)


async def journal_day_cleared(db: AsyncSession, user: User, entry_date: date) -> None:
    await db.execute(
        delete(XPEvent).where(
            XPEvent.user_id == user.id,
            XPEvent.source_key == f"journal:{entry_date.isoformat()}",
        )
    )


async def progress(db: AsyncSession, user: User) -> ProgressOut:
    total = await db.scalar(
        select(func.coalesce(func.sum(XPEvent.amount), 0)).where(XPEvent.user_id == user.id)
    )
    today = await db.scalar(
        select(func.coalesce(func.sum(XPEvent.amount), 0)).where(
            XPEvent.user_id == user.id, XPEvent.created_at >= _start_of_today(user)
        )
    )
    recent = await db.scalars(
        select(XPEvent)
        .where(XPEvent.user_id == user.id)
        .order_by(XPEvent.created_at.desc())
        .limit(20)
    )
    level, in_level, needed = level_for(int(total or 0))
    return ProgressOut(
        level=level,
        xp_in_level=in_level,
        xp_for_next_level=needed,
        total_xp=int(total or 0),
        today_xp=int(today or 0),
        recent=[XPEventOut.model_validate(event) for event in recent],
    )


async def _award(
    db: AsyncSession, user: User, source_type: str, key: str, amount: int, title: str
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
        )
        .on_conflict_do_nothing(index_elements=["user_id", "source_key"])
        .returning(XPEvent.amount)
    )
    return int(inserted or 0)


async def _small_tasks_today(db: AsyncSession, user: User) -> int:
    count = await db.scalar(
        select(func.count()).where(
            XPEvent.user_id == user.id,
            XPEvent.source_type == "task",
            XPEvent.amount == TASK_XP[1],
            XPEvent.created_at >= _start_of_today(user),
        )
    )
    return int(count or 0)


def _start_of_today(user: User) -> datetime:
    tz = ZoneInfo(user.timezone)
    return datetime.combine(local_today(user), time.min, tz)
