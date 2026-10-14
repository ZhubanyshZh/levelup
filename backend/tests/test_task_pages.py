import json
import uuid
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from httpx import AsyncClient
from sqlalchemy import text

from app.models import User
from app.schemas.task import TaskQuery
from app.services.task_query import task_statement
from tests.conftest import bearer, sign_in_device


@pytest.fixture
def today(monkeypatch: pytest.MonkeyPatch) -> date:
    now = datetime(2026, 10, 14, 22, 30, tzinfo=UTC)
    monkeypatch.setattr(
        "app.services.task_query.xp.local_today",
        lambda user: now.astimezone(ZoneInfo(user.timezone)).date(),
    )
    monkeypatch.setattr("app.services.task_query.utcnow", lambda: now)
    return date(2026, 10, 15)


async def create(client, tokens, **fields):
    response = await client.post(
        "/tasks", headers=bearer(tokens), json={"title": "Задача", **fields}
    )
    assert response.status_code == 201, response.text
    return response.json()


async def page(client, tokens, **params):
    response = await client.get("/tasks/page", headers=bearer(tokens), params=params)
    assert response.status_code == 200, response.text
    return response.json()


async def test_filters_run_together_in_sql(client: AsyncClient, today: date) -> None:
    tokens = await sign_in_device(client, timezone="Asia/Almaty")
    goal = (await client.post("/goals", headers=bearer(tokens), json={"title": "Моя цель"})).json()
    wanted = await create(
        client,
        tokens,
        title="Подготовить ОТЧЁТ",
        notes="для банка",
        due_date=str(today),
        priority="high",
        status="doing",
        sphere="body",
        goal_id=goal["id"],
    )
    await create(client, tokens, title="Отчёт для банка", due_date=str(today), priority="normal")
    await create(
        client, tokens, title="Встреча", due_date=str(today), priority="high", status="doing"
    )
    result = await page(
        client,
        tokens,
        due="today",
        priority="high",
        status="doing",
        sphere="body",
        goal_id=goal["id"],
        q="  БАНК   отчёт ",
    )
    assert [item["id"] for item in result["items"]] == [wanted["id"]]
    assert result["next_cursor"] is None


async def test_dates_use_user_timezone_and_week_has_seven_days(
    client: AsyncClient, today: date
) -> None:
    tokens = await sign_in_device(client, timezone="Asia/Almaty")
    expected = []
    for offset in range(-1, 8):
        task = await create(
            client, tokens, title=str(offset), due_date=str(today + timedelta(days=offset))
        )
        if 0 <= offset <= 6:
            expected.append(task["id"])
    undated = await create(client, tokens)
    completed = await create(client, tokens, due_date=str(today - timedelta(days=1)), status="done")
    assert [
        item["id"] for item in (await page(client, tokens, due="nextSevenDays"))["items"]
    ] == expected
    for due, value in (("today", today), ("tomorrow", today + timedelta(days=1))):
        assert [item["due_date"] for item in (await page(client, tokens, due=due))["items"]] == [
            str(value)
        ]
    assert [item["id"] for item in (await page(client, tokens, due="noDate"))["items"]] == [
        undated["id"]
    ]
    overdue = await page(client, tokens, due="overdue")
    assert len(overdue["items"]) == 1
    assert overdue["items"][0]["id"] != completed["id"]


@pytest.mark.parametrize("sort", ["due", "position"])
async def test_cursor_has_no_gaps_or_duplicates_with_ties_and_nulls(
    client: AsyncClient, today: date, sort: str
) -> None:
    tokens = await sign_in_device(client)
    ids = set()
    for index in range(13):
        task = await create(
            client,
            tokens,
            title=str(index),
            position=0,
            due_date=str(today) if index < 9 else None,
            due_time="09:00" if index < 9 else None,
        )
        ids.add(task["id"])
    seen, cursor = [], None
    while True:
        result = await page(
            client, tokens, limit=3, sort=sort, **({"cursor": cursor} if cursor else {})
        )
        assert len(result["items"]) <= 3
        seen.extend(item["id"] for item in result["items"])
        cursor = result["next_cursor"]
        if not cursor:
            break
    assert len(seen) == len(set(seen)) == 13
    assert set(seen) == ids


async def test_cursor_is_bound_to_filter_and_account(client: AsyncClient, today: date) -> None:
    owner = await sign_in_device(client)
    stranger = await sign_in_device(client, secret="s" * 43)
    for _ in range(3):
        await create(client, owner, due_date=str(today))
    cursor = (await page(client, owner, limit=1))["next_cursor"]
    for tokens, params in (
        (owner, {"cursor": "invalid!"}),
        (owner, {"cursor": cursor, "priority": "high"}),
        (stranger, {"cursor": cursor}),
    ):
        response = await client.get("/tasks/page", headers=bearer(tokens), params=params)
        assert response.status_code == 422
    assert (await page(client, stranger))["items"] == []


