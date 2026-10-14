import os

os.environ.setdefault("JWT_SECRET", "test-secret-test-secret-test-secret-123")
os.environ.setdefault("GOOGLE_CLIENT_IDS", "test-client.apps.googleusercontent.com")
os.environ.setdefault("ENCRYPTION_KEY", "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=")

from collections.abc import AsyncIterator  # noqa: E402

import asyncpg  # noqa: E402
import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import text  # noqa: E402
from sqlalchemy.engine import make_url  # noqa: E402
from sqlalchemy.ext.asyncio import (  # noqa: E402
    AsyncEngine,
    async_sessionmaker,
    create_async_engine,
)

from app.core.errors import AuthError  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import get_db  # noqa: E402
from app.main import create_app  # noqa: E402
from app.services.ai.providers import get_provider_factory  # noqa: E402
from app.services.google import GoogleProfile, get_google_verifier  # noqa: E402
from tests.fakes import FakeAI  # noqa: E402

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL", "postgresql+asyncpg://levelup:levelup@localhost:5433/levelup_test"
)

# Фейковый Google: токен вида "google:<sub>" считается валидным.
VALID_GOOGLE_PREFIX = "google:"


def fake_google_verifier(token: str) -> GoogleProfile:
    if not token.startswith(VALID_GOOGLE_PREFIX):
        raise AuthError("invalid_google_token")
    subject = token.removeprefix(VALID_GOOGLE_PREFIX)
    return GoogleProfile(
        subject=subject,
        email=f"{subject}@example.com",
        name="Test User",
        picture="https://example.com/avatar.png",
    )


async def _ensure_database() -> None:
    url = make_url(TEST_DATABASE_URL)
    conn = await asyncpg.connect(
        user=url.username, password=url.password, host=url.host, port=url.port, database="postgres"
    )
    try:
        exists = await conn.fetchval("SELECT 1 FROM pg_database WHERE datname = $1", url.database)
        if not exists:
            await conn.execute(f'CREATE DATABASE "{url.database}"')
    finally:
        await conn.close()


@pytest.fixture(scope="session")
async def engine() -> AsyncIterator[AsyncEngine]:
    await _ensure_database()
    eng = create_async_engine(TEST_DATABASE_URL)
    async with eng.begin() as conn:
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS pg_trgm"))
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield eng
    await eng.dispose()


@pytest.fixture(autouse=True)
async def _clean_tables(engine: AsyncEngine) -> AsyncIterator[None]:
    yield
    tables = ", ".join(t.name for t in Base.metadata.sorted_tables)
    async with engine.begin() as conn:
        await conn.execute(text(f"TRUNCATE {tables} CASCADE"))


@pytest.fixture
def sessionmaker(engine: AsyncEngine) -> async_sessionmaker:
    return async_sessionmaker(engine, expire_on_commit=False)


@pytest.fixture
def fake_ai() -> FakeAI:
    return FakeAI()


@pytest.fixture
async def client(sessionmaker: async_sessionmaker, fake_ai: FakeAI) -> AsyncIterator[AsyncClient]:
    app = create_app()

    async def override_get_db():
        async with sessionmaker() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_google_verifier] = lambda: fake_google_verifier
    app.dependency_overrides[get_provider_factory] = lambda: fake_ai.factory
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


DEVICE_SECRET = "d" * 43


async def sign_in_device(client: AsyncClient, secret: str = DEVICE_SECRET, **extra) -> dict:
    response = await client.post("/auth/device", json={"device_secret": secret, **extra})
    assert response.status_code == 200, response.text
    return response.json()


def bearer(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


GEMINI_KEY = "AIza" + "k" * 35


async def configure_ai(client: AsyncClient, tokens: dict, provider: str = "gemini") -> None:
    response = await client.put(
        f"/me/ai/{provider}", headers=bearer(tokens), json={"api_key": GEMINI_KEY}
    )
    assert response.status_code == 200, response.text
