import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import DB, CurrentUser
from app.core.time import utcnow
from app.schemas.task import TaskCreate, TaskOut, TaskPage, TaskQuery, TaskUpdate
from app.services import tasks as task_service
from app.services.task_query import page_tasks

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", deprecated=True)
async def list_tasks(
    user: CurrentUser, db: DB, limit: int = Query(50, ge=1, le=100)
) -> list[TaskOut]:
    """Совместимость со старым клиентом: всегда ограниченная первая страница."""
    return (await page_tasks(db, user, TaskQuery(limit=limit))).items


@router.get("/page")
async def task_page(user: CurrentUser, db: DB, query: Annotated[TaskQuery, Query()]) -> TaskPage:
    return await page_tasks(db, user, query)


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_task(body: TaskCreate, user: CurrentUser, db: DB) -> TaskOut:
    await task_service.check_links(db, user, body.model_dump())
    task = task_service.create_task(db, user, body)
    await db.commit()
    return (await task_service.presenter(db, user))(task)


@router.patch("/{task_id}")
async def update_task(task_id: uuid.UUID, body: TaskUpdate, user: CurrentUser, db: DB) -> TaskOut:
    """Выполнение задачи начисляет опыт; повторяющаяся задача переезжает на следующий раз."""
    task = await task_service.get_task(db, user.id, task_id)
    changes = body.model_dump(exclude_unset=True)
    await task_service.check_links(db, user, changes)
    await task_service.update_task(db, user, task, changes)
    await db.commit()
    return (await task_service.presenter(db, user))(task)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(task_id: uuid.UUID, user: CurrentUser, db: DB) -> None:
    task = await task_service.get_task(db, user.id, task_id)
    task.deleted_at = utcnow()
    await db.commit()
