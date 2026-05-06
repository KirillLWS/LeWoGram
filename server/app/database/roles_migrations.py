"""
Идемпотентное применение schema_roles_fragment.sql и бэкфилл роли user.
Вызывается из Database.init_db (координатор может вызывать отдельно).
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

from app.database.db_roles import highest_role_from_list

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


async def normalize_user_roles_to_single(db_path: Path) -> None:
    """
    Схлопывает несколько строк user_roles в одну (максимальная роль по иерархии).
    Идемпотентно: пользователи с одной ролью не меняются.
    """
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT user_id
            FROM user_roles
            GROUP BY user_id
            HAVING COUNT(*) > 1
            """,
        ) as cur:
            dup_ids = [int(r["user_id"]) for r in await cur.fetchall()]
        for uid in dup_ids:
            async with db.execute(
                "SELECT role FROM user_roles WHERE user_id = ?",
                (uid,),
            ) as cur2:
                roles = [str(x[0]) for x in await cur2.fetchall()]
            keep = highest_role_from_list(roles)
            await db.execute("DELETE FROM user_roles WHERE user_id = ?", (uid,))
            await db.execute(
                "INSERT INTO user_roles (user_id, role) VALUES (?, ?)",
                (uid, keep),
            )
        if dup_ids:
            await db.commit()
            logger.info("Normalized user_roles to single role for %d users", len(dup_ids))


async def apply_roles_migrations(db_path: Path) -> None:
    await apply_roles_schema(db_path)
    await backfill_default_user_roles(db_path)
    await normalize_user_roles_to_single(db_path)
    await ensure_one_role_row_per_user(db_path)


async def ensure_one_role_row_per_user(db_path: Path) -> None:
    """
    После нормализации — не более одной строки user_roles на user_id (UNIQUE INDEX).
    """
    await normalize_user_roles_to_single(db_path)
    await normalize_user_roles_to_single(db_path)
    try:
        async with aiosqlite.connect(db_path) as db:
            await db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS ux_user_roles_one_user ON user_roles(user_id)",
            )
            await db.commit()
    except aiosqlite.OperationalError as e:
        logger.warning(
            "CREATE UNIQUE INDEX ux_user_roles_one_user: %s — повторная нормализация",
            e,
        )
        await normalize_user_roles_to_single(db_path)
        async with aiosqlite.connect(db_path) as db:
            await db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS ux_user_roles_one_user ON user_roles(user_id)",
            )
            await db.commit()
