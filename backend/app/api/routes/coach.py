from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.deps import DB, AppSettings, CurrentUser
from app.schemas.coach import (
    AppliedActionOut,
    ApplyAction,
    CoachReportOut,
    QuestionAnswer,
    QuestionRequest,
    ReportKind,
    ReportRequest,
)
from app.services import coach, goals, tasks
from app.services.ai.providers import ProviderFactory, get_provider_factory

router = APIRouter(prefix="/coach", tags=["coach"])
Factory = Annotated[ProviderFactory, Depends(get_provider_factory)]


@router.get("/reports")
async def reports(user: CurrentUser, db: DB) -> list[CoachReportOut]:
    return await coach.list_reports(db, user)


@router.post("/reports/{kind}")
async def generate_report(
    kind: ReportKind,
    body: ReportRequest,
    user: CurrentUser,
    db: DB,
    settings: AppSettings,
    factory: Factory,
) -> CoachReportOut:
    report = await coach.generate(db, user, kind, body.goal_id, factory, settings)
    await db.commit()
    return coach.report_out(report)


@router.post("/reports/{report_id}/apply")
async def apply(report_id: UUID, body: ApplyAction, user: CurrentUser, db: DB) -> AppliedActionOut:
    report, task, goal = await coach.apply_action(
        db, user, report_id, body.action_id, body.unscheduled
    )
    await db.commit()
    return AppliedActionOut(
        report=coach.report_out(report),
        task=(await tasks.presenter(db, user))(task) if task else None,
        goal=goals.present(goal) if goal else None,
    )


@router.post("/questions")
async def question(
    body: QuestionRequest, user: CurrentUser, db: DB, settings: AppSettings, factory: Factory
) -> QuestionAnswer:
    return await coach.answer_question(db, user, body, factory, settings)


@router.get("/questions")
async def answers(user: CurrentUser, db: DB) -> list[QuestionAnswer]:
    return await coach.list_answers(db, user)
