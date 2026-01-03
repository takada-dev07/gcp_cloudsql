from __future__ import annotations

import logging

from fastapi import FastAPI
from sqlalchemy import text

from app.api.todos import router as todos_router
from app.db.session import engine
from app.settings import get_settings

settings = get_settings()

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
)

app = FastAPI(title=settings.APP_NAME)


@app.get("/health")
async def health():
    db_status = "ok"
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception:
        db_status = "ng"
        logging.getLogger(__name__).exception("DB healthcheck failed")
    return {"status": "ok", "db": db_status, "env": settings.ENV}


app.include_router(todos_router)


