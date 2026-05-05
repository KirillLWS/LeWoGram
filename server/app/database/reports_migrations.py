"""
Идемпотентные миграции для модуля отчётов/модерации.
Вызывается из Database.init_db (после schema.sql) координатором.
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)

_FRAGMENT = Path(__file__).resolve().parent / "schema_reports_fragment.sql"


async def apply_reports_schema_fragment(db_path: Path) -> None:
    """CREATE TABLE IF NOT EXISTS для reports / history / sanctions + индексы."""
    if not _FRAGMENT.is_file():
        logger.warning("schema_reports_fragment.sql not found, skip")
        return
    sql = _FRAGMENT.read_text(encoding="utf-8")
    async with aiosqlite.connect(db_path) as db:
        await db.executescript(sql)
        await db.commit()
    logger.debug("reports schema fragment applied")


async def migrate_drop_legacy_system_role(db_path: Path) -> None:
    """
    Удаляет legacy-колонку users.system_role (идемпотентно).

    RBAC только через user_roles; колонка не читается кодом и не должна существовать,
    чтобы исключить будущие обращения как обход проверок.
    Требуется SQLite с поддержкой DROP COLUMN (≥ 3.35).
    """
    async with aiosqlite.connect(db_path) as db:
        async with db.execute("PRAGMA table_info(users)") as cur:
            cols = {str(row[1]) for row in await cur.fetchall()}
        if "system_role" not in cols:
            return
        try:
            await db.execute("ALTER TABLE users DROP COLUMN system_role")
            await db.commit()
            logger.info("migration: dropped users.system_role")
        except aiosqlite.OperationalError as exc:
            await db.rollback()
            logger.warning(
                "migration: DROP COLUMN system_role skipped (%s); обновите SQLite или пересоздайте БД",
                exc,
            )


async def apply_all_reports_migrations(db_path: Path) -> None:
    await apply_reports_schema_fragment(db_path)
    await migrate_drop_legacy_system_role(db_path)
