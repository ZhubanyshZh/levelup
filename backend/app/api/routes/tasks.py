import uuid

from fastapi import APIRouter, status

from app.api.deps import DB, CurrentUser
from app.core.time import utcnow
from app.schemas.task import TaskCreate, TaskOut, TaskUpdate
from app.services import tasks as task_service

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("")
async def list_tasks(user: CurrentUser, db: DB) -> list[TaskOut]:
    present = await task_service.presenter(db, user)
    return [present(task) for task in await task_service.list_tasks(db, user.id)]


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
