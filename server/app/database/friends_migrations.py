"""
Идемпотентное применение schema_friends_fragment.sql (таблица friendships).
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)

_FRAGMENT_PATH = Path(__file__).resolve().parent / "schema_friends_fragment.sql"


async def apply_friends_migrations(db_path: Path) -> None:
    """CREATE TABLE IF NOT EXISTS + индексы."""
    sql = _FRAGMENT_PATH.read_text(encoding="utf-8")
    async with aiosqlite.connect(db_path) as db:
        await db.execute("PRAGMA foreign_keys = ON")
        await db.executescript(sql)
        await db.commit()
    logger.info("friends_migrations: friendships применена (%s)", _FRAGMENT_PATH.name)
