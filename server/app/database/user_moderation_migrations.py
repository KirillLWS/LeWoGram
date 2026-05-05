"""
Колонки модерации аккаунта: account_status, ban_until, ban_reason, staff_ban.
Идемпотентно; вызывается из Database.init_db.
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)


async def apply_user_moderation_migrations(db_path: Path) -> None:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute("PRAGMA table_info(users)") as cur:
            cols = {str(row[1]) for row in await cur.fetchall()}
        if "account_status" not in cols:
            await db.execute(
                """
                ALTER TABLE users ADD COLUMN account_status TEXT NOT NULL DEFAULT 'active'
                """,
            )
            logger.info("migration: added users.account_status")
        if "ban_until" not in cols:
            await db.execute("ALTER TABLE users ADD COLUMN ban_until TEXT")
            logger.info("migration: added users.ban_until")
        if "ban_reason" not in cols:
            await db.execute(
                """
                ALTER TABLE users ADD COLUMN ban_reason TEXT NOT NULL DEFAULT ''
                """,
            )
            logger.info("migration: added users.ban_reason")
        if "staff_ban" not in cols:
            await db.execute(
                "ALTER TABLE users ADD COLUMN staff_ban INTEGER NOT NULL DEFAULT 0",
            )
            logger.info("migration: added users.staff_ban")
        await db.commit()

    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            UPDATE users
            SET account_status = 'banned'
            WHERE is_blocked = 1
              AND (account_status IS NULL OR account_status = '' OR account_status = 'active')
            """,
        )
        await db.execute(
            """
            UPDATE users
            SET account_status = 'active', staff_ban = 0
            WHERE is_blocked = 0
              AND (account_status = 'banned' OR account_status IS NULL OR account_status = '')
            """,
        )
        await db.commit()

    logger.info("User moderation columns ready")
