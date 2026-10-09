"""Финансы: доходы, расходы, бюджеты и опыт за неделю в рамках бюджета."""

import calendar
import uuid
from datetime import date, timedelta
from decimal import Decimal
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.time import utcnow
from app.models import Budget, Transaction, User
from app.schemas.finance import (
    DEFAULT_CURRENCY,
    BudgetOut,
    CategoryTotal,
    CurrencyTotal,
    DayTotal,
    FinanceSummary,
    TransactionIn,
)
from app.services import xp

# За сколько прошедших недель проверяем бюджет (опыт за давние недели не начисляем).
BUDGET_WEEKS_BACK = 4


def user_currency(user: User) -> str:
    return user.currency or DEFAULT_CURRENCY


def money(value: float) -> Decimal:
    return Decimal(str(round(value, 2)))


def month_range(month: date) -> tuple[date, date]:
    """Первый и последний день месяца."""
    first = month.replace(day=1)
    return first, first.replace(day=calendar.monthrange(first.year, first.month)[1])


def parse_month(value: str | None, user: User) -> date:
    if not value:
        return xp.local_today(user).replace(day=1)
    try:
        year, month = (int(part) for part in value.split("-")[:2])
        return date(year, month, 1)
    except ValueError as exc:
        raise AppError("bad_month", status_code=422) from exc


# --- Операции ---


def create_transaction(
    db: AsyncSession, user: User, data: TransactionIn, *, capture_id: uuid.UUID | None = None
) -> Transaction:
    category = data.category
    # Категория должна подходить к типу: доход не бывает «Продуктами».
    if data.kind == "income" and category not in _INCOME:
        category = "other_income"
    if data.kind == "expense" and category in _INCOME:
        category = "other"
    row = Transaction(
        id=uuid.uuid4(),
        user_id=user.id,
        kind=data.kind,
        amount=money(data.amount),
        currency=data.currency or user_currency(user),
        category=category,
        note=(data.note or "").strip() or None,
        occurred_on=data.occurred_on or xp.local_today(user),
        capture_id=capture_id,
    )
    db.add(row)
    return row


def update_transaction(row: Transaction, changes: dict[str, Any]) -> None:
    for field in ("kind", "currency", "category", "occurred_on"):
        if changes.get(field) is not None:
            setattr(row, field, changes[field])
    if changes.get("amount") is not None:
        row.amount = money(changes["amount"])
    if "note" in changes:
        row.note = (changes["note"] or "").strip() or None
    if row.kind == "income" and row.category not in _INCOME:
        row.category = "other_income"
    elif row.kind == "expense" and row.category in _INCOME:
        row.category = "other"


async def get_transaction(db: AsyncSession, user_id: uuid.UUID, row_id: uuid.UUID) -> Transaction:
    row = await db.get(Transaction, row_id)
    if row is None or row.user_id != user_id or row.deleted_at is not None:
        raise AppError("transaction_not_found", status_code=404)
    return row


async def list_transactions(db: AsyncSession, user: User, month: date) -> list[Transaction]:
    first, last = month_range(month)
    rows = await db.scalars(
        select(Transaction)
        .where(
            Transaction.user_id == user.id,
            Transaction.deleted_at.is_(None),
            Transaction.occurred_on.between(first, last),
        )
        .order_by(Transaction.occurred_on.desc(), Transaction.created_at.desc())
    )
    return list(rows)


def delete_transaction(row: Transaction) -> None:
    row.deleted_at = utcnow()


# --- Бюджеты ---


async def list_budgets(db: AsyncSession, user_id: uuid.UUID) -> list[Budget]:
    rows = await db.scalars(
        select(Budget).where(Budget.user_id == user_id).order_by(Budget.category.nulls_first())
    )
    return list(rows)


async def set_budget(db: AsyncSession, user: User, category: str | None, limit: float) -> Budget:
    budget = await db.scalar(
        select(Budget).where(Budget.user_id == user.id, _same_category(category))
    )
    if budget is None:
        budget = Budget(id=uuid.uuid4(), user_id=user.id, category=category)
        db.add(budget)
    budget.monthly_limit = money(limit)
    budget.currency = user_currency(user)
    return budget


async def delete_budget(db: AsyncSession, user: User, category: str | None) -> None:
    budget = await db.scalar(
        select(Budget).where(Budget.user_id == user.id, _same_category(category))
    )
    if budget is not None:
        await db.delete(budget)


def _same_category(category: str | None):
    return Budget.category.is_(None) if category is None else Budget.category == category


# --- Сводка ---


