from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import update
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Goal
from tests.conftest import bearer, sign_in_device


async def _goal(client: AsyncClient, tokens: dict, **fields) -> dict:
    response = await client.post(
        "/goals", headers=bearer(tokens), json={"title": "Пробежать 10 км", **fields}
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _xp(client: AsyncClient, tokens: dict, source: str) -> list[dict]:
    progress = (await client.get("/progress", headers=bearer(tokens))).json()
    return [e for e in progress["recent"] if e["source_type"] == source]


async def test_metric_progress(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    goal = await _goal(
        client, tokens, metric_unit="км", start_value=2, current_value=2, target_value=10
    )

    updated = (
        await client.patch(
            f"/goals/{goal['id']}", headers=bearer(tokens), json={"current_value": 6}
        )
    ).json()

    assert updated["progress"] == 0.5


async def test_steps_progress_and_xp(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    goal = await _goal(client, tokens, steps=["Купить кроссовки", "Пробежать 3 км"], sphere="body")
    step = goal["steps"][0]

    updated = (
        await client.patch(
            f"/goals/{goal['id']}/steps/{step['id']}",
            headers=bearer(tokens),
            json={"is_done": True},
        )
    ).json()

    assert updated["progress"] == 0.5
    events = await _xp(client, tokens, "goal_step")
    assert [(e["amount"], e["sphere"]) for e in events] == [(100, "body")]

    await client.patch(
        f"/goals/{goal['id']}/steps/{step['id']}",
        headers=bearer(tokens),
        json={"is_done": False},
    )
    assert await _xp(client, tokens, "goal_step") == []


async def test_step_xp_is_capped_per_day(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    goal = await _goal(client, tokens, steps=[f"Шаг {i}" for i in range(5)])

    for step in goal["steps"]:
        await client.patch(
            f"/goals/{goal['id']}/steps/{step['id']}",
            headers=bearer(tokens),
            json={"is_done": True},
        )

    assert len(await _xp(client, tokens, "goal_step")) == 3


async def test_goal_completed_same_day_gives_no_xp(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    goal = await _goal(client, tokens)

    done = (
        await client.patch(f"/goals/{goal['id']}", headers=bearer(tokens), json={"status": "done"})
    ).json()

    assert done["status"] == "done"
    assert done["progress"] == 1
    assert await _xp(client, tokens, "goal") == []


async def test_achieved_goal_gives_500_and_reopening_takes_it_back(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    goal = await _goal(client, tokens)
    async with sessionmaker() as session:
        await session.execute(
            update(Goal).values(created_at=datetime.now(UTC) - timedelta(days=10))
        )
        await session.commit()

    await client.patch(f"/goals/{goal['id']}", headers=bearer(tokens), json={"status": "done"})
    assert [e["amount"] for e in await _xp(client, tokens, "goal")] == [500]

    await client.patch(f"/goals/{goal['id']}", headers=bearer(tokens), json={"status": "active"})
    assert await _xp(client, tokens, "goal") == []


async def test_task_can_be_linked_to_goal(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    goal = await _goal(client, tokens)

    task = (
        await client.post(
            "/tasks",
            headers=bearer(tokens),
            json={"title": "Пробежка 3 км", "goal_id": goal["id"], "sphere": "body"},
        )
    ).json()
    foreign = await client.post(
        "/tasks",
        headers=bearer(tokens),
        json={"title": "x", "goal_id": "00000000-0000-0000-0000-000000000000"},
    )

    assert task["goal_id"] == goal["id"]
    assert task["sphere"] == "body"
    assert foreign.status_code == 404


async def test_steps_can_be_added_and_removed(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    goal = await _goal(client, tokens)

    with_step = (
        await client.post(
            f"/goals/{goal['id']}/steps", headers=bearer(tokens), json={"title": "Шаг"}
        )
    ).json()
    without = (
        await client.delete(
            f"/goals/{goal['id']}/steps/{with_step['steps'][0]['id']}", headers=bearer(tokens)
        )
    ).json()

    assert [s["title"] for s in with_step["steps"]] == ["Шаг"]
    assert without["steps"] == []
