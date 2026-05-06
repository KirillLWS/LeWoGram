"""Операции с согласиями пользователя на расширенную диагностику."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import aiosqlite


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


async def grant_support_access(
    db_path: Path,
    *,
    user_id: int,
    granted_by_user_id: int,
    minutes: int,
) -> dict[str, Any]:
    ttl = max(5, min(minutes, 240))
    ttl_expr = f"+{ttl} minutes"
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        await db.execute("BEGIN IMMEDIATE")
        try:
            await db.execute(
                """
                UPDATE support_access_sessions
                SET revoked_at = datetime('now')
                WHERE user_id = ?
                  AND revoked_at IS NULL
                  AND expires_at > datetime('now')
                """,
                (user_id,),
            )
            cur = await db.execute(
                """
                INSERT INTO support_access_sessions (
                    user_id,
                    granted_by_user_id,
                    scope,
                    expires_at
                )
                VALUES (?, ?, 'diagnostics', datetime('now', ?))
                """,
                (user_id, granted_by_user_id, ttl_expr),
            )
            sid = int(cur.lastrowid)
            async with db.execute(
                """
                SELECT id, user_id, granted_by_user_id, scope, expires_at, revoked_at, created_at
                FROM support_access_sessions
                WHERE id = ?
                """,
                (sid,),
            ) as rcur:
                row = await rcur.fetchone()
            await db.commit()
        except Exception:
            await db.rollback()
            raise
    if row is None:
        raise RuntimeError("support_access_session insert failed")
    return _row_to_dict(row)


async def revoke_active_support_access(
    db_path: Path,
    *,
    user_id: int,
) -> int:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            UPDATE support_access_sessions
            SET revoked_at = datetime('now')
            WHERE user_id = ?
              AND revoked_at IS NULL
              AND expires_at > datetime('now')
            """,
            (user_id,),
        )
        await db.commit()
        return int(cur.rowcount or 0)


async def get_active_support_access(
    db_path: Path,
    *,
    user_id: int,
) -> dict[str, Any] | None:
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT id, user_id, granted_by_user_id, scope, expires_at, revoked_at, created_at
            FROM support_access_sessions
            WHERE user_id = ?
              AND revoked_at IS NULL
              AND expires_at > datetime('now')
            ORDER BY expires_at DESC, id DESC
            LIMIT 1
            """,
            (user_id,),
        ) as cur:
            row = await cur.fetchone()
    return _row_to_dict(row) if row else None


async def list_active_support_access_sessions(
    db_path: Path,
    *,
    limit: int = 50,
    offset: int = 0,
    user_id: int | None = None,
) -> list[dict[str, Any]]:
    lim = max(1, min(limit, 200))
    off = max(0, offset)
    where = "WHERE s.revoked_at IS NULL AND s.expires_at > datetime('now')"
    params: list[Any] = []
    if user_id is not None:
        where += " AND s.user_id = ?"
        params.append(int(user_id))
    params.extend([lim, off])
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            f"""
            SELECT
                s.id,
                s.user_id,
                s.granted_by_user_id,
                s.scope,
                s.created_at,
                s.expires_at,
                u.login AS user_login,
                u.username AS user_username,
                u.display_name AS user_display_name
            FROM support_access_sessions s
            JOIN users u ON u.id = s.user_id
            {where}
            ORDER BY s.expires_at DESC, s.id DESC
            LIMIT ? OFFSET ?
            """,
            params,
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]
