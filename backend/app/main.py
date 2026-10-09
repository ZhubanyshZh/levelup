from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import __version__
from app.api.routes import ai, auth, captures, daily, health, me, profile, tasks
from app.core.config import get_settings
from app.core.errors import AppError, app_error_handler
from app.db.session import get_engine


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    yield
    await get_engine().dispose()


def create_app() -> FastAPI:
    # На боевом сервере документацию API наружу не показываем.
    docs = get_settings().environment != "production"
    app = FastAPI(
        title="Level Up API",
        version=__version__,
        lifespan=lifespan,
        docs_url="/docs" if docs else None,
        redoc_url="/redoc" if docs else None,
        openapi_url="/openapi.json" if docs else None,
    )
    app.add_exception_handler(AppError, app_error_handler)
    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(me.router)
    app.include_router(ai.router)
    app.include_router(profile.router)
    app.include_router(tasks.router)
    app.include_router(captures.router)
    app.include_router(daily.journal)
    app.include_router(daily.shopping)
    app.include_router(daily.progress)
    return app


app = create_app()
