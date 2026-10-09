from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.errors import AuthError
from app.core.security import InvalidAccessToken, decode_access_token
from app.db.session import get_db
from app.models import User

DB = Annotated[AsyncSession, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]

_bearer = HTTPBearer(auto_error=False)


async def get_current_user(
    db: DB,
    settings: AppSettings,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    if credentials is None:
        raise AuthError("not_authenticated")
    try:
        user_id = decode_access_token(credentials.credentials, settings)
    except InvalidAccessToken as exc:
        raise AuthError("invalid_access_token") from exc

    user = await db.get(User, user_id)
    if user is None or user.deleted_at is not None:
        raise AuthError("invalid_access_token")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
