"""Цели: шаги, метрика прогресса, опыт за шаги и за достигнутую цель."""

import uuid
from datetime import timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.time import utcnow
from app.models import Goal, GoalStep, User
from app.schemas.goals import GoalIn, GoalOut
from app.services import xp

# Цель, созданную и сразу закрытую, «достигнутой» не считаем — иначе 500 XP за минуту.
GOAL_MIN_AGE = timedelta(hours=24)


def goal_key(goal: Goal) -> str:
    return f"goal:{goal.id}"


def step_key(step: GoalStep) -> str:
    return f"goalstep:{step.id}"


def progress(goal: Goal) -> float:
    """0…1: по метрике, если задана цель-число, иначе по доле выполненных шагов."""
    if goal.status == "done":
        return 1.0
    if goal.target_value is not None:
        start = goal.start_value or 0
        current = goal.current_value if goal.current_value is not None else start
        span = goal.target_value - start
        if span:
            return min(max((current - start) / span, 0.0), 1.0)
    if goal.steps:
        return sum(step.is_done for step in goal.steps) / len(goal.steps)
    return 0.0


def present(goal: Goal) -> GoalOut:
    out = GoalOut.model_validate(goal)
    out.progress = round(progress(goal), 4)
    return out


async def list_goals(db: AsyncSession, user_id: uuid.UUID) -> list[Goal]:
    rows = await db.scalars(
        select(Goal)
        .where(Goal.user_id == user_id, Goal.deleted_at.is_(None))
        .order_by(Goal.status, Goal.position, Goal.created_at)
    )
    return list(rows)


async def get_goal(db: AsyncSession, user_id: uuid.UUID, goal_id: uuid.UUID) -> Goal:
    goal = await db.get(Goal, goal_id)
    if goal is None or goal.user_id != user_id or goal.deleted_at is not None:
        raise AppError("goal_not_found", status_code=404)
    return goal


def create_goal(
    db: AsyncSession,
    user: User,
    data: GoalIn,
    *,
    sphere: str | None = None,
    capture_id: uuid.UUID | None = None,
) -> Goal:
    goal = Goal(
        id=uuid.uuid4(),
        user_id=user.id,
        title=data.title.strip(),
        why=(data.why or "").strip() or None,
        deadline=data.deadline,
        metric_unit=(data.metric_unit or "").strip() or None,
        start_value=data.start_value,
        current_value=data.current_value,
        target_value=data.target_value,
        sphere=sphere,
        status="active",
        position=utcnow().timestamp(),
        capture_id=capture_id,
        steps=[],
    )
    for index, title in enumerate(t.strip() for t in data.steps):
        if title:
            goal.steps.append(_new_step(goal, title[:300], index))
    db.add(goal)
    return goal


async def update_goal(db: AsyncSession, user: User, goal: Goal, changes: dict[str, Any]) -> None:
    for field in ("title", "deadline", "start_value", "current_value", "target_value", "position"):
        if field in changes and (changes[field] is not None or field not in ("title", "position")):
            setattr(goal, field, changes[field].strip() if field == "title" else changes[field])
    for field in ("why", "metric_unit"):
        if field in changes:
            setattr(goal, field, (changes[field] or "").strip() or None)
    if "sphere" in changes:
        goal.sphere = changes["sphere"]
    status = changes.get("status")
    if status and status != goal.status:
        goal.status = status
        if status == "done":
            goal.completed_at = utcnow()
            if utcnow() - goal.created_at >= GOAL_MIN_AGE:
                await xp.award(
                    db, user, "goal", goal_key(goal), xp.GOAL_XP, goal.title, sphere=goal.sphere
                )
        else:
            goal.completed_at = None
            await xp.revoke(db, user, goal_key(goal))


def delete_goal(goal: Goal) -> None:
    goal.deleted_at = utcnow()


# --- Шаги ---


def add_step(goal: Goal, title: str) -> GoalStep:
    position = max((step.position for step in goal.steps), default=-1) + 1
    step = _new_step(goal, title.strip(), position)
    goal.steps.append(step)
    return step


def get_step(goal: Goal, step_id: uuid.UUID) -> GoalStep:
    for step in goal.steps:
        if step.id == step_id:
            return step
    raise AppError("step_not_found", status_code=404)


async def update_step(
    db: AsyncSession, user: User, goal: Goal, step: GoalStep, changes: dict[str, Any]
) -> None:
    if changes.get("title"):
        step.title = changes["title"].strip()
    if changes.get("position") is not None:
        step.position = changes["position"]
    done = changes.get("is_done")
    if done is None or done == step.is_done:
        return
    step.is_done = done
    step.done_at = utcnow() if done else None
    if done:
        # Не больше трёх шагов в день приносят опыт — шаги не дробят ради XP.
        if await xp.count_today(db, user, "goal_step") < xp.GOAL_STEPS_PER_DAY:
            await xp.award(
                db,
                user,
                "goal_step",
                step_key(step),
                xp.GOAL_STEP_XP,
                step.title,
                sphere=goal.sphere,
            )
    else:
        await xp.revoke(db, user, step_key(step))


async def delete_step(db: AsyncSession, user: User, goal: Goal, step: GoalStep) -> None:
    goal.steps.remove(step)
    await xp.revoke(db, user, step_key(step))


def _new_step(goal: Goal, title: str, position: float) -> GoalStep:
    return GoalStep(
        id=uuid.uuid4(),
        goal_id=goal.id,
        user_id=goal.user_id,
        title=title,
        is_done=False,
        position=position,
    )
