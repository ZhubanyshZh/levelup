"""Финансы, тренировки, цели и прокачка (сферы, прогресс)."""

import uuid

from fastapi import APIRouter, Query, status

from app.api.deps import DB, CurrentUser
from app.core.errors import AppError
from app.schemas.finance import (
    BudgetIn,
    Category,
    FinanceSummary,
    TransactionIn,
    TransactionOut,
    TransactionUpdate,
)
from app.schemas.game import ProgressOut, SphereIn, SphereOut, SphereUpdate
from app.schemas.goals import GoalIn, GoalOut, GoalUpdate, StepIn, StepUpdate
from app.schemas.workouts import (
    ExerciseStats,
    WorkoutIn,
    WorkoutOut,
    WorkoutResult,
    WorkoutUpdate,
)
from app.services import finance, game, goals, spheres, workouts

finance_router = APIRouter(prefix="/finance", tags=["finance"])
workouts_router = APIRouter(prefix="/workouts", tags=["workouts"])
goals_router = APIRouter(prefix="/goals", tags=["goals"])
game_router = APIRouter(tags=["progress"])


# --- Финансы ---


@finance_router.get("/transactions")
async def list_transactions(
    user: CurrentUser, db: DB, month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$")
) -> list[TransactionOut]:
    rows = await finance.list_transactions(db, user, finance.parse_month(month, user))
    return [TransactionOut.model_validate(row) for row in rows]


@finance_router.post("/transactions", status_code=status.HTTP_201_CREATED)
async def create_transaction(body: TransactionIn, user: CurrentUser, db: DB) -> TransactionOut:
    row = finance.create_transaction(db, user, body)
    await db.commit()
    return TransactionOut.model_validate(row)


@finance_router.patch("/transactions/{row_id}")
async def update_transaction(
    row_id: uuid.UUID, body: TransactionUpdate, user: CurrentUser, db: DB
) -> TransactionOut:
    row = await finance.get_transaction(db, user.id, row_id)
    finance.update_transaction(row, body.model_dump(exclude_unset=True))
    await db.commit()
    return TransactionOut.model_validate(row)


