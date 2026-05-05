"""
Низкоуровневый доступ к таблице user_push_tokens (FCM device tokens).
"""

from __future__ import annotations

from pathlib import Path

import aiosqlite


async def save_push_token(db_path: Path, user_id: int, token: str) -> None:
    """Сохраняет токен; при дубликате (user_id, token) — INSERT OR IGNORE."""
    t = token.strip()
    if not t:
        return
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            INSERT OR IGNORE INTO user_push_tokens (user_id, token)
            VALUES (?, ?)
            """,
            (user_id, t),
        )
        await db.commit()


async def get_user_push_tokens(db_path: Path, user_id: int) -> list[str]:
    """Все FCM-токены пользователя (несколько устройств)."""
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            """
            SELECT token FROM user_push_tokens
            WHERE user_id = ?
            """,
            (user_id,),
        ) as cur:
            rows = await cur.fetchall()
    return [str(r[0]) for r in rows]


async def remove_push_token(db_path: Path, token: str) -> None:
    """Удаляет токен (например после INVALID_ARGUMENT / UNREGISTERED от FCM)."""
    t = token.strip()
    if not t:
        return
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            "DELETE FROM user_push_tokens WHERE token = ?",
            (t,),
        )
        await db.commit()
