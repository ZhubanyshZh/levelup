import uuid
from datetime import UTC, date, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Capture
from app.services.recurrence import next_after, normalize, occurrences
from app.services.xp import level_for
from tests.conftest import bearer, configure_ai, sign_in_device
from tests.fakes import FakeAI, parsed
from tests.test_tasks_and_profile import JUMA


def _today() -> date:
    return datetime.now(UTC).date()


def _next_weekday(weekday: int, after: date | None = None) -> date:
    day = (after or _today()) + timedelta(days=1)
    while day.weekday() != weekday:
        day += timedelta(days=1)
    return day


async def _progress(client: AsyncClient, tokens: dict) -> dict:
    """Прогресс без наград за квесты: здесь проверяется опыт за сами действия,
    квесты — в test_game.py."""
    progress = (await client.get("/progress", headers=bearer(tokens))).json()
    quest_xp = sum(q["reward"] for q in progress["quests"] if q["completed_at"])
    progress["total_xp"] -= quest_xp
    progress["today_xp"] -= quest_xp
    progress["recent"] = [e for e in progress["recent"] if e["source_type"] != "quest"]
    return progress


async def _confirm_all(client: AsyncClient, tokens: dict) -> dict:
    preview = (
        await client.post("/captures", headers=bearer(tokens), json={"text": "ввод"})
    ).json()["capture"]
    response = await client.post(
        f"/captures/{preview['id']}/confirm",
        headers=bearer(tokens),
        json={"items": preview["items"]},
    )
    assert response.status_code == 200, response.text
    return response.json()


# --- Покупки и дневник через ввод ---


async def test_shopping_capture_creates_separate_products(
    client: AsyncClient, fake_ai: FakeAI
) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(
        parsed(
            "shopping",
            "Молоко и хлеб",
            products=[{"name": "Молоко", "quantity": None}, {"name": "Хлеб", "quantity": "2"}],
            shopping_list="Дача",
        ),
        parsed("shopping", "Яйца, сыр"),  # ИИ не разделил — делим сами
    )

    result = await _confirm_all(client, tokens)

    names = [(i["name"], i["quantity"], i["list_name"]) for i in result["shopping"]]
    assert names == [
        ("Молоко", None, "Дача"),
        ("Хлеб", "2", "Дача"),
        ("Яйца", None, None),
        ("Сыр", None, None),
    ]
    assert result["capture"]["status"] == "confirmed"


async def test_journal_capture_gives_xp_once_per_day(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(
        parsed(
            "journal",
            "Тяжёлый день, но тренировка порадовала",
            details="День был тяжёлый, но тренировкой доволен",
            mood=3,
            energy=2,
            tags=["Работа", "спорт"],
        )
    )

    first = await _confirm_all(client, tokens)
    second = await _confirm_all(client, tokens)

    entry = first["journal"][0]
    assert entry["text"] == "День был тяжёлый, но тренировкой доволен"
    assert entry["summary"] == "Тяжёлый день, но тренировка порадовала"
    assert entry["mood"] == 3
    assert entry["tags"] == ["работа", "спорт"]
    assert first["xp_gained"] == 15
    assert second["xp_gained"] == 0
    assert (await _progress(client, tokens))["total_xp"] == 15


async def test_deferred_items_are_filed_when_their_section_appears(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    # Так выглядела запись этапа 1: покупки подтверждены, но раздела ещё не было.
    async with sessionmaker() as db:
        db.add(
            Capture(
                id=uuid.uuid4(),
                user_id=uuid.UUID(tokens["user"]["id"]),
                text="купить молоко и хлеб",
                source="voice",
                timezone="UTC",
                status="deferred",
                items=[
                    {
                        "type": "shopping",
                        "title": "Молоко, хлеб",
                        "include": True,
                        "supported": False,
                    },
                    {"type": "expense", "title": "Такси", "include": True, "supported": False},
                ],
                created_refs=[],
            )
        )
        await db.commit()

    inbox = (await client.get("/captures", headers=bearer(tokens))).json()
    shopping = (await client.get("/shopping", headers=bearer(tokens))).json()

    assert sorted(i["name"] for i in shopping) == ["Молоко", "Хлеб"]
    # Трата без суммы ждёт во «Входящих»: сохранить её нечем.
    assert inbox[0]["status"] == "deferred"
    assert len(inbox[0]["created"]) == 2


# --- Повторы, опыт, напоминания ---


async def test_recurring_task_moves_to_next_time_and_gives_xp(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    monday = _next_weekday(0)
    task = (
        await client.post(
            "/tasks",
            headers=bearer(tokens),
            json={
                "title": "Планёрка",
                "due_date": monday.isoformat(),
                "due_time": "09:00",
                "remind": True,
                "difficulty": 2,
                "recurrence": {"freq": "weekly"},
            },
        )
    ).json()
    assert task["recurrence"]["weekdays"] == ["MON"]

    done = (
        await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})
    ).json()

    assert done["status"] == "todo"
    assert done["due_date"] == (monday + timedelta(days=7)).isoformat()
    assert (await _progress(client, tokens))["total_xp"] == 10


async def test_recurrence_without_date_starts_from_first_matching_day(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    task = (
        await client.post(
            "/tasks",
            headers=bearer(tokens),
            json={"title": "Отчёт", "recurrence": {"freq": "weekly", "weekdays": ["FRI"]}},
        )
    ).json()

    due = date.fromisoformat(task["due_date"])
    assert due.weekday() == 4
    assert due >= _today()


async def test_uncompleting_task_takes_xp_back(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    task = (
        await client.post(
            "/tasks", headers=bearer(tokens), json={"title": "Отчёт", "difficulty": 5}
        )
    ).json()

    await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})
    assert (await _progress(client, tokens))["total_xp"] == 30
    await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "todo"})

    progress = await _progress(client, tokens)
    assert progress["total_xp"] == 0
    assert progress["level"] == 1


