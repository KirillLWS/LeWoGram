"""Таблица временных согласий пользователя на расширенную диагностику поддержки."""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)


async def apply_support_access_migrations(db_path: Path) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE TABLE IF NOT EXISTS support_access_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
                granted_by_user_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
                scope TEXT NOT NULL DEFAULT 'diagnostics',
                expires_at TEXT NOT NULL,
                revoked_at TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """,
        )
        await db.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_support_access_user_active
            ON support_access_sessions (user_id, revoked_at, expires_at DESC)
            """,
        )
        await db.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_support_access_expires
            ON support_access_sessions (expires_at)
            """,
        )
        await db.commit()
    logger.info("support_access_migrations: применены")
