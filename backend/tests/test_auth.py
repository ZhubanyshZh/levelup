import uuid
from datetime import timedelta

from httpx import AsyncClient
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.core.config import get_settings
from app.core.security import create_access_token, hash_secret
from app.core.time import utcnow
from app.models import RefreshToken
from tests.conftest import bearer, sign_in_device


async def test_device_sign_in_creates_user_once(client: AsyncClient) -> None:
    first = await sign_in_device(client, locale="en-US", timezone="Asia/Almaty")
    second = await sign_in_device(client)

    assert first["is_new_user"] is True
    assert second["is_new_user"] is False
    assert first["user"]["id"] == second["user"]["id"]
    assert first["user"]["locale"] == "en"
    assert first["user"]["timezone"] == "Asia/Almaty"
    assert first["user"]["auth_providers"] == ["device"]


async def test_device_sign_in_rejects_short_secret(client: AsyncClient) -> None:
    response = await client.post("/auth/device", json={"device_secret": "short"})

    assert response.status_code == 422


async def test_google_sign_in_fills_profile(client: AsyncClient) -> None:
    response = await client.post("/auth/google", json={"id_token": "google:sub-123" + "x" * 20})

    assert response.status_code == 200
    user = response.json()["user"]
    assert user["display_name"] == "Test User"
    assert user["email"].endswith("@example.com")
    assert user["auth_providers"] == ["google"]


async def test_google_sign_in_rejects_invalid_token(client: AsyncClient) -> None:
    response = await client.post("/auth/google", json={"id_token": "not-a-google-token-at-all"})

    assert response.status_code == 401
    assert response.json()["detail"] == "invalid_google_token"


async def test_me_requires_token(client: AsyncClient) -> None:
    response = await client.get("/me")

    assert response.status_code == 401
    assert response.json()["detail"] == "not_authenticated"


async def test_me_rejects_expired_access_token(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    settings = get_settings().model_copy(update={"access_token_ttl_minutes": -1})
    expired, _ = create_access_token(uuid.UUID(tokens["user"]["id"]), settings)

    response = await client.get("/me", headers={"Authorization": f"Bearer {expired}"})

    assert response.status_code == 401
    assert response.json()["detail"] == "invalid_access_token"


async def test_me_returns_and_updates_profile(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    response = await client.patch(
        "/me",
        headers=bearer(tokens),
        json={"display_name": "Жұбаныш", "timezone": "Asia/Almaty", "currency": "KZT"},
    )
    assert response.status_code == 200

    me = (await client.get("/me", headers=bearer(tokens))).json()
    assert me["display_name"] == "Жұбаныш"
    assert me["timezone"] == "Asia/Almaty"
    assert me["currency"] == "KZT"


async def test_me_rejects_unknown_timezone(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    response = await client.patch("/me", headers=bearer(tokens), json={"timezone": "Mars/Base"})

    assert response.status_code == 422


async def test_refresh_rotates_tokens(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    response = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})

    assert response.status_code == 200
    rotated = response.json()
    assert rotated["refresh_token"] != tokens["refresh_token"]
    assert (await client.get("/me", headers=bearer(rotated))).status_code == 200


async def test_refresh_retry_within_leeway_keeps_session(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    first = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})

    # Ответ на первый обмен «потерялся», клиент повторяет запрос со старым токеном.
    retry = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert retry.status_code == 200
    assert (await client.get("/me", headers=bearer(retry.json()))).status_code == 200

    # Токен из потерянного ответа отозван: если он всплывёт — это утечка.
    lost = await client.post("/auth/refresh", json={"refresh_token": first.json()["refresh_token"]})
    assert lost.status_code == 401
    assert lost.json()["detail"] == "refresh_token_reused"


async def test_refresh_reuse_after_leeway_revokes_family(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    rotated = (
        await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    ).json()
    async with sessionmaker() as db:
        await db.execute(
            update(RefreshToken)
            .where(RefreshToken.token_hash == hash_secret(tokens["refresh_token"]))
            .values(revoked_at=utcnow() - timedelta(minutes=5))
        )
        await db.commit()

    reuse = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert reuse.status_code == 401
    assert reuse.json()["detail"] == "refresh_token_reused"

    # Вся семья отозвана — даже последний выданный токен.
    after = await client.post("/auth/refresh", json={"refresh_token": rotated["refresh_token"]})
    assert after.status_code == 401


async def test_refresh_rejects_expired_token(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    async with sessionmaker() as db:
        await db.execute(update(RefreshToken).values(expires_at=utcnow() - timedelta(seconds=1)))
        await db.commit()

    response = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})

    assert response.status_code == 401
    assert response.json()["detail"] == "refresh_token_expired"


async def test_refresh_extends_session(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)
    rotated = (
        await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    ).json()

    async with sessionmaker() as db:
        token = await db.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash == hash_secret(rotated["refresh_token"])
            )
        )
    assert token is not None
    days_left = (token.expires_at - utcnow()).days
    assert days_left >= get_settings().refresh_token_ttl_days - 1


async def test_logout_revokes_session(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    logout = await client.post("/auth/logout", json={"refresh_token": tokens["refresh_token"]})
    assert logout.status_code == 204

    response = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert response.status_code == 401


async def test_guest_can_link_google_and_keep_account(client: AsyncClient) -> None:
    guest = await sign_in_device(client)

    linked = await client.post(
        "/auth/link/google", headers=bearer(guest), json={"id_token": "google:linked" + "x" * 20}
    )
    assert linked.status_code == 200
    assert linked.json()["auth_providers"] == ["device", "google"]
    assert linked.json()["display_name"] == "Test User"

    # Вход через Google теперь ведёт в тот же аккаунт.
    google = await client.post("/auth/google", json={"id_token": "google:linked" + "x" * 20})
    assert google.json()["user"]["id"] == guest["user"]["id"]


async def test_google_account_of_another_user_cannot_be_linked(client: AsyncClient) -> None:
    await client.post("/auth/google", json={"id_token": "google:taken" + "x" * 20})
    guest = await sign_in_device(client)

    response = await client.post(
        "/auth/link/google", headers=bearer(guest), json={"id_token": "google:taken" + "x" * 20}
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "identity_in_use"