async def test_small_tasks_have_a_daily_xp_cap(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    for index in range(12):
        task = (
            await client.post(
                "/tasks", headers=bearer(tokens), json={"title": f"Мелочь {index}", "difficulty": 1}
            )
        ).json()
        await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})

    assert (await _progress(client, tokens))["total_xp"] == 50


async def test_reminder_moves_out_of_busy_time_except_important(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await client.post("/profile/facts", headers=bearer(tokens), json=JUMA)
    friday = _next_weekday(4)
    body = {"due_date": friday.isoformat(), "due_time": "13:00", "remind": True}

    normal = (
        await client.post("/tasks", headers=bearer(tokens), json={"title": "Созвон", **body})
    ).json()
    urgent = (
        await client.post(
            "/tasks", headers=bearer(tokens), json={"title": "Срочно", "priority": "high", **body}
        )
    ).json()

    assert normal["reminders"] == [f"{friday.isoformat()}T14:00:00Z"]
    assert urgent["reminders"] == [f"{friday.isoformat()}T13:00:00Z"]


async def test_daily_task_has_reminders_for_the_week_ahead(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    start = _today() + timedelta(days=1)

    task = (
        await client.post(
            "/tasks",
            headers=bearer(tokens),
            json={
                "title": "Таблетка",
                "due_date": start.isoformat(),
                "due_time": "08:00",
                "remind": True,
                "recurrence": {"freq": "daily"},
            },
        )
    ).json()

    assert len(task["reminders"]) == 7
    assert task["remind_at"] == task["reminders"][0]


def test_level_curve() -> None:
    assert level_for(0) == (1, 0, 100)
    assert level_for(99) == (1, 99, 100)
    assert level_for(100) == (2, 0, 283)
    assert level_for(383) == (3, 0, 520)


def test_monthly_recurrence_clamps_to_short_months() -> None:
    rule = normalize({"freq": "monthly"}, date(2026, 1, 31))

    assert next_after(rule, date(2026, 1, 31)) == date(2026, 2, 28)
    assert occurrences(rule, date(2026, 3, 1), date(2026, 4, 30)) == [
        date(2026, 3, 31),
        date(2026, 4, 30),
    ]


# --- Дневник и покупки вручную ---


async def test_deleting_last_journal_entry_of_day_takes_xp_back(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    first = (await client.post("/journal", headers=bearer(tokens), json={"text": "Утро"})).json()
    second = (await client.post("/journal", headers=bearer(tokens), json={"text": "Вечер"})).json()
    assert (await _progress(client, tokens))["total_xp"] == 15

    await client.delete(f"/journal/{first['id']}", headers=bearer(tokens))
    assert (await _progress(client, tokens))["total_xp"] == 15
    await client.delete(f"/journal/{second['id']}", headers=bearer(tokens))
    assert (await _progress(client, tokens))["total_xp"] == 0


async def test_old_journal_entries_do_not_give_xp(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    old = (_today() - timedelta(days=10)).isoformat()

    entry = (
        await client.post(
            "/journal", headers=bearer(tokens), json={"text": "Вспомнил", "entry_date": old}
        )
    ).json()

    assert entry["entry_date"] == old
    assert (await _progress(client, tokens))["total_xp"] == 0


async def test_moving_journal_entry_moves_its_xp(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    entry = (await client.post("/journal", headers=bearer(tokens), json={"text": "День"})).json()
    assert (await _progress(client, tokens))["total_xp"] == 15

    old = (_today() - timedelta(days=10)).isoformat()
    await client.patch(f"/journal/{entry['id']}", headers=bearer(tokens), json={"entry_date": old})
    assert (await _progress(client, tokens))["total_xp"] == 0

    today = _today().isoformat()
    await client.patch(
        f"/journal/{entry['id']}", headers=bearer(tokens), json={"entry_date": today}
    )
    assert (await _progress(client, tokens))["total_xp"] == 15


async def test_shopping_list_lifecycle(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    milk = (await client.post("/shopping", headers=bearer(tokens), json={"name": "Молоко"})).json()
    await client.post("/shopping", headers=bearer(tokens), json={"name": "Хлеб", "quantity": "2"})

    bought = (
        await client.patch(
            f"/shopping/{milk['id']}", headers=bearer(tokens), json={"is_bought": True}
        )
    ).json()
    assert bought["bought_at"] is not None

    await client.post("/shopping/clear-bought", headers=bearer(tokens))
    remaining = (await client.get("/shopping", headers=bearer(tokens))).json()
    assert [(i["name"], i["quantity"]) for i in remaining] == [("Хлеб", "2")]


async def test_progress_lists_recent_xp(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    task = (await client.post("/tasks", headers=bearer(tokens), json={"title": "Отчёт"})).json()
    await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})

    progress = await _progress(client, tokens)

    assert progress["today_xp"] == 10
    assert progress["recent"][0]["title"] == "Отчёт"
    assert progress["xp_for_next_level"] == 100
