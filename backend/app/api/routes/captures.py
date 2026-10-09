import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.api.deps import DB, AppSettings, CurrentUser
from app.core.time import utcnow
from app.models import Capture, User
from app.schemas.capture import (
    CaptureConfirm,
    CaptureCreate,
    CaptureItem,
    CaptureOut,
    CaptureResult,
)
from app.schemas.daily import JournalOut, ShoppingOut
from app.schemas.finance import TransactionOut
from app.schemas.profile import ProfileFactOut
from app.schemas.workouts import WorkoutOut
from app.services import captures as capture_service
from app.services import goals as goal_service
from app.services import tasks as task_service
from app.services.ai.providers import ProviderFactory, get_provider_factory
from app.services.captures import CreatedRecords

router = APIRouter(prefix="/captures", tags=["captures"])

Factory = Annotated[ProviderFactory, Depends(get_provider_factory)]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_capture(
    body: CaptureCreate, user: CurrentUser, db: DB, settings: AppSettings, factory: Factory
) -> CaptureResult:
    """Сохраняет ввод и сразу разбирает его. Ответ — всегда 201: даже если ИИ не справился,
    ввод лежит во «Входящих», а причина — в error_code."""
    capture = Capture(
        id=uuid.uuid4(),
        user_id=user.id,
        text=body.text,
        source=body.source,
        timezone=body.timezone or user.timezone,
        status="failed",
        items=[],
        created_refs=[],
    )
    db.add(capture)
    # Сначала фиксируем сырой ввод: если дальше что-то упадёт, он не потеряется.
    await db.commit()

    await capture_service.parse_capture(db, capture, user, factory, settings)
    created = CreatedRecords()
    if body.autosave and capture.status == "parsed":
        items = [CaptureItem.model_validate(item) for item in capture.items]
        created = await capture_service.confirm_capture(db, user, capture, items)
    await db.commit()
    return await _result(db, user, capture, created)


@router.get("")
async def inbox(user: CurrentUser, db: DB) -> list[CaptureOut]:
    """«Входящие»: не разобранное, не подтверждённое и ждущее своих разделов."""
    await capture_service.resolve_deferred(db, user)
    await db.commit()
    return [CaptureOut.model_validate(c) for c in await capture_service.list_inbox(db, user.id)]


@router.get("/{capture_id}")
async def get_capture(capture_id: uuid.UUID, user: CurrentUser, db: DB) -> CaptureOut:
    return CaptureOut.model_validate(await capture_service.get_capture(db, user.id, capture_id))


@router.post("/{capture_id}/confirm")
async def confirm_capture(
    capture_id: uuid.UUID, body: CaptureConfirm, user: CurrentUser, db: DB
) -> CaptureResult:
    capture = await capture_service.get_capture(db, user.id, capture_id)
    created = await capture_service.confirm_capture(db, user, capture, body.items)
    await db.commit()
    return await _result(db, user, capture, created)


@router.post("/{capture_id}/retry")
async def retry_capture(
    capture_id: uuid.UUID, user: CurrentUser, db: DB, settings: AppSettings, factory: Factory
) -> CaptureResult:
    capture = await capture_service.get_capture(db, user.id, capture_id)
    if capture.status in ("failed", "parsed"):
        await capture_service.parse_capture(db, capture, user, factory, settings)
        await db.commit()
    return await _result(db, user, capture, CreatedRecords())


@router.post("/{capture_id}/undo")
async def undo_capture(capture_id: uuid.UUID, user: CurrentUser, db: DB) -> CaptureOut:
    capture = await capture_service.get_capture(db, user.id, capture_id)
    await capture_service.undo_capture(db, user, capture)
    await db.commit()
    return CaptureOut.model_validate(capture)


@router.delete("/{capture_id}", status_code=status.HTTP_204_NO_CONTENT)
async def dismiss_capture(capture_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    """Убрать из «Входящих». Уже созданные из ввода записи остаются."""
    capture = await capture_service.get_capture(db, user.id, capture_id)
    capture.deleted_at = utcnow()
    await db.commit()


async def _result(db: DB, user: User, capture: Capture, created: CreatedRecords) -> CaptureResult:
    present = await task_service.presenter(db, user)
    return CaptureResult(
        capture=CaptureOut.model_validate(capture),
        tasks=[present(t) for t in created.tasks],
        facts=[ProfileFactOut.model_validate(f) for f in created.facts],
        journal=[JournalOut.model_validate(e) for e in created.journal],
        shopping=[ShoppingOut.model_validate(i) for i in created.shopping],
        transactions=[TransactionOut.model_validate(t) for t in created.transactions],
        workouts=[WorkoutOut.model_validate(w) for w in created.workouts],
        goals=[goal_service.present(g) for g in created.goals],
        xp_gained=created.xp_gained,
    )
