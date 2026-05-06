"""
Идемпотентная миграция для тикет-системы поддержки.
Добавляет колонки support_user_id и support_status в chats для тикет-чатов
(type='support_ticket'); индекс по support_user_id и support_status.
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)


async def apply_support_tickets_migrations(db_path: Path) -> None:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute("PRAGMA table_info(chats)") as cur:
            cols = {str(r[1]) for r in await cur.fetchall()}
        if "support_user_id" not in cols:
            await db.execute(
                "ALTER TABLE chats ADD COLUMN support_user_id INTEGER"
            )
        if "support_status" not in cols:
            await db.execute(
                "ALTER TABLE chats ADD COLUMN support_status TEXT"
            )
        if "support_subject" not in cols:
            await db.execute(
                "ALTER TABLE chats ADD COLUMN support_subject TEXT"
            )
        await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_chats_support_user "
            "ON chats (support_user_id) WHERE support_user_id IS NOT NULL"
        )
        await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_chats_support_status "
            "ON chats (support_status) WHERE support_status IS NOT NULL"
        )
        await db.commit()
    logger.debug("support_tickets migrations applied")
