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
