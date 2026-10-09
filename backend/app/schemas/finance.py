import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

# Ключи категорий. Названия и значки — в приложении (на языке интерфейса).
EXPENSE_CATEGORIES = (
    "groceries",
    "cafe",
    "transport",
    "home",
    "bills",
    "health",
    "clothes",
    "fun",
    "education",
    "sport",
    "gifts",
    "travel",
    "pets",
    "other",
)
INCOME_CATEGORIES = ("salary", "freelance", "gift", "refund", "other_income")

TransactionKind = Literal["expense", "income"]
Category = Literal[
    "groceries",
    "cafe",
    "transport",
    "home",
    "bills",
    "health",
    "clothes",
    "fun",
    "education",
    "sport",
    "gifts",
    "travel",
    "pets",
    "other",
    "salary",
    "freelance",
    "gift",
    "refund",
    "other_income",
]
CURRENCY_PATTERN = r"^[A-Z]{3}$"
DEFAULT_CURRENCY = "KZT"


class TransactionIn(BaseModel):
    kind: TransactionKind = "expense"
    amount: float = Field(gt=0, le=1_000_000_000_000)
    # По умолчанию — валюта пользователя.
    currency: str | None = Field(default=None, pattern=CURRENCY_PATTERN)
    category: Category = "other"
    note: str | None = Field(default=None, max_length=300)
    # По умолчанию — сегодня в часовом поясе пользователя.
    occurred_on: date | None = None


class TransactionUpdate(BaseModel):
    kind: TransactionKind | None = None
    amount: float | None = Field(default=None, gt=0, le=1_000_000_000_000)
    currency: str | None = Field(default=None, pattern=CURRENCY_PATTERN)
    category: Category | None = None
    note: str | None = Field(default=None, max_length=300)
    occurred_on: date | None = None


class TransactionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: TransactionKind
    amount: float
    currency: str
    category: str
    note: str | None
    occurred_on: date
    capture_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime


class BudgetIn(BaseModel):
    # null — общий лимит на месяц.
    category: Category | None = None
    monthly_limit: float = Field(gt=0, le=1_000_000_000_000)


class BudgetOut(BaseModel):
    category: str | None
    monthly_limit: float
    currency: str
    spent: float
    remaining: float


class CategoryTotal(BaseModel):
    category: str
    amount: float


class DayTotal(BaseModel):
    date: date
    spent: float
    income: float


class CurrencyTotal(BaseModel):
    currency: str
    spent: float
    income: float


class FinanceSummary(BaseModel):
    month: str
    currency: str
    spent: float
    income: float
    spent_today: float
    spent_week: float
    # Сколько можно тратить в неделю, чтобы уложиться в общий бюджет (null — бюджета нет).
    week_allowance: float | None
    expenses_by_category: list[CategoryTotal]
    income_by_category: list[CategoryTotal]
    by_day: list[DayTotal]
    budgets: list[BudgetOut]
    # Операции в других валютах — отдельно, без пересчёта.
    other_currencies: list[CurrencyTotal]
