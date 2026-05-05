"""
Идемпотентная миграция для лайв-геопозиций пользователя.
Поток точек копится в live_geo_positions, читается owner-инструментами в реальном времени.
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)


async def apply_live_geo_migrations(db_path: Path) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE TABLE IF NOT EXISTS live_geo_positions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
                lat REAL NOT NULL,
                lng REAL NOT NULL,
                accuracy_m REAL,
                recorded_at TEXT NOT NULL DEFAULT (datetime('now')),
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
            """,
        )
        await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_live_geo_user_recorded "
            "ON live_geo_positions (user_id, recorded_at DESC)",
        )
        await db.commit()
    logger.debug("live_geo migrations applied")