async def test_insert_before_cursor_does_not_repeat_previous_page(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    for index in range(6):
        await create(client, tokens, position=index)
    first = await page(client, tokens, limit=3, sort="position")
    new = await create(client, tokens, position=-1)
    second = await page(client, tokens, limit=3, sort="position", cursor=first["next_cursor"])
    assert len(second["items"]) == 3
    assert {item["id"] for item in first["items"]}.isdisjoint(
        item["id"] for item in second["items"]
    )
    assert new["id"] not in {item["id"] for item in second["items"]}


async def test_search_escapes_wildcards_and_excludes_deleted(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    wanted = await create(client, tokens, title="План 100%_готов")
    await create(client, tokens, title="План 100XXXготов")
    deleted = await create(client, tokens, title="План 100%_готов")
    await client.delete(f"/tasks/{deleted['id']}", headers=bearer(tokens))
    assert [item["id"] for item in (await page(client, tokens, q="100%_"))["items"]] == [
        wanted["id"]
    ]


async def test_scopes_and_columns_are_independent(client: AsyncClient, today: date) -> None:
    tokens = await sign_in_device(client, timezone="Asia/Almaty")
    overdue = await create(client, tokens, due_date=str(today - timedelta(days=2)))
    doing = await create(client, tokens, status="doing")
    future = await create(client, tokens, due_date=str(today + timedelta(days=1)), remind=True)
    await create(client, tokens, due_date=str(today + timedelta(days=30)))
    assert {item["id"] for item in (await page(client, tokens, view="today"))["items"]} == {
        overdue["id"],
        doing["id"],
    }
    assert {item["id"] for item in (await page(client, tokens, view="widgets"))["items"]} == {
        overdue["id"],
        doing["id"],
        future["id"],
    }
    assert [item["id"] for item in (await page(client, tokens, view="reminders"))["items"]] == [
        future["id"]
    ]
    assert [
        item["id"]
        for item in (await page(client, tokens, status="doing", sort="position"))["items"]
    ] == [doing["id"]]


@pytest.mark.parametrize(
    "params", [{"limit": 0}, {"limit": 101}, {"due": "invalid"}, {"goal_id": "x"}, {"q": "x" * 201}]
)
async def test_invalid_queries_are_rejected(client: AsyncClient, params: dict) -> None:
    tokens = await sign_in_device(client)
    response = await client.get("/tasks/page", headers=bearer(tokens), params=params)
    assert response.status_code == 422


async def test_sparse_today_query_uses_index(
    client: AsyncClient, sessionmaker, today: date
) -> None:
    tokens = await sign_in_device(client, timezone="Asia/Almaty")
    user_id = uuid.UUID((await client.get("/me", headers=bearer(tokens))).json()["id"])
    async with sessionmaker() as db:
        await db.execute(
            text("""
            INSERT INTO tasks (id, user_id, title, status, priority, due_date, position)
            SELECT md5(:uid || n::text)::uuid, CAST(:uid AS uuid), 'Future ' || n, 'todo', 'normal',
                   CAST(:future AS date), n FROM generate_series(1, 50000) n
        """),
            {"uid": str(user_id), "future": today + timedelta(days=30)},
        )
        await db.commit()
    for title in ("Today A", "Today B"):
        await create(client, tokens, title=title, due_date=str(today))
    result = await page(client, tokens, due="today")
    assert len(result["items"]) == 2
    assert result["next_cursor"] is None
    async with sessionmaker() as db:
        await db.execute(text("ANALYZE tasks"))
        user = await db.get(User, user_id)
        sql = str(
            task_statement(user, TaskQuery(due="today"), today).compile(
                dialect=db.bind.dialect, compile_kwargs={"literal_binds": True}
            )
        )
        plan = await db.scalar(text("EXPLAIN (ANALYZE, FORMAT JSON) " + sql))
        assert "ix_tasks_live_date" in json.dumps(plan)
        assert plan[0]["Plan"]["Actual Rows"] == 2


async def test_active_tasks_precede_completed_and_archive_is_excluded(
    client: AsyncClient, sessionmaker, today: date
) -> None:
    tokens = await sign_in_device(client)
    completed = await create(client, tokens, due_date=str(today - timedelta(days=1)), status="done")
    active = await create(client, tokens)
    archived = await create(client, tokens, status="done")
    async with sessionmaker() as db:
        await db.execute(
            text("UPDATE tasks SET completed_at=:at WHERE id=CAST(:id AS uuid)"),
            {"at": datetime(2020, 1, 1, tzinfo=UTC), "id": archived["id"]},
        )
        await db.commit()
    first = await page(client, tokens, limit=1)
    second = await page(client, tokens, limit=1, cursor=first["next_cursor"])
    assert [item["id"] for item in first["items"]] == [active["id"]]
    assert [item["id"] for item in second["items"]] == [completed["id"]]
    assert second["next_cursor"] is None


async def test_legacy_and_new_endpoints_are_always_bounded(
    client: AsyncClient, sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    user_id = (await client.get("/me", headers=bearer(tokens))).json()["id"]
    async with sessionmaker() as db:
        await db.execute(
            text("""
            INSERT INTO tasks (id,user_id,title,status,priority,position)
            SELECT gen_random_uuid(),CAST(:uid AS uuid),'Task '||n,'todo','normal',n
            FROM generate_series(1,125) n
        """),
            {"uid": user_id},
        )
        await db.commit()
    assert len((await client.get("/tasks", headers=bearer(tokens))).json()) == 50
    result = await page(client, tokens, limit=100)
    assert len(result["items"]) == 100 and result["next_cursor"] is not None


@pytest.mark.parametrize("position", ["NaN", "Infinity", "-Infinity"])
async def test_nonfinite_positions_are_rejected(client: AsyncClient, position: str) -> None:
    tokens = await sign_in_device(client)
    response = await client.post(
        "/tasks", headers=bearer(tokens), json={"title": "Task", "position": position}
    )
    assert response.status_code == 422
