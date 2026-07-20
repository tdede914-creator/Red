"""Async SQLAlchemy engine + session factory + init helper."""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from .config import settings
from .models import Base

log = logging.getLogger(__name__)

engine = create_async_engine(
    settings.database_url,
    echo=(settings.log_level == "DEBUG"),
    pool_pre_ping=True,
    future=True,
)

SessionLocal = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False, autoflush=False
)


async def init_db() -> None:
    """Create all tables. Idempotent — safe to call on every boot."""
    # Ensure data dir exists for SQLite
    settings.data_dir  # side-effect: mkdir

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    log.info("Database initialized: %s", settings.database_url.split("://")[0])


@asynccontextmanager
async def get_session() -> AsyncIterator[AsyncSession]:
    """Session context manager with automatic rollback on error."""
    async with SessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