@finance_router.delete("/transactions/{row_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(row_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    finance.delete_transaction(await finance.get_transaction(db, user.id, row_id))
    await db.commit()


@finance_router.get("/summary")
async def finance_summary(
    user: CurrentUser, db: DB, month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$")
) -> FinanceSummary:
    return await finance.summary(db, user, finance.parse_month(month, user))


@finance_router.put("/budgets")
async def set_budget(body: BudgetIn, user: CurrentUser, db: DB) -> FinanceSummary:
    """Задать месячный лимит (общий или на категорию). Ответ — сводка текущего месяца."""
    if body.category in ("salary", "freelance", "gift", "refund", "other_income"):
        raise AppError("budget_needs_expense_category", status_code=422)
    await finance.set_budget(db, user, body.category, body.monthly_limit)
    await db.commit()
    return await finance.summary(db, user, finance.parse_month(None, user))


@finance_router.delete("/budgets")
async def delete_budget(
    user: CurrentUser, db: DB, category: Category | None = None
) -> FinanceSummary:
    await finance.delete_budget(db, user, category)
    await db.commit()
    return await finance.summary(db, user, finance.parse_month(None, user))


# --- Тренировки ---


@workouts_router.get("")
async def list_workouts(user: CurrentUser, db: DB) -> list[WorkoutOut]:
    return [WorkoutOut.model_validate(w) for w in await workouts.list_workouts(db, user.id)]


@workouts_router.post("", status_code=status.HTTP_201_CREATED)
async def create_workout(body: WorkoutIn, user: CurrentUser, db: DB) -> WorkoutResult:
    workout, gained, records = await workouts.create_workout(db, user, body)
    await db.commit()
    await db.refresh(workout, ["sets"])
    return WorkoutResult(
        workout=WorkoutOut.model_validate(workout), xp_gained=gained, records=records
    )


@workouts_router.get("/exercises")
async def exercise_stats(user: CurrentUser, db: DB) -> list[ExerciseStats]:
    return await workouts.exercise_stats(db, user)


@workouts_router.patch("/{workout_id}")
async def update_workout(
    workout_id: uuid.UUID, body: WorkoutUpdate, user: CurrentUser, db: DB
) -> WorkoutResult:
    workout = await workouts.get_workout(db, user.id, workout_id)
    records = await workouts.update_workout(db, user, workout, body.model_dump(exclude_unset=True))
    await db.commit()
    await db.refresh(workout, ["sets"])
    return WorkoutResult(workout=WorkoutOut.model_validate(workout), records=records)


@workouts_router.delete("/{workout_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_workout(workout_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    workout = await workouts.get_workout(db, user.id, workout_id)
    await workouts.delete_workout(db, user, workout)
    await db.commit()


# --- Цели ---


@goals_router.get("")
async def list_goals(user: CurrentUser, db: DB) -> list[GoalOut]:
    return [goals.present(goal) for goal in await goals.list_goals(db, user.id)]


@goals_router.post("", status_code=status.HTTP_201_CREATED)
async def create_goal(body: GoalIn, user: CurrentUser, db: DB) -> GoalOut:
    sphere = await _sphere(db, user, body.sphere)
    goal = goals.create_goal(db, user, body, sphere=sphere)
    await db.commit()
    return await _goal_out(db, goal)


@goals_router.patch("/{goal_id}")
async def update_goal(goal_id: uuid.UUID, body: GoalUpdate, user: CurrentUser, db: DB) -> GoalOut:
    goal = await goals.get_goal(db, user.id, goal_id)
    changes = body.model_dump(exclude_unset=True)
    if changes.get("sphere"):
        changes["sphere"] = await _sphere(db, user, changes["sphere"])
    await goals.update_goal(db, user, goal, changes)
    await db.commit()
    return await _goal_out(db, goal)


@goals_router.delete("/{goal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_goal(goal_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    goals.delete_goal(await goals.get_goal(db, user.id, goal_id))
    await db.commit()


@goals_router.post("/{goal_id}/steps", status_code=status.HTTP_201_CREATED)
async def add_step(goal_id: uuid.UUID, body: StepIn, user: CurrentUser, db: DB) -> GoalOut:
    goal = await goals.get_goal(db, user.id, goal_id)
    goals.add_step(goal, body.title)
    await db.commit()
    return await _goal_out(db, goal)


@goals_router.patch("/{goal_id}/steps/{step_id}")
async def update_step(
    goal_id: uuid.UUID, step_id: uuid.UUID, body: StepUpdate, user: CurrentUser, db: DB
) -> GoalOut:
    goal = await goals.get_goal(db, user.id, goal_id)
    step = goals.get_step(goal, step_id)
    await goals.update_step(db, user, goal, step, body.model_dump(exclude_unset=True))
    await db.commit()
    return await _goal_out(db, goal)


@goals_router.delete("/{goal_id}/steps/{step_id}")
async def delete_step(goal_id: uuid.UUID, step_id: uuid.UUID, user: CurrentUser, db: DB) -> GoalOut:
    goal = await goals.get_goal(db, user.id, goal_id)
    await goals.delete_step(db, user, goal, goals.get_step(goal, step_id))
    await db.commit()
    return await _goal_out(db, goal)


async def _goal_out(db: DB, goal) -> GoalOut:
    await db.refresh(goal, ["steps"])
    return goals.present(goal)


async def _sphere(db: DB, user, key: str | None) -> str | None:
    if key and await spheres.valid_key(db, user, key) is None:
        raise AppError("sphere_not_found", status_code=422)
    return key


# --- Прогресс и сферы ---


@game_router.get("/progress")
async def get_progress(user: CurrentUser, db: DB) -> ProgressOut:
    """Уровень, сферы, серия, квесты и достижения. Заодно засчитывает квесты и бюджет."""
    result = await game.progress(db, user)
    await db.commit()
    return result


@game_router.get("/spheres")
async def list_spheres(user: CurrentUser, db: DB) -> list[SphereOut]:
    rows = await spheres.list_spheres(db, user)
    await db.commit()
    return [
        SphereOut.model_validate(row).model_copy(
            update={"is_custom": row.key not in spheres.DEFAULT_SPHERES}
        )
        for row in rows
    ]


@game_router.post("/spheres", status_code=status.HTTP_201_CREATED)
async def create_sphere(body: SphereIn, user: CurrentUser, db: DB) -> SphereOut:
    existing = await spheres.list_spheres(db, user)
    position = max((row.position for row in existing), default=0) + 1
    row = spheres.create_sphere(db, user, body.name, body.icon, position)
    await db.commit()
    return SphereOut.model_validate(row).model_copy(update={"is_custom": True})


@game_router.patch("/spheres/{sphere_id}")
async def update_sphere(
    sphere_id: uuid.UUID, body: SphereUpdate, user: CurrentUser, db: DB
) -> SphereOut:
    row = await spheres.get_sphere(db, user.id, sphere_id)
    for field, value in body.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(row, field, value.strip() if isinstance(value, str) else value)
    await db.commit()
    return SphereOut.model_validate(row).model_copy(
        update={"is_custom": row.key not in spheres.DEFAULT_SPHERES}
    )


@game_router.delete("/spheres/{sphere_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sphere(sphere_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    """Удалить можно только свою сферу; стандартные можно переименовать."""
    row = await spheres.get_sphere(db, user.id, sphere_id)
    if row.key in spheres.DEFAULT_SPHERES:
        raise AppError("default_sphere", status_code=409)
    await db.delete(row)
    await db.commit()
