import hashlib
import secrets
import uuid
from datetime import datetime, timedelta

import jwt

from app.core.config import Settings
from app.core.time import utcnow


class InvalidAccessToken(Exception):
    pass


def create_access_token(user_id: uuid.UUID, settings: Settings) -> tuple[str, datetime]:
    now = utcnow()
    expires_at = now + timedelta(minutes=settings.access_token_ttl_minutes)
    payload = {
        "sub": str(user_id),
        "type": "access",
        "iss": settings.jwt_issuer,
        "iat": now,
        "exp": expires_at,
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires_at


def decode_access_token(token: str, settings: Settings) -> uuid.UUID:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
            options={"require": ["sub", "exp", "iss"]},
        )
        if payload.get("type") != "access":
            raise InvalidAccessToken("wrong token type")
        return uuid.UUID(payload["sub"])
    except (jwt.InvalidTokenError, ValueError) as exc:
        raise InvalidAccessToken(str(exc)) from exc


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_secret(value: str) -> str:
    """SHA-256 для случайных секретов (refresh-токены, секрет устройства).

    Медленный хэш (bcrypt) не нужен: значения случайные и длинные, перебор невозможен.
    """
    return hashlib.sha256(value.encode()).hexdigest()
