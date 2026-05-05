"""
Миграции для push-уведомлений (FCM): таблица токенов устройств.
Идемпотентно, без удаления существующих данных.
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)

# SQL храним в константе — отдельный «фрагмент» схемы, как у других модулей.
_PUSH_SCHEMA = """
CREATE TABLE IF NOT EXISTS user_push_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id
ON user_push_tokens(user_id);
"""


async def apply_push_migrations(db_path: Path) -> None:
    """Создаёт user_push_tokens и индекс, если ещё нет."""
    async with aiosqlite.connect(db_path) as db:
        await db.executescript(_PUSH_SCHEMA)
        await db.commit()
    logger.info("push_migrations: user_push_tokens применена")
