"""Прокачка поверх журнала опыта: уровни сфер, квесты, достижения, серия.

Всё считается кодом по фиксированным правилам из xp_events. Квесты пока составляются
по правилам из истории пользователя; подстройку под цели и профиль сделает ИИ-коуч.
"""

import uuid
from dataclasses import dataclass
from datetime import date, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.time import utcnow
from app.models import Goal, JournalEntry, Quest, User, UserAchievement, Workout, XPEvent
from app.schemas.game import AchievementOut, ProgressOut, QuestOut, SphereOut, XPEventOut
from app.services import finance, spheres, xp

# --- Квесты ---


@dataclass(frozen=True)
class QuestRule:
    # Какие начисления опыта засчитываются в квест.
    sources: tuple[str, ...]
    sphere: str | None


QUEST_RULES: dict[str, QuestRule] = {
    "tasks": QuestRule(("task",), "discipline"),
    "journal": QuestRule(("journal",), "balance"),
    "workouts": QuestRule(("workout",), "body"),
    "goal_steps": QuestRule(("goal_step",), "discipline"),
    # «Вернись»: любой опыт за день после перерыва.
    "comeback": QuestRule(("task", "journal", "workout", "goal_step", "goal", "pr"), None),
}
DAY_QUEST_REWARD = 50
# Сколько дней без опыта считается перерывом, после которого предлагается «Вернись».
COMEBACK_AFTER_DAYS = 3


def week_start(day: date) -> date:
    return day - timedelta(days=day.weekday())


def period_end(quest: Quest) -> date:
    return quest.period_start + timedelta(days=6 if quest.period == "week" else 0)


async def ensure_quests(db: AsyncSession, user: User) -> list[Quest]:
    """Квесты текущей недели и дня: создаёт недостающие, возвращает активные."""
    today = xp.local_today(user)
    monday = week_start(today)
    existing = await _quests(db, user, monday, today)

    # Недостающие недельные квесты: в начале недели — все, а посреди недели — новые виды
    # (начал тренироваться или поставил цель — квест появляется сразу, не через неделю).
    week_kinds = {q.kind for q in existing if q.period == "week"}
    planned = []
    for kind, target, reward in await _plan_week(db, user, today):
        if kind not in week_kinds:
            planned.append(_quest(user, "week", monday, kind, target, reward))
    if not any(q.period == "day" for q in existing):
        kind, target = await _plan_day(db, user, today)
        planned.append(_quest(user, "day", today, kind, target, DAY_QUEST_REWARD))
    if planned:
        # Приложение и виджеты могут запросить прогресс одновременно.
        await db.execute(
            insert(Quest)
            .values(planned)
            .on_conflict_do_nothing(index_elements=["user_id", "period", "period_start", "kind"])
        )
    return await _quests(db, user, monday, today)


async def quest_progress(db: AsyncSession, user: User, quest: Quest) -> int:
    rule = QUEST_RULES[quest.kind]
    start = xp.start_of_day(user, quest.period_start)
    end = xp.start_of_day(user, period_end(quest) + timedelta(days=1))
    value = await db.scalar(
        select(func.count()).where(
            XPEvent.user_id == user.id,
            XPEvent.source_type.in_(rule.sources),
            XPEvent.created_at >= start,
            XPEvent.created_at < end,
        )
    )
    return int(value or 0)


async def settle_quests(db: AsyncSession, user: User, quests: list[Quest]) -> list[QuestOut]:
    """Засчитывает выполненные квесты (+опыт) и снимает зачёт, если прогресс откатился
    (например, задачу вернули в работу)."""
    result = []
    for quest in quests:
        progress = await quest_progress(db, user, quest)
        key = f"quest:{quest.id}"
        if progress >= quest.target and quest.completed_at is None:
            quest.completed_at = utcnow()
            await xp.award(
                db,
                user,
                "quest",
                key,
                quest.reward,
                f"{quest.kind}:{quest.target}",
                sphere=quest.sphere,
            )
        elif progress < quest.target and quest.completed_at is not None:
            quest.completed_at = None
            await xp.revoke(db, user, key)
        result.append(
            QuestOut(
                id=quest.id,
                period=quest.period,
                period_start=quest.period_start,
                period_end=period_end(quest),
                kind=quest.kind,
                target=quest.target,
                progress=min(progress, quest.target),
                reward=quest.reward,
                sphere=quest.sphere,
                completed_at=quest.completed_at,
            )
        )
    return result


