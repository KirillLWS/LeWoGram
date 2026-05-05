"""Идемпотентное применение schema_device_transfer_fragment.sql."""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

logger = logging.getLogger(__name__)

_FRAGMENT_PATH = Path(__file__).resolve().parent / "schema_device_transfer_fragment.sql"


async def apply_device_transfer_migrations(db_path: Path) -> None:
    sql = _FRAGMENT_PATH.read_text(encoding="utf-8")
    async with aiosqlite.connect(db_path) as db:
        await db.execute("PRAGMA foreign_keys = ON")
        await db.executescript(sql)
        await db.commit()
    logger.info("device_transfer_migrations: device_transfer_requests (%s)", _FRAGMENT_PATH.name)
