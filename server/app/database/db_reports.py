"""
Доступ к таблицам reports / report_resolution_history / user_sanctions.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import aiosqlite

from app.database.database import Database

VALID_TARGET_TYPES = frozenset({"user", "profile", "message"})
VALID_STATUSES = frozenset({"open", "in_review", "resolved", "rejected", "dismissed"})
VALID_SANCTION_TYPES = frozenset({"warning", "mute", "ban", "shadow_ban", "other"})


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


def _db_path(db: Database) -> Path:
    return Path(db._db_path)  # noqa: SLF001


async def _table_exists(db_path, name: str) -> bool:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            (name,),
        ) as cur:
            return await cur.fetchone() is not None


async def count_active_bans_for_user(db: Database, user_id: int) -> int:
    if not await _table_exists(_db_path(db), "user_sanctions"):
        return 0
    async with aiosqlite.connect(_db_path(db)) as db:
        async with db.execute(
            """
            SELECT COUNT(*) FROM user_sanctions
            WHERE user_id = ? AND is_active = 1 AND sanction_type = 'ban'
            """,
            (user_id,),
        ) as cur:
            row = await cur.fetchone()
    return int(row[0]) if row and row[0] is not None else 0


async def create_report(
    db: Database,
    *,
    reporter_id: int,
    target_type: str,
    target_user_id: int | None,
    target_message_id: int | None,
    reason_code: str,
    description: str,
) -> int:
    if not await _table_exists(_db_path(db), "reports"):
        raise RuntimeError("reports table missing; run apply_reports_schema_fragment")
    async with aiosqlite.connect(_db_path(db)) as dbw:
        cur = await dbw.execute(
            """
            INSERT INTO reports (
                reporter_id, target_type, target_user_id, target_message_id,
                reason_code, description, status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, 'open', datetime('now'), datetime('now'))
            """,
            (
                reporter_id,
                target_type,
                target_user_id,
                target_message_id,
                reason_code.strip() or "other",
                (description or "").strip(),
            ),
        )
        report_id = int(cur.lastrowid)
        await dbw.execute(
            """
            INSERT INTO report_resolution_history (report_id, actor_id, action, from_status, to_status, note, created_at)
            VALUES (?, ?, 'created', NULL, 'open', NULL, datetime('now'))
            """,
            (report_id, reporter_id),
        )
        await dbw.commit()
    return report_id


async def list_reports(
    db: Database,
    *,
    status: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> list[dict[str, Any]]:
    if not await _table_exists(_db_path(db), "reports"):
        return []
    lim = max(1, min(limit, 200))
    off = max(0, offset)
    base = """
        SELECT r.*,
               ur.login AS reporter_login,
               ur.username AS reporter_username
        FROM reports r
        LEFT JOIN users ur ON ur.id = r.reporter_id
    """
    params: list[Any] = []
    if status:
        base += " WHERE r.status = ?"
        params.append(status)
    base += " ORDER BY r.created_at DESC LIMIT ? OFFSET ?"
    params.extend([lim, off])
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(base, params) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]


async def get_report_by_id(db: Database, report_id: int) -> dict[str, Any] | None:
    if not await _table_exists(_db_path(db), "reports"):
        return None
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            """
            SELECT r.*,
                   ur.login AS reporter_login,
                   ur.username AS reporter_username,
                   ut.login AS target_user_login,
                   ut.username AS target_user_username
            FROM reports r
            LEFT JOIN users ur ON ur.id = r.reporter_id
            LEFT JOIN users ut ON ut.id = r.target_user_id
            WHERE r.id = ?
            """,
            (report_id,),
        ) as cur:
            row = await cur.fetchone()
    return _row_to_dict(row) if row else None


async def get_report_history(
    db: Database,
    report_id: int,
) -> list[dict[str, Any]]:
    if not await _table_exists(_db_path(db), "report_resolution_history"):
        return []
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            """
            SELECT h.*, u.login AS actor_login, u.username AS actor_username
            FROM report_resolution_history h
            LEFT JOIN users u ON u.id = h.actor_id
            WHERE h.report_id = ?
            ORDER BY h.created_at ASC, h.id ASC
            """,
            (report_id,),
        ) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]


async def _append_history(
    dbw: aiosqlite.Connection,
    *,
    report_id: int,
    actor_id: int,
    action: str,
    from_status: str | None,
    to_status: str | None,
    note: str | None,
) -> None:
    await dbw.execute(
        """
        INSERT INTO report_resolution_history (report_id, actor_id, action, from_status, to_status, note)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (report_id, actor_id, action, from_status, to_status, note),
    )


