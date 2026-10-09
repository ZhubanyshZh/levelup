import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.schemas.capture import BusyConflict, CaptureSource
from app.schemas.finance import CURRENCY_PATTERN, Category
from app.schemas.goals import GoalOut
from app.schemas.task import TaskOut

ReportKind = Literal["morning", "evening", "weekly", "goal"]
Metric = Literal["expense", "income", "workouts", "journal_days", "tasks_done", "xp", "unsupported"]


class DraftAction(BaseModel):
    title: str
    notes: str | None
    due_date: str | None
    due_time: str | None
    duration_minutes: int
    difficulty: int
    sphere: str | None
    task_id: str | None = Field(description="Existing task UUID from the context, or null.")


class CoachDraft(BaseModel):
    title: str
    message: str
    highlights: list[str]
    reflection_question: str | None
    actions: list[DraftAction]


class CoachAction(BaseModel):
    id: uuid.UUID
    title: str
    notes: str | None = None
    due_date: date | None = None
    due_time: str | None = None
    duration_minutes: int
    difficulty: int
    sphere: str | None = None
    task_id: uuid.UUID | None = None
    conflict: BusyConflict | None = None
    applied_id: uuid.UUID | None = None


class CoachReportOut(BaseModel):
    id: uuid.UUID
    kind: ReportKind
    period_start: date
    goal_id: uuid.UUID | None
    title: str
    message: str
    highlights: list[str]
    reflection_question: str | None
    actions: list[CoachAction]
    created_at: datetime


class ReportRequest(BaseModel):
    goal_id: uuid.UUID | None = None


class ApplyAction(BaseModel):
    action_id: uuid.UUID
    unscheduled: bool = False


class AppliedActionOut(BaseModel):
    report: CoachReportOut
    task: TaskOut | None = None
    goal: GoalOut | None = None


class QuestionPlan(BaseModel):
    metric: Metric
    start_date: str | None
    end_date: str | None
    category: Category | None
    currency: str | None
    search: str | None = Field(description="Literal exercise/task words to filter, or null.")
    explanation: str = Field(description="A short explanation of the filter; NEVER invent a total.")


class QuestionRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    capture_id: uuid.UUID | None = None
    source: CaptureSource = "text"
    request_id: uuid.UUID | None = None
    question_index: int | None = Field(default=None, ge=0)

    @field_validator("text")
    @classmethod
    def not_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("empty question")
        return value


class QuestionAnswer(BaseModel):
    id: uuid.UUID
    capture_id: uuid.UUID
    question: str
    metric: Metric
    start_date: date
    end_date: date
    value: float | None
    currency: str | None = Field(default=None, pattern=CURRENCY_PATTERN)
    explanation: str
