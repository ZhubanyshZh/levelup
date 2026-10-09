from collections.abc import Callable
from dataclasses import dataclass

from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app.core.config import get_settings
from app.core.errors import AuthError


@dataclass(frozen=True)
class GoogleProfile:
    subject: str
    email: str | None
    name: str | None
    picture: str | None


GoogleVerifier = Callable[[str], GoogleProfile]

_transport = google_requests.Request()


def verify_google_id_token(token: str) -> GoogleProfile:
    """Проверяет подпись, срок, issuer и audience Google ID token. Блокирующий вызов."""
    client_ids = get_settings().google_client_ids
    if not client_ids:
        raise AuthError("google_not_configured", status_code=503)
    try:
        claims = google_id_token.verify_oauth2_token(token, _transport, audience=client_ids)
    except ValueError as exc:
        raise AuthError("invalid_google_token") from exc

    email = claims.get("email") if claims.get("email_verified") else None
    return GoogleProfile(
        subject=claims["sub"],
        email=email,
        name=claims.get("name"),
        picture=claims.get("picture"),
    )


def get_google_verifier() -> GoogleVerifier:
    return verify_google_id_token
