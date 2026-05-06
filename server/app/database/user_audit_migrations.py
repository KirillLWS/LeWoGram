"""Append-only журнал событий для безопасности и поддержки (не слежка)."""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)


async def apply_user_audit_migrations(db_path: Path) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE TABLE IF NOT EXISTS user_audit_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
                actor_id INTEGER REFERENCES users (id) ON DELETE SET NULL,
                event_type TEXT NOT NULL,
                payload TEXT NOT NULL DEFAULT '{}',
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """,
        )
        await db.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_user_audit_user_created
            ON user_audit_events (user_id, created_at)
            """,
        )
        await db.commit()
    logger.info("user_audit_migrations: применены")