async def update_report_status(
    db: Database,
    *,
    report_id: int,
    actor_id: int,
    new_status: str,
    action: str,
    resolution_note: str | None,
) -> bool:
    if not await _table_exists(_db_path(db), "reports"):
        return False
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            "SELECT id, status FROM reports WHERE id = ?",
            (report_id,),
        ) as cur:
            row = await cur.fetchone()
        if not row:
            return False
        old = str(row["status"])
        if new_status in ("resolved", "rejected"):
            await dbw.execute(
                """
                UPDATE reports
                SET status = ?,
                    resolution_note = ?,
                    updated_at = datetime('now'),
                    resolved_at = datetime('now'),
                    resolved_by = ?
                WHERE id = ?
                """,
                (new_status, resolution_note, actor_id, report_id),
            )
        else:
            await dbw.execute(
                """
                UPDATE reports
                SET status = ?,
                    resolution_note = COALESCE(?, resolution_note),
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                (new_status, resolution_note, report_id),
            )
        await _append_history(
            dbw,
            report_id=report_id,
            actor_id=actor_id,
            action=action,
            from_status=old,
            to_status=new_status,
            note=resolution_note,
        )
        await dbw.commit()
    return True


async def create_sanction(
    db: Database,
    *,
    user_id: int,
    sanction_type: str,
    reason: str | None,
    created_by: int,
    report_id: int | None,
    ends_at: str | None,
) -> int:
    if not await _table_exists(_db_path(db), "user_sanctions"):
        raise RuntimeError("user_sanctions table missing")
    async with aiosqlite.connect(_db_path(db)) as dbw:
        cur = await dbw.execute(
            """
            INSERT INTO user_sanctions (
                user_id, sanction_type, reason, report_id, created_by, is_active, ends_at
            )
            VALUES (?, ?, ?, ?, ?, 1, ?)
            """,
            (user_id, sanction_type, (reason or "").strip() or None, report_id, created_by, ends_at),
        )
        sid = int(cur.lastrowid)
        if sanction_type == "ban":
            await dbw.execute(
                "UPDATE users SET is_blocked = 1 WHERE id = ?",
                (user_id,),
            )
        await dbw.commit()
    return sid


async def revoke_sanction(
    db: Database,
    *,
    sanction_id: int,
    revoked_by: int,
) -> dict[str, Any] | None:
    if not await _table_exists(_db_path(db), "user_sanctions"):
        return None
    stype = ""
    uid = 0
    remaining_bans = 0
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            "SELECT * FROM user_sanctions WHERE id = ?",
            (sanction_id,),
        ) as cur:
            row = await cur.fetchone()
        if not row:
            return None
        s = _row_to_dict(row)
        if not int(s.get("is_active", 0)):
            return s
        uid = int(s["user_id"])
        stype = str(s.get("sanction_type") or "")
        await dbw.execute(
            """
            UPDATE user_sanctions
            SET is_active = 0,
                revoked_at = datetime('now'),
                revoked_by = ?
            WHERE id = ?
            """,
            (revoked_by, sanction_id),
        )
        if stype == "ban":
            async with dbw.execute(
                """
                SELECT COUNT(*) FROM user_sanctions
                WHERE user_id = ? AND is_active = 1 AND sanction_type = 'ban'
                """,
                (uid,),
            ) as cur:
                r2 = await cur.fetchone()
                remaining_bans = int(r2[0]) if r2 and r2[0] is not None else 0
        await dbw.commit()

    if stype == "ban" and remaining_bans == 0:
        async with aiosqlite.connect(_db_path(db)) as dbw2:
            await dbw2.execute(
                "UPDATE users SET is_blocked = 0 WHERE id = ?",
                (uid,),
            )
            await dbw2.commit()
    return await get_sanction_by_id(db, sanction_id)


async def get_sanction_by_id(db: Database, sanction_id: int) -> dict[str, Any] | None:
    if not await _table_exists(_db_path(db), "user_sanctions"):
        return None
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(
            "SELECT * FROM user_sanctions WHERE id = ?",
            (sanction_id,),
        ) as cur:
            row = await cur.fetchone()
    return _row_to_dict(row) if row else None


async def list_sanctions_for_user(
    db: Database,
    user_id: int,
    *,
    active_only: bool = False,
) -> list[dict[str, Any]]:
    if not await _table_exists(_db_path(db), "user_sanctions"):
        return []
    sql = "SELECT * FROM user_sanctions WHERE user_id = ?"
    params: list[Any] = [user_id]
    if active_only:
        sql += " AND is_active = 1"
    sql += " ORDER BY created_at DESC"
    async with aiosqlite.connect(_db_path(db)) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(sql, params) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]