async def _quests(db: AsyncSession, user: User, monday: date, today: date) -> list[Quest]:
    rows = await db.scalars(
        select(Quest)
        .where(
            Quest.user_id == user.id,
            ((Quest.period == "week") & (Quest.period_start == monday))
            | ((Quest.period == "day") & (Quest.period_start == today)),
        )
        .order_by(Quest.period.desc(), Quest.created_at)
    )
    return list(rows)


async def _plan_week(db: AsyncSession, user: User, today: date) -> list[tuple[str, int, int]]:
    """Цели недели по последним четырём неделям: чуть выше привычного, но достижимо."""
    since = xp.start_of_day(user, today - timedelta(days=28))
    tasks = await xp.count_since(db, user, ("task",), since) / 4
    journal = await xp.count_since(db, user, ("journal",), since) / 4
    workouts = await xp.count_since(db, user, ("workout",), since) / 4

    plan = []
    target = _clamp(round(tasks * 1.15), 5, 40)
    plan.append(("tasks", target, 150 if target >= 15 else 100))
    target = _clamp(round(journal) + 1, 3, 7)
    plan.append(("journal", target, 150 if target >= 6 else 100))
    has_workouts = await db.scalar(
        select(func.count()).where(Workout.user_id == user.id, Workout.deleted_at.is_(None))
    )
    if has_workouts or await _has_goal_in(db, user, "body"):
        target = _clamp(round(workouts) + (1 if workouts >= 1.5 else 0), 2, 6)
        plan.append(("workouts", target, 150))
    if await _has_goal_in(db, user, None):
        plan.append(("goal_steps", 2, 150))
    return plan


async def _plan_day(db: AsyncSession, user: User, today: date) -> tuple[str, int]:
    last = await db.scalar(
        select(func.max(XPEvent.created_at)).where(
            XPEvent.user_id == user.id, XPEvent.source_type != "quest"
        )
    )
    if last is not None:
        last_day = last.astimezone(ZoneInfo(user.timezone)).date()
        if (today - last_day).days >= COMEBACK_AFTER_DAYS:
            return "comeback", 1
    return "tasks", 3


async def _has_goal_in(db: AsyncSession, user: User, sphere: str | None) -> bool:
    query = select(func.count()).where(
        Goal.user_id == user.id, Goal.deleted_at.is_(None), Goal.status == "active"
    )
    if sphere:
        query = query.where(Goal.sphere == sphere)
    return bool(await db.scalar(query))


def _quest(user: User, period: str, start: date, kind: str, target: int, reward: int) -> dict:
    return {
        "id": uuid.uuid4(),
        "user_id": user.id,
        "period": period,
        "period_start": start,
        "kind": kind,
        "target": target,
        "reward": reward,
        "sphere": QUEST_RULES[kind].sphere,
    }


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


# --- Достижения ---

# Порядок — как в каталоге приложения.
ACHIEVEMENTS = (
    "first_task",
    "tasks_50",
    "tasks_200",
    "journal_7",
    "journal_30",
    "first_workout",
    "workouts_10",
    "workouts_50",
    "first_pr",
    "budget_month",
    "goal_done",
    "quests_10",
    "streak_7",
    "streak_30",
    "level_5",
    "level_10",
    "level_20",
)


