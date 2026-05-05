"""
CRUD для live_geo_positions: запись точек пользователем и чтение последних точек владельцем.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import aiosqlite


def _db_path(db: Any) -> Path:
    return db.db_path


async def insert_live_geo(
    db: Any,
    *,
    user_id: int,
    lat: float,
    lng: float,
    accuracy_m: float | None,
    recorded_at: str | None = None,
) -> int:
    async with aiosqlite.connect(_db_path(db)) as dbw:
        cur = await dbw.execute(
            """
            INSERT INTO live_geo_positions (user_id, lat, lng, accuracy_m, recorded_at)
            VALUES (?, ?, ?, ?, COALESCE(?, datetime('now')))
            """,
            (user_id, lat, lng, accuracy_m, recorded_at),
        )
        await dbw.commit()
        return int(cur.lastrowid)


async def list_live_geo(
    db: Any,
    *,
    user_id: int,
    limit: int = 200,
    since: str | None = None,
) -> list[dict[str, Any]]:
    sql = (
        "SELECT id, user_id, lat, lng, accuracy_m, recorded_at, created_at "
        "FROM live_geo_positions WHERE user_id = ?"
    )
    params: list[Any] = [user_id]
    if since:
        sql += " AND recorded_at >= ?"
        params.append(since)
    sql += " ORDER BY recorded_at DESC, id DESC LIMIT ?"
    params.append(max(1, min(limit, 1000)))
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(sql, params) as cur:
            rows = await cur.fetchall()
    return [dict(r) for r in rows]


async def get_latest_live_geo(db: Any, *, user_id: int) -> dict[str, Any] | None:
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            "SELECT id, user_id, lat, lng, accuracy_m, recorded_at, created_at "
            "FROM live_geo_positions WHERE user_id = ? "
            "ORDER BY recorded_at DESC, id DESC LIMIT 1",
            (user_id,),
        ) as cur:
            row = await cur.fetchone()
    return dict(row) if row else None
