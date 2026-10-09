import asyncio
from datetime import UTC, date, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import update
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Quest, XPEvent
from app.services import game
from app.services.xp import streak
from tests.conftest import bearer, sign_in_device


async def _progress(client: AsyncClient, tokens: dict) -> dict:
    return (await client.get("/progress", headers=bearer(tokens))).json()


async def _done_task(client: AsyncClient, tokens: dict, title: str = "Задача") -> None:
    task = (await client.post("/tasks", headers=bearer(tokens), json={"title": title})).json()
    await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})


def test_streak_survives_one_missed_day() -> None:
    today = date(2026, 10, 10)
    days = {today - timedelta(days=d) for d in (1, 2, 4, 5)}

    assert streak(days, today) == 4
    # Два пропуска подряд серию рвут.
    assert streak({today - timedelta(days=d) for d in (0, 3, 4)}, today) == 1
    assert streak(set(), today) == 0


async def test_default_spheres_and_their_levels(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _done_task(client, tokens)

    progress = await _progress(client, tokens)

    keys = [s["key"] for s in progress["spheres"]]
    assert keys == ["body", "mind", "finance", "discipline", "balance"]
    discipline = next(s for s in progress["spheres"] if s["key"] == "discipline")
    assert discipline["total_xp"] >= 10
    assert discipline["name"] == "Дисциплина"


async def test_task_xp_goes_to_its_sphere(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    task = (
        await client.post(
            "/tasks", headers=bearer(tokens), json={"title": "Прочитать главу", "sphere": "mind"}
        )
    ).json()
    await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})

    progress = await _progress(client, tokens)

    mind = next(s for s in progress["spheres"] if s["key"] == "mind")
    assert mind["total_xp"] == 10


async def test_custom_sphere_lifecycle(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    created = (
        await client.post("/spheres", headers=bearer(tokens), json={"name": "Музыка", "icon": "🎸"})
    ).json()
    assert created["is_custom"] is True

    task = (
        await client.post(
            "/tasks", headers=bearer(tokens), json={"title": "Гаммы", "sphere": created["key"]}
        )
    ).json()
    assert task["sphere"] == created["key"]

    spheres = (await client.get("/spheres", headers=bearer(tokens))).json()
    assert next(s for s in spheres if s["id"] == created["id"])["is_custom"] is True
    body = next(s for s in spheres if s["key"] == "body")
    assert (
        await client.delete(f"/spheres/{body['id']}", headers=bearer(tokens))
    ).status_code == 409
    renamed = (
        await client.patch(f"/spheres/{body['id']}", headers=bearer(tokens), json={"name": "Спорт"})
    ).json()
    assert renamed["name"] == "Спорт"
    assert (
        await client.delete(f"/spheres/{created['id']}", headers=bearer(tokens))
    ).status_code == 204


async def test_unknown_sphere_is_rejected(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    response = await client.post(
        "/tasks", headers=bearer(tokens), json={"title": "x", "sphere": "nope"}
    )

    assert response.status_code == 422


async def test_quests_are_created_and_completed(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    quests = (await _progress(client, tokens))["quests"]

    kinds = {(q["period"], q["kind"]): q for q in quests}
    assert ("week", "tasks") in kinds and ("week", "journal") in kinds
    assert ("day", "tasks") in kinds
    day = kinds[("day", "tasks")]
    assert day["target"] == 3 and day["reward"] == 50

    for i in range(3):
        await _done_task(client, tokens, f"Задача {i}")
    progress = await _progress(client, tokens)

    day = next(q for q in progress["quests"] if q["period"] == "day")
    assert day["progress"] == 3
    assert day["completed_at"] is not None
    assert [e["amount"] for e in progress["recent"] if e["source_type"] == "quest"] == [50]


async def test_parallel_progress_requests_create_quests_once(
    client: AsyncClient, monkeypatch
) -> None:
    tokens = await sign_in_device(client)
    original = game._plan_week
    both_planning = asyncio.Event()
    started = 0

    async def plan_together(db, user, today):
        nonlocal started
        plan = await original(db, user, today)
        started += 1
        if started == 2:
            both_planning.set()
        await asyncio.wait_for(both_planning.wait(), timeout=5)
        return plan

    monkeypatch.setattr(game, "_plan_week", plan_together)
    responses = await asyncio.gather(
        client.get("/progress", headers=bearer(tokens)),
        client.get("/progress", headers=bearer(tokens)),
    )

    for response in responses:
        assert response.status_code == 200, response.text
        quests = response.json()["quests"]
        assert len(quests) == 3
        assert len({q["id"] for q in quests}) == 3


async def test_quest_is_unsettled_when_progress_rolls_back(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _progress(client, tokens)
    ids = []
    for i in range(3):
        task = (await client.post("/tasks", headers=bearer(tokens), json={"title": f"{i}"})).json()
        await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})
        ids.append(task["id"])
    await _progress(client, tokens)

    await client.patch(f"/tasks/{ids[0]}", headers=bearer(tokens), json={"status": "todo"})
    progress = await _progress(client, tokens)

    day = next(q for q in progress["quests"] if q["period"] == "day")
    assert day["completed_at"] is None
    assert not [e for e in progress["recent"] if e["source_type"] == "quest"]


async def test_comeback_quest_after_a_break(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    await _done_task(client, tokens)
    async with sessionmaker() as session:
        await session.execute(
            update(XPEvent).values(created_at=datetime.now(UTC) - timedelta(days=5))
        )
        await session.execute(
            # Квесты, созданные при выполнении задачи, — «вчерашние»: удаляем, чтобы
            # сегодняшний день составился заново.
            XPEvent.__table__.delete().where(XPEvent.source_type == "quest")
        )
        await session.execute(Quest.__table__.delete())
        await session.commit()

    quests = (await _progress(client, tokens))["quests"]

    assert [q["kind"] for q in quests if q["period"] == "day"] == ["comeback"]


async def test_workout_quest_appears_for_people_who_train(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    # Квесты недели уже составлены, а тренировки начались посреди недели.
    assert "workouts" not in [q["kind"] for q in (await _progress(client, tokens))["quests"]]
    await client.post(
        "/workouts",
        headers=bearer(tokens),
        json={"sets": [{"exercise": "Бег", "distance_m": 3000}]},
    )

    quests = (await _progress(client, tokens))["quests"]

    assert "workouts" in [q["kind"] for q in quests]


async def test_achievements_catalog_and_unlocks(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _done_task(client, tokens)

    achievements = (await _progress(client, tokens))["achievements"]

    by_code = {a["code"]: a for a in achievements}
    assert by_code["first_task"]["achieved_at"] is not None
    assert by_code["first_workout"]["achieved_at"] is None
    assert achievements[0]["code"] == "first_task"


async def test_streak_counts_active_days(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _done_task(client, tokens)

    assert (await _progress(client, tokens))["streak_days"] == 1
