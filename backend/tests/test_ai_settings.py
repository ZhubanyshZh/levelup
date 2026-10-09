from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.core.crypto import DecryptionError, SecretBox
from app.models import AICredential
from tests.conftest import GEMINI_KEY, bearer, configure_ai, sign_in_device
from tests.fakes import FakeAI


def _provider(body: dict, name: str) -> dict:
    return next(p for p in body["providers"] if p["provider"] == name)


async def test_key_is_stored_encrypted_and_never_returned(
    client: AsyncClient, sessionmaker: async_sessionmaker
) -> None:
    tokens = await sign_in_device(client)

    response = await client.put(
        "/me/ai/gemini", headers=bearer(tokens), json={"api_key": GEMINI_KEY}
    )

    assert response.status_code == 200
    assert GEMINI_KEY not in response.text
    body = response.json()
    assert body["active_provider"] == "gemini"
    gemini = _provider(body, "gemini")
    assert gemini["has_key"] is True
    assert gemini["key_hint"] == "…kkkk"
    assert gemini["model"] == gemini["default_model"]
    async with sessionmaker() as db:
        row = await db.scalar(select(AICredential))
    assert row is not None
    assert row.encrypted_key.startswith("v1:")
    assert GEMINI_KEY not in row.encrypted_key


async def test_first_save_requires_key(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    response = await client.put("/me/ai/openai", headers=bearer(tokens), json={"model": "gpt-x"})

    assert response.status_code == 400
    assert response.json()["detail"] == "ai_key_required"


async def test_model_can_be_changed_without_resending_key(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)

    response = await client.put("/me/ai/gemini", headers=bearer(tokens), json={"model": "gemini-x"})

    gemini = _provider(response.json(), "gemini")
    assert gemini["model"] == "gemini-x"
    assert gemini["has_key"] is True


async def test_key_check_reports_provider_errors(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)

    fake_ai.error = "ai_invalid_key"
    failed = (await client.post("/me/ai/gemini/test", headers=bearer(tokens))).json()
    fake_ai.error = None
    fake_ai.models = ["something-else"]
    missing_model = (await client.post("/me/ai/gemini/test", headers=bearer(tokens))).json()

    assert failed == {"ok": False, "error_code": "ai_invalid_key", "model_available": None}
    assert missing_model == {"ok": True, "error_code": None, "model_available": False}


async def test_models_are_listed_with_the_stored_key(client: AsyncClient, fake_ai: FakeAI) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens)

    response = await client.get("/me/ai/gemini/models", headers=bearer(tokens))

    assert response.json() == fake_ai.models


async def test_deleting_active_provider_switches_to_another(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await configure_ai(client, tokens, "gemini")
    await configure_ai(client, tokens, "openai")

    response = await client.delete("/me/ai/gemini", headers=bearer(tokens))

    body = response.json()
    assert body["active_provider"] == "openai"
    assert _provider(body, "gemini")["has_key"] is False


async def test_active_provider_requires_key(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    response = await client.put(
        "/me/ai/active", headers=bearer(tokens), json={"provider": "openai"}
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "ai_not_configured"


def test_ciphertext_is_bound_to_its_owner() -> None:
    box = SecretBox("MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=")
    token = box.encrypt("secret", context="ai-key:user-a:gemini")

    assert box.decrypt(token, context="ai-key:user-a:gemini") == "secret"
    try:
        box.decrypt(token, context="ai-key:user-b:gemini")
    except DecryptionError:
        pass
    else:
        raise AssertionError("decrypted with a foreign context")
