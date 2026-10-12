import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import get_settings
from app.db.session import get_db
from app.main import create_app


async def test_health_reports_database(client: AsyncClient) -> None:
    response = await client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"


async def test_ping_does_not_touch_database() -> None:
    app = create_app()

    async def broken_db():
        raise AssertionError("ping не должен ходить в базу")
        yield

    app.dependency_overrides[get_db] = broken_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/ping")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_docs_hidden_in_production(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ENVIRONMENT", "production")
    get_settings.cache_clear()
    try:
        app = create_app()
    finally:
        monkeypatch.delenv("ENVIRONMENT")
        get_settings.cache_clear()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        for path in ("/docs", "/openapi.json"):
            assert (await client.get(path)).status_code == 404
