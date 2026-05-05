"""
Операции с таблицей auth_sessions (refresh, revoke, список).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import aiosqlite


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


async def insert_session(
    db_path: Path,
    *,
    user_id: int,
    refresh_token_hash: str,
    device_fingerprint: str,
    device_model: str | None,
    device_os: str | None,
    ip_address: str | None,
    expires_at: str,
) -> int:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            INSERT INTO auth_sessions (
                user_id, refresh_token_hash, device_fingerprint,
                device_model, device_os, ip_address, expires_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                refresh_token_hash,
                device_fingerprint,
                device_model,
                device_os,
                ip_address,
                expires_at,
            ),
        )
        await db.commit()
        return int(cur.lastrowid)


async def rotate_refresh_session(
    db_path: Path,
    old_refresh_hash: str,
    *,
    new_refresh_hash: str,
    new_expires_at: str,
    client_ip: str | None,
) -> dict[str, Any] | None:
    """
    Транзакция: валидная активная сессия по старому хешу → last_used+revoke,
    вставка новой строки с новым хешом. Возвращает user_id и login или None.
    """
    async with aiosqlite.connect(db_path) as db:
        await db.execute("BEGIN IMMEDIATE")
        try:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                """
                SELECT s.id, s.user_id, s.device_fingerprint, s.device_model,
                       s.device_os, s.ip_address, u.login AS user_login
                FROM auth_sessions s
                INNER JOIN users u ON u.id = s.user_id
                WHERE s.refresh_token_hash = ?
                  AND s.revoked_at IS NULL
                  AND s.expires_at > datetime('now')
                  AND u.is_blocked = 0
                """,
                (old_refresh_hash,),
            ) as cur:
                row = await cur.fetchone()
            if row is None:
                await db.rollback()
                return None

            sid = int(row["id"])
            uid = int(row["user_id"])
            login = str(row["user_login"])
            fp = str(row["device_fingerprint"])
            dmodel = row["device_model"]
            dos = row["device_os"]
            old_ip = row["ip_address"]
            ip_use = client_ip if (client_ip is not None and str(client_ip).strip() != "") else old_ip

            await db.execute(
                """
                UPDATE auth_sessions
                SET last_used_at = datetime('now'),
                    revoked_at = datetime('now')
                WHERE id = ? AND revoked_at IS NULL
                """,
                (sid,),
            )
            await db.execute(
                """
                INSERT INTO auth_sessions (
                    user_id, refresh_token_hash, device_fingerprint,
                    device_model, device_os, ip_address, expires_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    uid,
                    new_refresh_hash,
                    fp,
                    dmodel,
                    dos,
                    ip_use,
                    new_expires_at,
                ),
            )
            await db.commit()
            return {"user_id": uid, "login": login}
        except Exception:
            await db.rollback()
            raise


async def revoke_session_by_id(db_path: Path, session_id: int, user_id: int) -> bool:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            UPDATE auth_sessions
            SET revoked_at = datetime('now')
            WHERE id = ? AND user_id = ? AND revoked_at IS NULL
            """,
            (session_id, user_id),
        )
        await db.commit()
        return cur.rowcount > 0


async def revoke_session_by_refresh_hash(db_path: Path, refresh_token_hash: str) -> bool:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            UPDATE auth_sessions
            SET revoked_at = datetime('now')
            WHERE refresh_token_hash = ? AND revoked_at IS NULL
            """,
            (refresh_token_hash,),
        )
        await db.commit()
        return cur.rowcount > 0


async def revoke_all_sessions_for_user(db_path: Path, user_id: int) -> int:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            UPDATE auth_sessions
            SET revoked_at = datetime('now')
            WHERE user_id = ? AND revoked_at IS NULL
            """,
            (user_id,),
        )
        await db.commit()
        return cur.rowcount


async def user_has_active_session_with_fingerprint(
    db_path: Path,
    user_id: int,
    fingerprint: str,
) -> bool:
    fp = fingerprint.strip()
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            """
            SELECT 1 FROM auth_sessions
            WHERE user_id = ?
              AND device_fingerprint = ?
              AND revoked_at IS NULL
              AND expires_at > datetime('now')
            LIMIT 1
            """,
            (user_id, fp),
        ) as cur:
            return (await cur.fetchone()) is not None


async def user_has_any_active_session(db_path: Path, user_id: int) -> bool:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            """
            SELECT 1 FROM auth_sessions
            WHERE user_id = ?
              AND revoked_at IS NULL
              AND expires_at > datetime('now')
            LIMIT 1
            """,
            (user_id,),
        ) as cur:
            return (await cur.fetchone()) is not None


async def list_active_sessions(db_path: Path, user_id: int) -> list[dict[str, Any]]:
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT id, device_model, device_os, ip_address, last_used_at, created_at
            FROM auth_sessions
            WHERE user_id = ?
              AND revoked_at IS NULL
              AND expires_at > datetime('now')
            ORDER BY last_used_at DESC
            """,
            (user_id,),
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]