async def check_achievements(
    db: AsyncSession, user: User, *, level: int, streak_days: int
) -> list[AchievementOut]:
    counts = dict(
        (
            await db.execute(
                select(XPEvent.source_type, func.count())
                .where(XPEvent.user_id == user.id)
                .group_by(XPEvent.source_type)
            )
        ).all()
    )
    today = xp.local_today(user)
    journal_days = await _journal_days(db, user, today - timedelta(days=400))
    journal_streak = xp.streak(journal_days, today)

    earned = {
        "first_task": counts.get("task", 0) >= 1,
        "tasks_50": counts.get("task", 0) >= 50,
        "tasks_200": counts.get("task", 0) >= 200,
        "journal_7": journal_streak >= 7,
        "journal_30": journal_streak >= 30,
        "first_workout": counts.get("workout", 0) >= 1,
        "workouts_10": counts.get("workout", 0) >= 10,
        "workouts_50": counts.get("workout", 0) >= 50,
        "first_pr": counts.get("pr", 0) >= 1,
        "budget_month": await _budget_weeks_in_row(db, user) >= 4,
        "goal_done": counts.get("goal", 0) >= 1,
        "quests_10": counts.get("quest", 0) >= 10,
        "streak_7": streak_days >= 7,
        "streak_30": streak_days >= 30,
        "level_5": level >= 5,
        "level_10": level >= 10,
        "level_20": level >= 20,
    }
    new = [code for code, ok in earned.items() if ok]
    if new:
        await db.execute(
            insert(UserAchievement)
            .values([{"id": uuid.uuid4(), "user_id": user.id, "code": code} for code in new])
            .on_conflict_do_nothing(index_elements=["user_id", "code"])
        )
    achieved = dict(
        (
            await db.execute(
                select(UserAchievement.code, UserAchievement.achieved_at).where(
                    UserAchievement.user_id == user.id
                )
            )
        ).all()
    )
    return [AchievementOut(code=code, achieved_at=achieved.get(code)) for code in ACHIEVEMENTS]


async def _journal_days(db: AsyncSession, user: User, since: date) -> set[date]:
    rows = await db.scalars(
        select(JournalEntry.entry_date)
        .where(
            JournalEntry.user_id == user.id,
            JournalEntry.deleted_at.is_(None),
            JournalEntry.entry_date >= since,
        )
        .distinct()
    )
    return set(rows)


async def _budget_weeks_in_row(db: AsyncSession, user: User) -> int:
    keys = set(
        await db.scalars(
            select(XPEvent.source_key).where(
                XPEvent.user_id == user.id, XPEvent.source_type == "budget"
            )
        )
    )
    best = run = 0
    monday = week_start(xp.local_today(user))
    for weeks_back in range(1, 60):
        year, week, _ = (monday - timedelta(weeks=weeks_back)).isocalendar()
        if f"budget:{year}-W{week:02d}" in keys:
            run += 1
            best = max(best, run)
        else:
            run = 0
    return best


# --- Сводка прогресса ---


async def progress(db: AsyncSession, user: User) -> ProgressOut:
    """Уровень, сферы, серия, квесты и достижения. Заодно засчитывает то, что пора
    засчитать: недели в рамках бюджета и выполненные квесты."""
    await finance.settle_budget_weeks(db, user)
    quests = await settle_quests(db, user, await ensure_quests(db, user))

    total = await xp.total(db, user)
    level, in_level, needed = xp.level_for(total)
    today = xp.local_today(user)
    streak_days = xp.streak(await xp.active_days(db, user, today - timedelta(days=400)), today)
    sphere_xp = await xp.by_sphere(db, user)
    sphere_rows = await spheres.list_spheres(db, user)

    return ProgressOut(
        level=level,
        xp_in_level=in_level,
        xp_for_next_level=needed,
        total_xp=total,
        today_xp=await xp.today_total(db, user),
        recent=[XPEventOut.model_validate(e) for e in await xp.recent(db, user)],
        spheres=[_sphere_out(row, sphere_xp.get(row.key, 0)) for row in sphere_rows],
        streak_days=streak_days,
        quests=quests,
        achievements=await check_achievements(db, user, level=level, streak_days=streak_days),
    )


def _sphere_out(row, total: int) -> SphereOut:
    level, in_level, needed = xp.level_for(total)
    out = SphereOut.model_validate(row)
    return out.model_copy(
        update={
            "is_custom": row.key not in spheres.DEFAULT_SPHERES,
            "level": level,
            "xp_in_level": in_level,
            "xp_for_next_level": needed,
            "total_xp": total,
        }
    )
