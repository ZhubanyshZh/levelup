from fastapi import APIRouter

from app.api.deps import DB, CurrentUser
from app.api.routes.auth import user_out
from app.schemas.user import UserOut, UserUpdate

router = APIRouter(prefix="/me", tags=["me"])


@router.get("")
async def get_me(user: CurrentUser, db: DB) -> UserOut:
    return await user_out(db, user)


@router.patch("")
async def update_me(body: UserUpdate, user: CurrentUser, db: DB) -> UserOut:
    for field, value in body.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(user, field, value)
    await db.commit()
    return await user_out(db, user)
