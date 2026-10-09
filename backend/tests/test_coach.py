import uuid
from datetime import UTC, date, datetime

import pytest
from httpx import AsyncClient
from openai.lib._pydantic import to_strict_json_schema

from app.schemas.coach import CoachDraft, DraftAction, QuestionPlan
from app.services import coach, xp
from app.services.ai import context
from tests.conftest import bearer, configure_ai, sign_in_device
from tests.fakes import FakeAI, parsed


@pytest.fixture(autouse=True)
def fixed_day(monkeypatch):
    now = datetime(2026, 10, 12, 6, 0, tzinfo=UTC)
    for module in (coach, xp, context):
        monkeypatch.setattr(module, "utcnow", lambda: now)


def draft(*actions: DraftAction) -> CoachDraft:
    return CoachDraft(
        title="План дня",
        message="Начни с одного важного дела.",
        highlights=["Выспаться"],
        reflection_question="Что сегодня помогло тебе?",
        actions=list(actions),
    )


def action(**extra) -> DraftAction:
    return DraftAction(
        title="Прочитать главу",
        notes=None,
        due_date="2026-10-12",
        due_time="10:00",
        duration_minutes=30,
        difficulty=2,
        sphere="mind",
        task_id=None,
        **extra,
    )


def question(**extra) -> QuestionPlan:
    data = dict(
        metric="expense",
        start_date="2026-10-01",
        end_date="2026-10-12",
        category="cafe",
        currency=None,
        search=None,
        explanation="Траты на кафе за октябрь.",
    )
    return QuestionPlan(**(data | extra))


async def generate(client, tokens, kind="morning", **body):
    return await client.post(f"/coach/reports/{kind}", headers=bearer(tokens), json=body)


async def test_reports_need_ai_configuration(client: AsyncClient):
    tokens = await sign_in_device(client)
    response = await generate(client, tokens)
    assert response.status_code == 400
    assert response.json()["detail"] == "ai_not_configured"


async def test_daily_report_is_cached_and_has_personal_context(
    client: AsyncClient, fake_ai: FakeAI
):
    tokens = await sign_in_device(client, timezone="Asia/Almaty")
    await configure_ai(client, tokens)
    fact = await client.post(
        "/profile/facts",
        headers=bearer(tokens),
        json={"category": "preference", "text": "Сложные задачи до обеда"},
    )
    assert fact.status_code == 201
    fake_ai.result = draft(action())
    first, second = await generate(client, tokens), await generate(client, tokens)
    assert first.status_code == second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert len(fake_ai.calls) == 1
    assert "Asia/Almaty" in fake_ai.calls[0]["instructions"]
    assert "Сложные задачи до обеда" in fake_ai.calls[0]["instructions"]
    assert "Russian" in fake_ai.calls[0]["instructions"]


