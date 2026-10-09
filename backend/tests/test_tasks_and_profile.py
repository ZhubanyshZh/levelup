from httpx import AsyncClient

from tests.conftest import bearer, sign_in_device

JUMA = {
    "category": "schedule",
    "text": "Каждую пятницу 12:30–14:00 — жума",
    "schedule": {"weekdays": ["FRI"], "start": "12:30", "end": "14:00", "busy": True},
}


async def test_profile_fact_lifecycle(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    created = await client.post("/profile/facts", headers=bearer(tokens), json=JUMA)
    assert created.status_code == 201
    fact = created.json()
    assert fact["schedule"]["weekdays"] == ["FRI"]

    patched = await client.patch(
        f"/profile/facts/{fact['id']}", headers=bearer(tokens), json={"is_active": False}
    )
    assert patched.json()["is_active"] is False

    deleted = await client.delete(f"/profile/facts/{fact['id']}", headers=bearer(tokens))
    assert deleted.status_code == 204
    assert (await client.get("/profile/facts", headers=bearer(tokens))).json() == []


async def test_schedule_must_have_distinct_bounds(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    bad = {**JUMA, "schedule": {**JUMA["schedule"], "end": "12:30"}}

    response = await client.post("/profile/facts", headers=bearer(tokens), json=bad)

    assert response.status_code == 422


async def test_reminder_is_computed_in_user_timezone(client: AsyncClient) -> None:
    tokens = await sign_in_device(client, timezone="Asia/Almaty")

    with_time = await client.post(
        "/tasks",
        headers=bearer(tokens),
        json={
            "title": "Позвонить в банк",
            "due_date": "2026-10-10",
            "due_time": "09:30",
            "remind": True,
        },
    )
    without_time = await client.post(
        "/tasks",
        headers=bearer(tokens),
        json={"title": "Оплатить интернет", "due_date": "2026-10-10", "remind": True},
    )

    assert with_time.json()["due_time"] == "09:30"
    assert with_time.json()["remind_at"].startswith("2026-10-10T04:30:00")
    assert without_time.json()["remind_at"].startswith("2026-10-10T04:00:00")


async def test_task_status_and_due_updates(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    task = (
        await client.post(
            "/tasks",
            headers=bearer(tokens),
            json={"title": "Отчёт", "due_date": "2026-10-10", "remind": True},
        )
    ).json()

    done = (
        await client.patch(f"/tasks/{task['id']}", headers=bearer(tokens), json={"status": "done"})
    ).json()
    assert done["completed_at"] is not None

    reopened = (
        await client.patch(
            f"/tasks/{task['id']}",
            headers=bearer(tokens),
            json={"status": "doing", "due_date": None},
        )
    ).json()
    assert reopened["completed_at"] is None
    assert reopened["due_date"] is None
    assert reopened["remind_at"] is None


async def test_tasks_are_private(client: AsyncClient) -> None:
    owner = await sign_in_device(client)
    stranger = await sign_in_device(client, secret="s" * 43)
    task = (await client.post("/tasks", headers=bearer(owner), json={"title": "Моё"})).json()

    response = await client.patch(
        f"/tasks/{task['id']}", headers=bearer(stranger), json={"title": "Чужое"}
    )

    assert response.status_code == 404
    assert (await client.get("/tasks", headers=bearer(stranger))).json() == []


async def test_deleted_task_disappears(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    task = (await client.post("/tasks", headers=bearer(tokens), json={"title": "Удалить"})).json()

    await client.delete(f"/tasks/{task['id']}", headers=bearer(tokens))

    assert (await client.get("/tasks", headers=bearer(tokens))).json() == []
