"""Тренировки: подходы, личные рекорды и опыт."""

import re
import uuid
from collections import defaultdict
from collections.abc import Sequence
from datetime import date
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.time import utcnow
from app.models import User, Workout, WorkoutSet
from app.schemas.workouts import ExercisePoint, ExerciseStats, SetIn, WorkoutIn
from app.services import xp


def exercise_key(name: str) -> str:
    """«Жим лёжа», «жим лежа » и «Жим  Лёжа!» — одно упражнение."""
    value = name.lower().replace("ё", "е")
    value = re.sub(r"[^\w\s]", " ", value)
    return re.sub(r"\s+", " ", value).strip()[:100]


def workout_key(workout: Workout) -> str:
    return f"workout:{workout.id}"


def pr_key(workout: Workout) -> str:
    return f"pr:{workout.id}"


async def get_workout(db: AsyncSession, user_id: uuid.UUID, workout_id: uuid.UUID) -> Workout:
    workout = await db.get(Workout, workout_id)
    if workout is None or workout.user_id != user_id or workout.deleted_at is not None:
        raise AppError("workout_not_found", status_code=404)
    return workout


async def list_workouts(db: AsyncSession, user_id: uuid.UUID, limit: int = 60) -> list[Workout]:
    rows = await db.scalars(
        select(Workout)
        .where(Workout.user_id == user_id, Workout.deleted_at.is_(None))
        .order_by(Workout.workout_date.desc(), Workout.created_at.desc())
        .limit(limit)
    )
    return list(rows)


async def create_workout(
    db: AsyncSession,
    user: User,
    data: WorkoutIn,
    *,
    capture_id: uuid.UUID | None = None,
) -> tuple[Workout, int, list[str]]:
    """Сохраняет тренировку, отмечает рекорды и начисляет опыт: 25 за тренировку
    (не больше двух в день) и +50, если поставлен хоть один личный рекорд."""
    workout = Workout(
        id=uuid.uuid4(),
        user_id=user.id,
        workout_date=data.workout_date or xp.local_today(user),
        started_at=data.started_at,
        ended_at=data.ended_at,
        title=(data.title or "").strip() or None,
        note=(data.note or "").strip() or None,
        capture_id=capture_id,
        sets=[],
    )
    workout.sets = _make_sets(workout, user, data.sets)
    db.add(workout)
    await db.flush()
    records = await _mark_records(db, workout)

    gained = 0
    if await xp.count_today(db, user, "workout") < xp.WORKOUTS_PER_DAY:
        gained += await xp.award(
            db, user, "workout", workout_key(workout), xp.WORKOUT_XP, describe(workout)
        )
    if records:
        gained += await xp.award(db, user, "pr", pr_key(workout), xp.PR_XP, ", ".join(records))
    return workout, gained, records


async def update_workout(
    db: AsyncSession, user: User, workout: Workout, changes: dict[str, Any]
) -> list[str]:
    if changes.get("workout_date") is not None:
        workout.workout_date = changes["workout_date"]
    for field in ("title", "note"):
        if field in changes:
            setattr(workout, field, (changes[field] or "").strip() or None)
    if changes.get("sets") is not None:
        workout.sets = _make_sets(workout, user, [SetIn(**s) for s in changes["sets"]])
        await db.flush()
    records = await _mark_records(db, workout)
    # Рекорд мог появиться или исчезнуть после правки подходов.
    if records:
        await xp.award(db, user, "pr", pr_key(workout), xp.PR_XP, ", ".join(records))
    else:
        await xp.revoke(db, user, pr_key(workout))
    return records


async def delete_workout(db: AsyncSession, user: User, workout: Workout) -> None:
    workout.deleted_at = utcnow()
    await xp.revoke(db, user, workout_key(workout))
    await xp.revoke(db, user, pr_key(workout))


def describe(workout: Workout) -> str:
    if workout.title:
        return workout.title
    names: list[str] = []
    for item in workout.sets:
        if item.exercise not in names:
            names.append(item.exercise)
    return ", ".join(names[:3]) or "—"


def _make_sets(workout: Workout, user: User, sets: Sequence[SetIn]) -> list[WorkoutSet]:
    return [
        WorkoutSet(
            id=uuid.uuid4(),
            workout_id=workout.id,
            user_id=user.id,
            exercise=item.exercise.strip(),
            exercise_key=exercise_key(item.exercise),
            position=index,
            weight_kg=item.weight_kg,
            reps=item.reps,
            duration_sec=item.duration_sec,
            distance_m=item.distance_m,
            is_pr=False,
        )
        for index, item in enumerate(sets)
    ]


