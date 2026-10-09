from httpx import AsyncClient

from app.services.captures import normalize_item
from tests.conftest import GEMINI_KEY, bearer, configure_ai, sign_in_device
from tests.fakes import FakeAI, parsed
from tests.test_tasks_and_profile import JUMA


async def _capture(client: AsyncClient, tokens: dict, text: str = "текст", **extra) -> dict:
    response = await client.post(
        "/captures",
        headers=bearer(tokens),
        json={"text": text, "timezone": "Asia/Almaty", **extra},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def test_capture_without_ai_is_kept_in_inbox(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    result = await _capture(client, tokens, "Купить молоко")

    assert result["capture"]["status"] == "failed"
    assert result["capture"]["error_code"] == "ai_not_configured"
    inbox = (await client.get("/captures", headers=bearer(tokens))).json()
    assert [c["text"] for c in inbox] == ["Купить молоко"]


async def test_capture_is_parsed_with_user_context(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    await client.post("/profile/facts", headers=bearer(tokens), json=JUMA)
    # 2026-10-16 — пятница: 13:00 попадает на жума.
    fake_ai.respond(parsed(title="Созвон с командой", due_date="2026-10-16", due_time="13:00"))

    result = await _capture(client, tokens, "Созвон с командой в пятницу в 13")

    capture = result["capture"]
    assert capture["status"] == "parsed"
    assert capture["provider"] == "gemini"
    item = capture["items"][0]
    assert item["supported"] is True
    assert item["conflict"]["end"] == "14:00"
    call = fake_ai.calls[0]
    assert call["api_key"] == GEMINI_KEY
    assert "жума" in call["instructions"]
    assert "Upcoming dates:" in call["instructions"]
    assert call["text"] == "Созвон с командой в пятницу в 13"


async def test_confirm_creates_records_and_defers_unsupported(
    client: AsyncClient, fake_ai: FakeAI
) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(
        parsed(title="Позвонить в банк", due_date="2026-10-10", due_time="09:00", remind=True),
        parsed(
            "profile_fact",
            "По пятницам 12:30–14:00 жума",
            fact_category="schedule",
            schedule_weekdays=["FRI"],
            schedule_start="12:30",
            schedule_end="14:00",
            schedule_busy=True,
        ),
        parsed("expense", "Такси 3500"),
    )
    preview = (await _capture(client, tokens))["capture"]

    response = await client.post(
        f"/captures/{preview['id']}/confirm",
        headers=bearer(tokens),
        json={"items": preview["items"]},
    )

    result = response.json()
    assert len(result["tasks"]) == 1
    assert result["tasks"][0]["remind_at"] is not None
    assert result["facts"][0]["schedule"]["weekdays"] == ["FRI"]
    assert result["capture"]["status"] == "deferred"
    assert len(result["capture"]["created"]) == 2
    assert len((await client.get("/tasks", headers=bearer(tokens))).json()) == 1
    assert len((await client.get("/profile/facts", headers=bearer(tokens))).json()) == 1
    inbox = (await client.get("/captures", headers=bearer(tokens))).json()
    assert [c["status"] for c in inbox] == ["deferred"]


async def test_excluded_and_edited_items_are_respected(
    client: AsyncClient, fake_ai: FakeAI
) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(parsed(title="Черновик"), parsed(title="Лишнее"))
    preview = (await _capture(client, tokens))["capture"]
    first, second = preview["items"]

    result = (
        await client.post(
            f"/captures/{preview['id']}/confirm",
            headers=bearer(tokens),
            json={"items": [{**first, "title": "Исправлено"}, {**second, "include": False}]},
        )
    ).json()

    assert [t["title"] for t in result["tasks"]] == ["Исправлено"]
    assert result["capture"]["status"] == "confirmed"
    assert (await client.get("/captures", headers=bearer(tokens))).json() == []


async def test_autosave_confirms_immediately(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(parsed(title="Позвонить маме"))

    result = await _capture(client, tokens, source="siri", autosave=True)

    assert result["capture"]["status"] == "confirmed"
    assert [t["title"] for t in result["tasks"]] == ["Позвонить маме"]


async def test_undo_removes_created_records(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(parsed(title="Отменить меня"))
    capture = (await _capture(client, tokens, autosave=True))["capture"]

    response = await client.post(f"/captures/{capture['id']}/undo", headers=bearer(tokens))

    assert response.json()["status"] == "undone"
    assert (await client.get("/tasks", headers=bearer(tokens))).json() == []


async def test_retry_after_ai_is_configured(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    capture = (await _capture(client, tokens))["capture"]
    await configure_ai(client, tokens)
    fake_ai.respond(parsed(title="Теперь разобрано"))

    result = (await client.post(f"/captures/{capture['id']}/retry", headers=bearer(tokens))).json()

    assert result["capture"]["status"] == "parsed"
    assert result["capture"]["items"][0]["title"] == "Теперь разобрано"


async def test_ai_errors_keep_input_in_inbox(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.error = "ai_rate_limited"

    result = await _capture(client, tokens, "Не потеряй меня")

    assert result["capture"]["status"] == "failed"
    assert result["capture"]["error_code"] == "ai_rate_limited"


async def test_confirm_twice_is_rejected(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(parsed())
    capture = (await _capture(client, tokens, autosave=True))["capture"]

    response = await client.post(
        f"/captures/{capture['id']}/confirm",
        headers=bearer(tokens),
        json={"items": capture["items"]},
    )

    assert response.status_code == 409


async def test_captures_are_private(client: AsyncClient) -> None:
    owner = await sign_in_device(client)
    stranger = await sign_in_device(client, secret="s" * 43)
    capture = (await _capture(client, owner))["capture"]

    response = await client.get(f"/captures/{capture['id']}", headers=bearer(stranger))

    assert response.status_code == 404


def test_normalize_item_turns_garbage_into_nulls() -> None:
    item = normalize_item(
        parsed(
            title="  Сделать  ",
            due_date="завтра",
            due_time="25:99",
            difficulty=9,
            remind=True,
        )
    )

    assert item.title == "Сделать"
    assert item.due_date is None
    assert item.due_time is None
    assert item.difficulty == 5
    assert item.remind is True


def test_normalize_drops_broken_schedule_but_keeps_fact() -> None:
    item = normalize_item(
        parsed(
            "profile_fact",
            "Работаю по будням",
            schedule_weekdays=["MON"],
            schedule_start="09:00",
            schedule_end="09:00",
        )
    )

    assert item.schedule is None
    assert item.fact_category == "personal"
    assert item.remind is False


# --- Финансы, тренировки, цели (этап 4) ---


def _bench(**extra) -> dict:
    return {
        "name": "Жим лёжа",
        "sets": 3,
        "reps": 5,
        "weight_kg": 80,
        "duration_sec": None,
        "distance_m": None,
        **extra,
    }


async def test_money_workout_and_goal_are_saved(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(
        parsed("expense", "Такси", amount=3500, category="transport"),
        parsed("income", "Зарплата", amount=450000, category="salary"),
        parsed("workout", "Силовая", exercises=[_bench()]),
        parsed("goal", "Пробежать 10 км", target_value=10, metric_unit="км", sphere="body"),
    )

    result = await _capture(client, tokens, "...", autosave=True)

    assert result["capture"]["status"] == "confirmed"
    assert [(t["kind"], t["amount"], t["category"]) for t in result["transactions"]] == [
        ("expense", 3500.0, "transport"),
        ("income", 450000.0, "salary"),
    ]
    sets = result["workouts"][0]["sets"]
    assert [(s["exercise"], s["weight_kg"], s["reps"]) for s in sets] == [("Жим лёжа", 80, 5)] * 3
    assert result["xp_gained"] == 25
    goal = result["goals"][0]
    assert (goal["target_value"], goal["metric_unit"], goal["sphere"]) == (10, "км", "body")
    call = fake_ai.calls[0]
    assert "User's currency: KZT" in call["instructions"]
    assert "body (Тело)" in call["instructions"]


async def test_expense_without_amount_waits_in_inbox(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(parsed("expense", "Такси"))

    result = await _capture(client, tokens, "потратил на такси", autosave=True)

    assert result["capture"]["status"] == "deferred"
    assert result["transactions"] == []


async def test_undo_removes_money_and_workout_xp(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(
        parsed("expense", "Кофе", amount=1500, category="cafe"),
        parsed(
            "workout",
            "Бег",
            exercises=[_bench(name="Бег", reps=None, weight_kg=None, sets=1, distance_m=5000)],
        ),
    )
    capture = (await _capture(client, tokens, "...", autosave=True))["capture"]

    await client.post(f"/captures/{capture['id']}/undo", headers=bearer(tokens))

    summary = (await client.get("/finance/summary", headers=bearer(tokens))).json()
    workouts = (await client.get("/workouts", headers=bearer(tokens))).json()
    progress = (await client.get("/progress", headers=bearer(tokens))).json()
    assert summary["spent"] == 0
    assert workouts == []
    assert "workout" not in [e["source_type"] for e in progress["recent"]]


def test_normalize_money_and_exercises() -> None:
    item = normalize_item(
        parsed(
            "expense",
            "Кофе",
            amount=-5,
            currency="рубли",
            category="salary",
        )
    )
    assert (item.amount, item.currency, item.category) == (None, None, "other")

    workout = normalize_item(
        parsed(
            "workout",
            "Зал",
            exercises=[
                _bench(sets=0, weight_kg=5000),
                {**_bench(), "name": "  "},
            ],
        )
    )
    assert len(workout.exercises) == 1
    assert (workout.exercises[0].sets, workout.exercises[0].weight_kg) == (1, None)
