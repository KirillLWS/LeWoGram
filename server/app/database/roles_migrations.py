"""
Идемпотентное применение schema_roles_fragment.sql и бэкфилл роли user.
Вызывается из Database.init_db (координатор может вызывать отдельно).
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)

_FRAGMENT_PATH = Path(__file__).resolve().parent / "schema_roles_fragment.sql"


async def apply_roles_schema(db_path: Path) -> None:
    """CREATE TABLE IF NOT EXISTS из фрагмента; без DROP."""
    sql = _FRAGMENT_PATH.read_text(encoding="utf-8")
    async with aiosqlite.connect(db_path) as db:
        await db.executescript(sql)
        await db.commit()
    logger.info("Roles schema fragment applied: %s", _FRAGMENT_PATH.name)


async def backfill_default_user_roles(db_path: Path) -> None:
    """
    Всем пользователям без строк в user_roles добавляет роль user.
    Идемпотентно (INSERT OR IGNORE + NOT EXISTS).
    """
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            INSERT OR IGNORE INTO user_roles (user_id, role)
            SELECT u.id, 'user'
            FROM users u
            WHERE NOT EXISTS (
                SELECT 1 FROM user_roles r WHERE r.user_id = u.id
            )
            """,
        )
        await db.commit()


async def apply_roles_migrations(db_path: Path) -> None:
    await apply_roles_schema(db_path)
    await backfill_default_user_roles(db_path)
