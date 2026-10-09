from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import update
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Budget
from tests.conftest import bearer, sign_in_device


def _today():
    return datetime.now(UTC).date()


async def _spend(client: AsyncClient, tokens: dict, amount: float, **extra) -> dict:
    response = await client.post(
        "/finance/transactions",
        headers=bearer(tokens),
        json={"amount": amount, "category": "cafe", **extra},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def test_transactions_and_monthly_summary(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _spend(client, tokens, 3500, category="transport", note="Такси")
    await _spend(client, tokens, 1200.5)
    await client.post(
        "/finance/transactions",
        headers=bearer(tokens),
        json={"kind": "income", "amount": 450000, "category": "salary"},
    )
    await _spend(client, tokens, 20, currency="USD")

    summary = (await client.get("/finance/summary", headers=bearer(tokens))).json()

    assert summary["currency"] == "KZT"
    assert summary["spent"] == 4700.5
    assert summary["income"] == 450000
    assert summary["spent_today"] == 4700.5
    assert [c["category"] for c in summary["expenses_by_category"]] == ["transport", "cafe"]
    assert summary["other_currencies"] == [{"currency": "USD", "spent": 20.0, "income": 0.0}]
    rows = (await client.get("/finance/transactions", headers=bearer(tokens))).json()
    assert len(rows) == 4
    assert {r["amount"] for r in rows} == {3500.0, 1200.5, 450000.0, 20.0}


async def test_income_category_is_kept_consistent(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    row = await _spend(client, tokens, 100, category="salary")

    assert row["kind"] == "expense"
    assert row["category"] == "other"


async def test_editing_transaction_keeps_category_consistent(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    row = await _spend(client, tokens, 100)

    income = await client.patch(
        f"/finance/transactions/{row['id']}", headers=bearer(tokens), json={"kind": "income"}
    )
    assert income.status_code == 200, income.text
    assert income.json()["category"] == "other_income"

    expense = await client.patch(
        f"/finance/transactions/{row['id']}",
        headers=bearer(tokens),
        json={"kind": "expense", "category": "salary"},
    )
    assert expense.status_code == 200, expense.text
    assert expense.json()["category"] == "other"


async def test_budget_in_old_currency_is_not_applied_to_new_currency(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await client.put("/finance/budgets", headers=bearer(tokens), json={"monthly_limit": 300000})
    changed = await client.patch("/me", headers=bearer(tokens), json={"currency": "USD"})
    assert changed.status_code == 200, changed.text
    await _spend(client, tokens, 20, currency="USD")

    summary = (await client.get("/finance/summary", headers=bearer(tokens))).json()

    assert summary["currency"] == "USD"
    assert summary["spent"] == 20
    assert summary["budgets"] == []
    assert summary["week_allowance"] is None


async def test_budget_remaining_and_week_allowance(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _spend(client, tokens, 10000, category="cafe")

    summary = (
        await client.put("/finance/budgets", headers=bearer(tokens), json={"monthly_limit": 300000})
    ).json()
    await client.put(
        "/finance/budgets",
        headers=bearer(tokens),
        json={"category": "cafe", "monthly_limit": 30000},
    )
    summary = (await client.get("/finance/summary", headers=bearer(tokens))).json()

    total, cafe = summary["budgets"]
    assert total["category"] is None and total["remaining"] == 290000
    assert cafe["category"] == "cafe" and cafe["remaining"] == 20000
    assert summary["week_allowance"] is not None


async def test_week_within_budget_gives_xp_once(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    today = _today()
    last_week = today - timedelta(days=today.weekday() + 7)
    await _spend(client, tokens, 1000, occurred_on=last_week.isoformat())
    await client.put("/finance/budgets", headers=bearer(tokens), json={"monthly_limit": 300000})
    # Бюджет задан «давно» — иначе прошлые недели не считаются.
    async with sessionmaker() as session:
        await session.execute(
            update(Budget).values(created_at=datetime.now(UTC) - timedelta(days=30))
        )
        await session.commit()

    first = (await client.get("/progress", headers=bearer(tokens))).json()
    second = (await client.get("/progress", headers=bearer(tokens))).json()

    budget_events = [e for e in second["recent"] if e["source_type"] == "budget"]
    assert len(budget_events) == 1
    assert budget_events[0]["amount"] == 50
    assert budget_events[0]["sphere"] == "finance"
    assert first["total_xp"] == second["total_xp"]


async def test_week_without_tracked_expenses_gives_no_budget_xp(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    await client.put("/finance/budgets", headers=bearer(tokens), json={"monthly_limit": 300000})
    async with sessionmaker() as session:
        await session.execute(
            update(Budget).values(created_at=datetime.now(UTC) - timedelta(days=30))
        )
        await session.commit()

    progress = (await client.get("/progress", headers=bearer(tokens))).json()

    assert not [e for e in progress["recent"] if e["source_type"] == "budget"]


async def test_deleted_transaction_leaves_summary(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    row = await _spend(client, tokens, 500)

    await client.delete(f"/finance/transactions/{row['id']}", headers=bearer(tokens))

    summary = (await client.get("/finance/summary", headers=bearer(tokens))).json()
    assert summary["spent"] == 0
