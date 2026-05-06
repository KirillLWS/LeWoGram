"""Запись и выборка диагностических логов поддержки."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import aiosqlite

from app.database.database import Database


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


async def insert_diagnostic_log(
    db: Database,
    *,
    user_id: int,
    body: str,
    client_meta: str | None,
) -> int:
    async with aiosqlite.connect(db.db_path) as dbw:
        cur = await dbw.execute(
            """
            INSERT INTO support_diagnostic_logs (user_id, body, client_meta)
            VALUES (?, ?, ?)
            """,
            (user_id, body.strip(), client_meta),
        )
        await dbw.commit()
        return int(cur.lastrowid)


async def list_diagnostic_logs(
    db_path: Path,
    *,
    limit: int = 50,
    offset: int = 0,
    user_id: int | None = None,
) -> list[dict[str, Any]]:
    lim = max(1, min(limit, 200))
    off = max(0, offset)
    uid = int(user_id) if user_id is not None else None
    where = "WHERE l.user_id = ?" if uid is not None else ""
    params: list[Any] = [uid] if uid is not None else []
    params.extend([lim, off])
    async with aiosqlite.connect(db_path) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            f"""
            SELECT l.*, u.login AS user_login, u.username AS user_username
            FROM support_diagnostic_logs l
            JOIN users u ON u.id = l.user_id
            {where}
            ORDER BY l.created_at DESC, l.id DESC
            LIMIT ? OFFSET ?
            """,
            params,
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]


async def list_login_logs(
    db_path: Path,
    *,
    limit: int = 50,
    offset: int = 0,
    user_id: int | None = None,
) -> list[dict[str, Any]]:
    lim = max(1, min(limit, 200))
    off = max(0, offset)
    uid = int(user_id) if user_id is not None else None
    where = "WHERE l.user_id = ?" if uid is not None else ""
    params: list[Any] = [uid] if uid is not None else []
    params.extend([lim, off])
    async with aiosqlite.connect(db_path) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            f"""
            SELECT
                l.id,
                l.user_id,
                l.device_fingerprint,
                l.ip_address,
                l.logged_in_at,
                l.success,
                u.login AS user_login,
                u.username AS user_username,
                u.display_name AS user_display_name,
                u.last_device_model,
                u.last_device_os
            FROM login_logs l
            LEFT JOIN users u ON u.id = l.user_id
            {where}
            ORDER BY l.logged_in_at DESC, l.id DESC
            LIMIT ? OFFSET ?
            """,
            params,
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]
