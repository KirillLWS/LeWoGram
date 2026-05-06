"""Один глобальный чат type=support на сервер (partial unique index)."""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)


async def apply_support_chat_migrations(db_path: Path) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_chats_single_support
            ON chats (type)
            WHERE type = 'support'
            """,
        )
        await db.commit()
    logger.info("support_chat_migrations: применены")
