"""
Глобальный чат поддержки (type=support): один на сервер, все пользователи — участники.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

import aiosqlite

if TYPE_CHECKING:
    from app.database.database import Database

logger = logging.getLogger(__name__)

_SUPPORT_TITLE = "Поддержка LeWoGram"


async def get_support_chat_id(db: Database) -> int | None:
    async with aiosqlite.connect(db.db_path) as conn:
        async with conn.execute(
            "SELECT id FROM chats WHERE type = 'support' ORDER BY id ASC LIMIT 1",
        ) as cur:
            row = await cur.fetchone()
    return int(row[0]) if row else None


async def ensure_support_chat_exists(db: Database, actor_user_id: int) -> int:
    """Атомарно создаёт единственный support-чат при отсутствии."""
    async with aiosqlite.connect(db.db_path) as conn:
        await conn.execute("BEGIN IMMEDIATE")
        try:
            async with conn.execute(
                "SELECT id FROM chats WHERE type = 'support' ORDER BY id ASC LIMIT 1",
            ) as cur:
                row = await cur.fetchone()
            if row:
                cid = int(row[0])
                await conn.commit()
                return cid
            cur = await conn.execute(
                """
                INSERT INTO chats (type, title, created_by)
                VALUES ('support', ?, ?)
                """,
                (_SUPPORT_TITLE, actor_user_id),
            )
            chat_id = int(cur.lastrowid)
            await conn.execute(
                """
                INSERT INTO chat_members (chat_id, user_id, role, can_write)
                VALUES (?, ?, 'member', 1)
                """,
                (chat_id, actor_user_id),
            )
            await conn.execute(
                """
                UPDATE chats SET members_count = 1, updated_at = datetime('now')
                WHERE id = ?
                """,
                (chat_id,),
            )
            await conn.commit()
            logger.info("support chat created id=%s", chat_id)
            return chat_id
        except Exception:
            await conn.rollback()
            raise


async def ensure_user_in_support_chat(db: Database, user_id: int) -> int:
    chat_id = await ensure_support_chat_exists(db, user_id)
    added = await db.add_chat_member_if_absent(chat_id, user_id, "member", 1)
    if added:
        logger.debug("user %s added to support chat %s", user_id, chat_id)
    return chat_id
