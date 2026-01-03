from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    12-factor に沿って環境変数を単一箇所へ集約する。

    - ローカルでは `.env` を自動読込（docker-compose の env_file と整合）
    - 本番(Cloud Run想定)では環境変数注入のみで動く想定
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    APP_NAME: str = "gcp_cloudsql"
    ENV: Literal["local", "prod"] = "local"
    LOG_LEVEL: str = "INFO"
    PORT: int = 8000

    DATABASE_URL: str

    DB_ECHO: bool = False
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 10
    DB_POOL_TIMEOUT: int = 30
    DB_POOL_RECYCLE: int = 1800


@lru_cache
def get_settings() -> Settings:
    return Settings()


def get_database_url(*, required: bool = False) -> str | None:
    """
    互換関数（STEP2で導入済み想定）。

    - FastAPI(API)側: async URL (postgresql+asyncpg://...) を想定
    - Alembic 側: env.py 内で sync URL へ変換して利用する
    """

    url = get_settings().DATABASE_URL
    if required and not url:
        raise RuntimeError("DATABASE_URL is required but not set")
    return url


