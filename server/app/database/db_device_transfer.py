"""Низкоуровневый SQL для device_transfer_requests."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import aiosqlite


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


def hash_short_code(code: str) -> str:
    return hashlib.sha256(code.strip().encode("utf-8")).hexdigest()


async def insert_request(
    db_path: Path,
    *,
    user_id: int,
    mode: str,
    req_device_fingerprint: str,
    req_device_model: str | None,
    req_device_os: str | None,
    req_ip_address: str | None,
    req_geo_lat: float | None,
    req_geo_lng: float | None,
    req_geo_accuracy_m: float | None,
    reason: str,
    short_code: str,
    short_code_hash: str,
    expires_at: str,
) -> int:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            INSERT INTO device_transfer_requests (
                user_id, mode, req_device_fingerprint, req_device_model,
                req_device_os, req_ip_address, req_geo_lat, req_geo_lng,
                req_geo_accuracy_m, reason, status, short_code, short_code_hash,
                expires_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)
            """,
            (
                user_id,
                mode,
                req_device_fingerprint,
                req_device_model,
                req_device_os,
                req_ip_address,
                req_geo_lat,
                req_geo_lng,
                req_geo_accuracy_m,
                reason,
                short_code,
                short_code_hash,
                expires_at,
            ),
        )
        await db.commit()
        return int(cur.lastrowid)


async def get_request_by_id(db_path: Path, request_id: int) -> dict[str, Any] | None:
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            "SELECT * FROM device_transfer_requests WHERE id = ?",
            (request_id,),
        ) as cur:
            row = await cur.fetchone()
    return _row_to_dict(row) if row else None


async def fetch_pending_for_poll(
    db_path: Path,
    request_id: int,
    code_hash: str,
) -> dict[str, Any] | None:
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT * FROM device_transfer_requests
            WHERE id = ?
              AND short_code_hash = ?
              AND status = 'pending'
              AND expires_at > datetime('now')
            """,
            (request_id, code_hash),
        ) as cur:
            row = await cur.fetchone()
    return _row_to_dict(row) if row else None


async def fetch_for_poll_by_id(
    db_path: Path,
    request_id: int,
    code_hash: str,
) -> dict[str, Any] | None:
    """Любой статус (для poll после approve)."""
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT * FROM device_transfer_requests
            WHERE id = ? AND short_code_hash = ?
            """,
            (request_id, code_hash),
        ) as cur:
            row = await cur.fetchone()
    return _row_to_dict(row) if row else None


async def mark_tokens_consumed(
    db_path: Path,
    request_id: int,
) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            UPDATE device_transfer_requests
            SET poll_access_token = NULL, poll_refresh_token = NULL
            WHERE id = ?
            """,
            (request_id,),
        )
        await db.commit()


async def set_poll_tokens(
    db_path: Path,
    request_id: int,
    access_token: str,
    refresh_token: str,
) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            UPDATE device_transfer_requests
            SET poll_access_token = ?, poll_refresh_token = ?
            WHERE id = ? AND status = 'approved'
            """,
            (access_token, refresh_token, request_id),
        )
        await db.commit()


async def update_status_cancelled(db_path: Path, request_id: int, user_id: int) -> bool:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            UPDATE device_transfer_requests
            SET status = 'cancelled'
            WHERE id = ? AND user_id = ? AND status = 'pending'
            """,
            (request_id, user_id),
        )
        await db.commit()
        return cur.rowcount > 0


async def update_status_denied(
    db_path: Path,
    request_id: int,
    decided_by: int,
    note: str | None,
) -> bool:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            UPDATE device_transfer_requests
            SET status = 'denied',
                decided_by = ?,
                decision_note = ?,
                decided_at = datetime('now')
            WHERE id = ? AND status = 'pending'
            """,
            (decided_by, note, request_id),
        )
        await db.commit()
        return cur.rowcount > 0


async def update_status_approved(
    db_path: Path,
    request_id: int,
    decided_by: int,
    revoke_old: bool,
    access_token: str,
    refresh_token: str,
) -> bool:
    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            """
            UPDATE device_transfer_requests
            SET status = 'approved',
                decided_by = ?,
                decided_at = datetime('now'),
                revoke_old_devices = ?,
                poll_access_token = ?,
                poll_refresh_token = ?
            WHERE id = ? AND status = 'pending'
            """,
            (decided_by, 1 if revoke_old else 0, access_token, refresh_token, request_id),
        )
        await db.commit()
        return cur.rowcount > 0


async def list_pending_all(db_path: Path) -> list[dict[str, Any]]:
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT d.id, d.user_id, d.mode,
                d.req_device_fingerprint, d.req_device_model, d.req_device_os,
                d.req_ip_address, d.req_geo_lat, d.req_geo_lng, d.req_geo_accuracy_m,
                d.reason, d.status, d.decided_by, d.decision_note, d.revoke_old_devices,
                d.created_at, d.decided_at, d.expires_at,
                u.login AS user_login, u.display_name AS user_display_name,
                dec.login AS decided_by_login
            FROM device_transfer_requests d
            INNER JOIN users u ON u.id = d.user_id
            LEFT JOIN users dec ON dec.id = d.decided_by
            WHERE d.status = 'pending'
              AND d.expires_at > datetime('now')
            ORDER BY d.id DESC
            """,
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]


async def list_admin_history(db_path: Path, limit: int = 80) -> list[dict[str, Any]]:
    """Неактивные ожидания и завершённые заявки (без poll-токенов)."""
    lim = max(1, min(limit, 200))
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT d.id, d.user_id, d.mode,
                d.req_device_fingerprint, d.req_device_model, d.req_device_os,
                d.req_ip_address, d.req_geo_lat, d.req_geo_lng, d.req_geo_accuracy_m,
                d.reason, d.status, d.decided_by, d.decision_note, d.revoke_old_devices,
                d.created_at, d.decided_at, d.expires_at,
                u.login AS user_login, u.display_name AS user_display_name,
                dec.login AS decided_by_login
            FROM device_transfer_requests d
            INNER JOIN users u ON u.id = d.user_id
            LEFT JOIN users dec ON dec.id = d.decided_by
            WHERE NOT (d.status = 'pending' AND d.expires_at > datetime('now'))
            ORDER BY d.id DESC
            LIMIT ?
            """,
            (lim,),
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]


async def list_my_requests(db_path: Path, user_id: int, limit: int = 50) -> list[dict[str, Any]]:
    lim = max(1, min(limit, 100))
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT d.id, d.user_id, d.mode, d.status, d.reason, d.created_at, d.decided_at,
                   d.expires_at, d.req_device_fingerprint, d.req_device_model, d.req_device_os,
                   d.req_ip_address, d.req_geo_lat, d.req_geo_lng, d.req_geo_accuracy_m,
                   d.decided_by, d.decision_note, d.short_code,
                   dec.login AS decided_by_login
            FROM device_transfer_requests d
            LEFT JOIN users dec ON dec.id = d.decided_by
            WHERE d.user_id = ?
            ORDER BY d.id DESC
            LIMIT ?
            """,
            (user_id, lim),
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]