async def test_action_is_applied_once(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.result = draft(action())
    report = (await generate(client, tokens)).json()
    path = f"/coach/reports/{report['id']}/apply"
    body = {"action_id": report["actions"][0]["id"]}
    first = await client.post(path, headers=bearer(tokens), json=body)
    second = await client.post(path, headers=bearer(tokens), json=body)
    assert first.status_code == second.status_code == 200
    assert first.json()["task"]["id"] == second.json()["task"]["id"]
    assert len((await client.get("/tasks", headers=bearer(tokens))).json()) == 1


async def test_busy_interval_is_checked_beyond_start(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    await client.post(
        "/profile/facts",
        headers=bearer(tokens),
        json={
            "category": "schedule",
            "text": "Работа",
            "schedule": {"weekdays": ["MON"], "start": "10:15", "end": "11:00"},
        },
    )
    fake_ai.result = draft(action())
    report = (await generate(client, tokens)).json()
    assert report["actions"][0]["conflict"]["fact_text"] == "Работа"
    response = await client.post(
        f"/coach/reports/{report['id']}/apply",
        headers=bearer(tokens),
        json={"action_id": report["actions"][0]["id"]},
    )
    assert response.status_code == 409
    assert (await client.get("/tasks", headers=bearer(tokens))).json() == []


async def test_existing_task_is_rescheduled_without_duplicate(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    task = (
        await client.post(
            "/tasks",
            headers=bearer(tokens),
            json={"title": "Свой текст", "priority": "high", "notes": "Сохранить"},
        )
    ).json()
    suggestion = action()
    suggestion.task_id = task["id"]
    fake_ai.result = draft(suggestion)
    report = (await generate(client, tokens)).json()
    result = (
        await client.post(
            f"/coach/reports/{report['id']}/apply",
            headers=bearer(tokens),
            json={"action_id": report["actions"][0]["id"]},
        )
    ).json()["task"]
    assert (result["id"], result["title"], result["notes"], result["priority"]) == (
        task["id"],
        "Свой текст",
        "Сохранить",
        "high",
    )
    assert result["due_time"] == "10:00"


async def test_foreign_task_and_report_are_rejected(client: AsyncClient, fake_ai: FakeAI):
    first = await sign_in_device(client)
    other = await sign_in_device(client, secret="e" * 43)
    await configure_ai(client, first)
    suggestion = action()
    suggestion.task_id = str(uuid.uuid4())
    fake_ai.result = draft(suggestion)
    report = (await generate(client, first)).json()
    assert report["actions"] == []
    response = await client.post(
        f"/coach/reports/{report['id']}/apply",
        headers=bearer(other),
        json={"action_id": str(uuid.uuid4())},
    )
    assert response.status_code == 404


async def test_goal_breakdown_is_a_preview_until_accepted(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    goal = (
        await client.post("/goals", headers=bearer(tokens), json={"title": "Читать больше"})
    ).json()
    fake_ai.result = draft(action())
    report = (await generate(client, tokens, "goal", goal_id=goal["id"])).json()
    assert (await client.get("/goals", headers=bearer(tokens))).json()[0]["steps"] == []
    response = await client.post(
        f"/coach/reports/{report['id']}/apply",
        headers=bearer(tokens),
        json={"action_id": report["actions"][0]["id"]},
    )
    assert response.status_code == 200, response.text
    assert len(response.json()["goal"]["steps"]) == 1
    assert (await client.get("/progress", headers=bearer(tokens))).json()["total_xp"] == 0


async def test_evening_and_weekly_use_correct_periods(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.result = draft(action())
    evening = (await generate(client, tokens, "evening")).json()
    weekly = (await generate(client, tokens, "weekly")).json()
    assert evening["actions"] == []
    assert evening["reflection_question"]
    assert weekly["period_start"] == "2026-10-05"


async def test_money_answer_is_calculated_by_database(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    for amount, category, currency in (
        (1200, "cafe", "KZT"),
        (500, "cafe", "KZT"),
        (20, "cafe", "USD"),
        (2000, "transport", "KZT"),
    ):
        await client.post(
            "/finance/transactions",
            headers=bearer(tokens),
            json={
                "amount": amount,
                "category": category,
                "currency": currency,
                "occurred_on": "2026-10-10",
            },
        )
    fake_ai.result = question()
    response = await client.post(
        "/coach/questions", headers=bearer(tokens), json={"text": "Сколько я потратил на кафе?"}
    )
    assert response.status_code == 200, response.text
    assert response.json()["value"] == 1700
    assert response.json()["currency"] == "KZT"
    assert len(fake_ai.calls) == 1
    assert (await client.get("/captures", headers=bearer(tokens))).json() == []


async def test_question_failure_keeps_raw_input(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.error = "ai_unavailable"
    response = await client.post(
        "/coach/questions", headers=bearer(tokens), json={"text": "Мой вопрос", "source": "voice"}
    )
    assert response.status_code == 502, response.text
    inbox = (await client.get("/captures", headers=bearer(tokens))).json()
    assert inbox[0]["text"] == "Мой вопрос"
    assert inbox[0]["source"] == "voice"
    assert inbox[0]["error_code"] == "ai_unavailable"


async def test_question_from_inbox_is_resolved(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(parsed(type="question", title="Сколько тренировок?"))
    capture = (
        await client.post(
            "/captures",
            headers=bearer(tokens),
            json={"text": "Сколько тренировок?", "autosave": True},
        )
    ).json()["capture"]
    assert capture["status"] == "deferred"
    fake_ai.result = question(metric="workouts", category=None)
    response = await client.post(
        "/coach/questions",
        headers=bearer(tokens),
        json={"text": "Сколько тренировок?", "capture_id": capture["id"]},
    )
    assert response.status_code == 200, response.text
    assert (await client.get("/captures", headers=bearer(tokens))).json() == []


async def test_invalid_question_range_stays_in_inbox(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.result = question(start_date="2026-10-12", end_date="2026-10-01")
    response = await client.post("/coach/questions", headers=bearer(tokens), json={"text": "Траты"})
    assert response.status_code == 502
    assert (await client.get("/captures", headers=bearer(tokens))).json()[0]["text"] == "Траты"


def test_coach_schemas_are_strict():
    for model in (CoachDraft, QuestionPlan):
        schema = to_strict_json_schema(model)
        assert schema["additionalProperties"] is False
        assert set(schema["required"]) == set(schema["properties"])


def test_overnight_interval_checks_next_day():
    from app.models import ProfileFact

    fact = ProfileFact(
        id=uuid.uuid4(),
        category="schedule",
        text="Сон",
        is_active=True,
        data={"weekdays": ["TUE"], "start": "00:00", "end": "07:00", "busy": True},
    )
    assert (
        coach.interval_conflict(
            date(2026, 10, 12), datetime.min.time().replace(hour=23, minute=45), 30, [fact]
        )
        is not None
    )


async def test_parallel_generation_pays_once(client: AsyncClient, fake_ai: FakeAI):
    import asyncio

    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.result = draft(action())
    results = await asyncio.gather(generate(client, tokens), generate(client, tokens))
    assert all(r.status_code == 200 for r in results)
    assert results[0].json()["id"] == results[1].json()["id"]
    assert len(fake_ai.calls) == 1


async def test_changed_schedule_can_be_accepted_without_time(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.result = draft(action())
    report = (await generate(client, tokens)).json()
    await client.post(
        "/profile/facts",
        headers=bearer(tokens),
        json={
            "category": "schedule",
            "text": "Новая встреча",
            "schedule": {"weekdays": ["MON"], "start": "10:00", "end": "12:00"},
        },
    )
    path = f"/coach/reports/{report['id']}/apply"
    body = {"action_id": report["actions"][0]["id"]}
    assert (await client.post(path, headers=bearer(tokens), json=body)).status_code == 409
    response = await client.post(path, headers=bearer(tokens), json=body | {"unscheduled": True})
    assert response.status_code == 200, response.text
    assert response.json()["task"]["due_time"] is None
    assert response.json()["task"]["remind"] is False
    assert response.json()["report"]["actions"][0]["due_time"] is None


async def test_question_retry_is_cached_and_history_is_private(
    client: AsyncClient, fake_ai: FakeAI
):
    import asyncio

    tokens = await sign_in_device(client)
    other = await sign_in_device(client, secret="q" * 43)
    await configure_ai(client, tokens)
    fake_ai.result = question()
    body = {"text": "Траты", "request_id": str(uuid.uuid4())}
    results = await asyncio.gather(
        *[client.post("/coach/questions", headers=bearer(tokens), json=body) for _ in range(2)]
    )
    assert all(r.status_code == 200 for r in results), [r.text for r in results]
    assert results[0].json()["id"] == results[1].json()["id"]
    assert len(fake_ai.calls) == 1
    assert len((await client.get("/coach/questions", headers=bearer(tokens))).json()) == 1
    assert (await client.get("/coach/questions", headers=bearer(other))).json() == []
    forbidden = await client.post(
        "/coach/questions",
        headers=bearer(other),
        json={
            "text": "Траты",
            "capture_id": results[0].json()["capture_id"],
        },
    )
    assert forbidden.status_code == 404


async def test_answer_only_removes_selected_question(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.respond(
        parsed(type="question", title="Траты?"),
        parsed(type="question", title="Тренировки?"),
        parsed(type="note", title="Не потерять"),
    )
    capture = (
        await client.post(
            "/captures",
            headers=bearer(tokens),
            json={
                "text": "Траты? Тренировки? Не потерять",
                "autosave": True,
            },
        )
    ).json()["capture"]
    fake_ai.result = question()
    response = await client.post(
        "/coach/questions",
        headers=bearer(tokens),
        json={
            "text": "Траты?",
            "capture_id": capture["id"],
            "question_index": 0,
        },
    )
    assert response.status_code == 200, response.text
    inbox = (await client.get("/captures", headers=bearer(tokens))).json()
    assert inbox[0]["text"] == capture["text"]
    assert [i["include"] for i in inbox[0]["items"]] == [False, True, True]
    fake_ai.result = question(metric="workouts", category=None)
    response = await client.post(
        "/coach/questions",
        headers=bearer(tokens),
        json={
            "text": "Тренировки?",
            "capture_id": capture["id"],
            "question_index": 1,
        },
    )
    assert response.status_code == 200
    assert len((await client.get("/coach/questions", headers=bearer(tokens))).json()) == 2
    assert (await client.get("/captures", headers=bearer(tokens))).json()[0]["status"] == "deferred"


async def test_invalid_date_is_not_silently_changed(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.result = question(start_date="2026-99-01")
    response = await client.post("/coach/questions", headers=bearer(tokens), json={"text": "Траты"})
    assert response.status_code == 502
    assert (await client.get("/captures", headers=bearer(tokens))).json()[0]["status"] == "failed"


async def test_goal_plan_accounts_for_changed_steps(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    goal = (await client.post("/goals", headers=bearer(tokens), json={"title": "Читать"})).json()
    fake_ai.result = draft(action())
    first = (await generate(client, tokens, "goal", goal_id=goal["id"])).json()
    await client.post(
        f"/goals/{goal['id']}/steps", headers=bearer(tokens), json={"title": "Уже добавил"}
    )
    second = (await generate(client, tokens, "goal", goal_id=goal["id"])).json()
    assert first["id"] != second["id"]
    assert "Уже добавил" in fake_ai.calls[-1]["text"]


async def test_goal_step_added_after_preview_is_not_duplicated(
    client: AsyncClient, fake_ai: FakeAI
):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    goal = (await client.post("/goals", headers=bearer(tokens), json={"title": "Читать"})).json()
    fake_ai.result = draft(action())
    report = (await generate(client, tokens, "goal", goal_id=goal["id"])).json()
    await client.post(
        f"/goals/{goal['id']}/steps", headers=bearer(tokens), json={"title": "Прочитать главу"}
    )
    response = await client.post(
        f"/coach/reports/{report['id']}/apply",
        headers=bearer(tokens),
        json={"action_id": report["actions"][0]["id"]},
    )
    assert response.status_code == 200, response.text
    assert len(response.json()["goal"]["steps"]) == 1


async def test_task_time_added_after_preview_is_protected(client: AsyncClient, fake_ai: FakeAI):
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)
    fake_ai.result = draft(action())
    report = (await generate(client, tokens)).json()
    await client.post(
        "/tasks",
        headers=bearer(tokens),
        json={
            "title": "Встреча",
            "due_date": "2026-10-12",
            "due_time": "10:15",
        },
    )
    response = await client.post(
        f"/coach/reports/{report['id']}/apply",
        headers=bearer(tokens),
        json={"action_id": report["actions"][0]["id"]},
    )
    assert response.status_code == 409
    assert len((await client.get("/tasks", headers=bearer(tokens))).json()) == 1
