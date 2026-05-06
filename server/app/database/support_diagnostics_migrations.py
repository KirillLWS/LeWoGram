"""Таблица диагностических логов пользователя (для поддержки)."""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)


async def apply_support_diagnostics_migrations(db_path: Path) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE TABLE IF NOT EXISTS support_diagnostic_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
                body TEXT NOT NULL,
                client_meta TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """,
        )
        await db.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_support_diag_user_created
            ON support_diagnostic_logs (user_id, created_at DESC)
            """,
        )
        await db.commit()
    logger.info("support_diagnostics_migrations: применены")
