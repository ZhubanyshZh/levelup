from fastapi import APIRouter
from pydantic import BaseModel
from sqlalchemy import text

from app import __version__
from app.api.deps import DB

router = APIRouter(tags=["health"])


class HealthOut(BaseModel):
    status: str
    database: str
    version: str


@router.get("/health")
async def health(db: DB) -> HealthOut:
    try:
        await db.execute(text("SELECT 1"))
        database = "ok"
    except Exception:
        database = "unavailable"
    return HealthOut(
        status="ok" if database == "ok" else "degraded", database=database, version=__version__
    )
