from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool
from sqlalchemy.engine import URL
from sqlalchemy.engine.url import make_url

from app.db.base import Base
from app.settings import get_database_url

# Alembic Config object
config = context.config

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Import models so metadata is populated
from app.db import models as _models  # noqa: F401  (import side-effects)

target_metadata = Base.metadata


def _to_sync_url(async_database_url: str) -> str:
    url: URL = make_url(async_database_url)
    if url.drivername == "postgresql+asyncpg":
        url = url.set(drivername="postgresql+psycopg")
    return url.render_as_string(hide_password=False)


def get_url() -> str:
    async_url = get_database_url(required=True)
    return _to_sync_url(async_url)


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = get_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    configuration = config.get_section(config.config_ini_section) or {}
    configuration["sqlalchemy.url"] = get_url()

    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()