async def summary(db: AsyncSession, user: User, month: date) -> FinanceSummary:
    currency = user_currency(user)
    first, last = month_range(month)
    today = xp.local_today(user)
    week_start = today - timedelta(days=today.weekday())

    rows = (
        await db.execute(
            select(
                Transaction.currency,
                Transaction.kind,
                Transaction.category,
                Transaction.occurred_on,
                func.sum(Transaction.amount),
            )
            .where(
                Transaction.user_id == user.id,
                Transaction.deleted_at.is_(None),
                Transaction.occurred_on.between(first, last),
            )
            .group_by(
                Transaction.currency,
                Transaction.kind,
                Transaction.category,
                Transaction.occurred_on,
            )
        )
    ).all()

    expenses: dict[str, float] = {}
    incomes: dict[str, float] = {}
    days: dict[date, list[float]] = {}
    others: dict[str, list[float]] = {}
    for row_currency, kind, category, day, amount in rows:
        value = float(amount)
        if row_currency != currency:
            totals = others.setdefault(row_currency, [0.0, 0.0])
            totals[0 if kind == "expense" else 1] += value
            continue
        bucket = expenses if kind == "expense" else incomes
        bucket[category] = bucket.get(category, 0) + value
        day_totals = days.setdefault(day, [0.0, 0.0])
        day_totals[0 if kind == "expense" else 1] += value

    spent_week = await _spent_between(db, user, week_start, today)
    budgets = [budget for budget in await list_budgets(db, user.id) if budget.currency == currency]
    total_budget = _total_limit(budgets)
    return FinanceSummary(
        month=f"{first:%Y-%m}",
        currency=currency,
        spent=round(sum(expenses.values()), 2),
        income=round(sum(incomes.values()), 2),
        spent_today=round(days.get(today, [0.0])[0], 2) if first <= today <= last else 0,
        spent_week=spent_week,
        week_allowance=_week_allowance(total_budget, week_start),
        expenses_by_category=_sorted_totals(expenses),
        income_by_category=_sorted_totals(incomes),
        by_day=[
            DayTotal(date=day, spent=round(t[0], 2), income=round(t[1], 2))
            for day, t in sorted(days.items())
        ],
        budgets=[
            BudgetOut(
                category=budget.category,
                monthly_limit=float(budget.monthly_limit),
                currency=budget.currency,
                spent=round(
                    sum(expenses.values())
                    if budget.category is None
                    else expenses.get(budget.category, 0),
                    2,
                ),
                remaining=round(
                    float(budget.monthly_limit)
                    - (
                        sum(expenses.values())
                        if budget.category is None
                        else expenses.get(budget.category, 0)
                    ),
                    2,
                ),
            )
            for budget in budgets
        ],
        other_currencies=[
            CurrencyTotal(currency=code, spent=round(t[0], 2), income=round(t[1], 2))
            for code, t in sorted(others.items())
        ],
    )


async def settle_budget_weeks(db: AsyncSession, user: User) -> int:
    """+50 XP за каждую прошедшую неделю (пн–вс), когда траты уложились в бюджет.

    Нужны общий бюджет (или лимиты по категориям) и хотя бы одна записанная трата за неделю —
    без учёта трат опыт не начисляется. Начисление идемпотентно: ключ — номер недели.
    """
    budgets = [
        budget
        for budget in await list_budgets(db, user.id)
        if budget.currency == user_currency(user)
    ]
    total_limit = _total_limit(budgets)
    if total_limit is None:
        return 0
    since = min(budget.created_at for budget in budgets).astimezone(ZoneInfo(user.timezone))
    today = xp.local_today(user)
    this_week = today - timedelta(days=today.weekday())
    gained = 0
    for weeks_back in range(1, BUDGET_WEEKS_BACK + 1):
        start = this_week - timedelta(weeks=weeks_back)
        end = start + timedelta(days=6)
        if start < since.date():
            continue
        count, spent = await _week_expenses(db, user, start, end)
        allowance = _week_allowance(total_limit, start)
        if count and allowance is not None and spent <= allowance:
            year, week, _ = start.isocalendar()
            gained += await xp.award(
                db,
                user,
                "budget",
                f"budget:{year}-W{week:02d}",
                xp.BUDGET_WEEK_XP,
                f"{start:%d.%m}–{end:%d.%m}",
            )
    return gained


def _total_limit(budgets: list[Budget]) -> float | None:
    for budget in budgets:
        if budget.category is None:
            return float(budget.monthly_limit)
    if budgets:
        return float(sum(budget.monthly_limit for budget in budgets))
    return None


def _week_allowance(total_limit: float | None, week_start: date) -> float | None:
    if total_limit is None:
        return None
    days_in_month = calendar.monthrange(week_start.year, week_start.month)[1]
    return round(total_limit * 7 / days_in_month, 2)


async def _spent_between(db: AsyncSession, user: User, first: date, last: date) -> float:
    return (await _week_expenses(db, user, first, last))[1]


async def _week_expenses(
    db: AsyncSession, user: User, first: date, last: date
) -> tuple[int, float]:
    count, amount = (
        await db.execute(
            select(func.count(), func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user.id,
                Transaction.deleted_at.is_(None),
                Transaction.kind == "expense",
                Transaction.currency == user_currency(user),
                Transaction.occurred_on.between(first, last),
            )
        )
    ).one()
    return int(count), round(float(amount), 2)


def _sorted_totals(totals: dict[str, float]) -> list[CategoryTotal]:
    return [
        CategoryTotal(category=category, amount=round(amount, 2))
        for category, amount in sorted(totals.items(), key=lambda item: -item[1])
    ]


_INCOME = frozenset({"salary", "freelance", "gift", "refund", "other_income"})