async def _mark_records(db: AsyncSession, workout: Workout) -> list[str]:
    """Отмечает лучший подход по каждому упражнению, если он лучше всего, что было раньше.

    Сравнение только с прошлыми тренировками: первая тренировка упражнения — это точка
    отсчёта, а не рекорд. Вес сравнивается с весом, повторы без веса — с повторами без веса,
    время и дистанция — со временем и дистанцией.
    """
    for item in workout.sets:
        item.is_pr = False
    by_exercise: dict[str, list[WorkoutSet]] = defaultdict(list)
    for item in workout.sets:
        by_exercise[item.exercise_key].append(item)

    records: list[str] = []
    for key, sets in by_exercise.items():
        best = await _previous_best(db, workout, key)
        if best is None:
            continue
        record = _record_set(sets, best)
        if record is not None:
            record.is_pr = True
            records.append(record.exercise)
    return records


async def _previous_best(db: AsyncSession, workout: Workout, key: str) -> dict[str, float] | None:
    row = (
        await db.execute(
            select(
                func.count(WorkoutSet.id),
                func.max(WorkoutSet.weight_kg),
                func.max(WorkoutSet.reps).filter(WorkoutSet.weight_kg.is_(None)),
                func.max(WorkoutSet.duration_sec),
                func.max(WorkoutSet.distance_m),
            )
            .join(Workout, Workout.id == WorkoutSet.workout_id)
            .where(
                WorkoutSet.user_id == workout.user_id,
                WorkoutSet.exercise_key == key,
                Workout.deleted_at.is_(None),
                Workout.id != workout.id,
                (Workout.workout_date < workout.workout_date)
                | (
                    (Workout.workout_date == workout.workout_date)
                    & (Workout.created_at < workout.created_at)
                ),
            )
        )
    ).one()
    count, weight, reps, duration, distance = row
    if not count:
        return None
    return {"weight": weight, "reps": reps, "duration": duration, "distance": distance}


def _record_set(sets: list[WorkoutSet], best: dict[str, float | None]) -> WorkoutSet | None:
    measures = (
        ("weight", lambda s: s.weight_kg),
        ("reps", lambda s: s.reps if s.weight_kg is None else None),
        ("duration", lambda s: s.duration_sec),
        ("distance", lambda s: s.distance_m),
    )
    for name, value in measures:
        candidates = [s for s in sets if value(s) is not None]
        previous = best[name]
        if not candidates or previous is None:
            continue
        top = max(candidates, key=value)
        if value(top) > previous:
            return top
    return None


# --- Статистика по упражнениям ---


async def exercise_stats(db: AsyncSession, user: User, limit: int = 30) -> list[ExerciseStats]:
    rows = (
        await db.execute(
            select(WorkoutSet, Workout.workout_date)
            .join(Workout, Workout.id == WorkoutSet.workout_id)
            .where(WorkoutSet.user_id == user.id, Workout.deleted_at.is_(None))
            .order_by(Workout.workout_date)
        )
    ).all()

    names: dict[str, str] = {}
    by_day: dict[str, dict[date, list[WorkoutSet]]] = defaultdict(lambda: defaultdict(list))
    for item, day in rows:
        names[item.exercise_key] = item.exercise
        by_day[item.exercise_key][day].append(item)

    stats = []
    for key, days in by_day.items():
        history = [_point(day, sets) for day, sets in sorted(days.items())]
        stats.append(
            ExerciseStats(
                key=key,
                name=names[key],
                sessions=len(history),
                last_date=history[-1].date,
                best_weight_kg=_max(p.best_weight_kg for p in history),
                best_reps=_max(p.best_reps for p in history),
                best_duration_sec=_max(p.best_duration_sec for p in history),
                best_distance_m=_max(p.best_distance_m for p in history),
                history=history[-30:],
            )
        )
    stats.sort(key=lambda s: s.last_date, reverse=True)
    return stats[:limit]


def _point(day: date, sets: list[WorkoutSet]) -> ExercisePoint:
    return ExercisePoint(
        date=day,
        best_weight_kg=_max(s.weight_kg for s in sets),
        best_reps=_max(s.reps for s in sets),
        volume_kg=round(sum((s.weight_kg or 0) * (s.reps or 0) for s in sets), 1),
        best_duration_sec=_max(s.duration_sec for s in sets),
        best_distance_m=_max(s.distance_m for s in sets),
    )


def _max(values):
    present = [v for v in values if v is not None]
    return max(present) if present else None
