"""
Тикет-система поддержки (type='support_ticket').

Каждый тикет — отдельный чат, в котором один обычный пользователь и весь staff
(owner + chief_admin + admin). Статусы: open / user_closed / admin_closed /
both_closed / closed_finalized. Финальное закрытие/реоткрытие — только
chief_admin или owner.
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite
from fastapi import HTTPException, status

from app.database.database import Database
from app.database.db_roles import (
    CHIEF_OR_OWNER_ROLES,
    OPERATIONAL_STAFF_ROLES,
    list_user_ids_with_any_role,
    list_user_roles,
)

logger = logging.getLogger(__name__)


STATUS_OPEN = "open"
STATUS_USER_CLOSED = "user_closed"
STATUS_ADMIN_CLOSED = "admin_closed"
STATUS_BOTH_CLOSED = "both_closed"
STATUS_FINALIZED = "closed_finalized"


def _is_staff(roles: set[str]) -> bool:
    return bool(roles & OPERATIONAL_STAFF_ROLES)


def _is_chief(roles: set[str]) -> bool:
    return bool(roles & CHIEF_OR_OWNER_ROLES)


async def _user_role_set(db: Database, user_id: int) -> set[str]:
    return {r.lower() for r in await list_user_roles(db.db_path, user_id)}


def _format_meta_for_message(meta_json: str | None) -> str:
    """Однострочное превью client_meta (без чувствительных полей)."""
    if not meta_json:
        return ""
    import json as _json
    try:
        data = _json.loads(meta_json)
        if not isinstance(data, dict):
            return ""
    except Exception:
        return meta_json[:120]
    keys = (
        "platform", "os_version", "app_version", "device_model",
        "device_os", "locale", "timezone",
    )
    parts: list[str] = []
    for k in keys:
        v = data.get(k)
        if v not in (None, ""):
            parts.append(f"{k}={v}")
    if "geo_lat" in data and "geo_lng" in data:
        parts.append(f"geo={data['geo_lat']:.4f},{data['geo_lng']:.4f}")
    return "; ".join(parts)


async def create_support_ticket(
    db: Database,
    user_id: int,
    *,
    subject: str | None,
    body: str | None = None,
    client_meta: str | None = None,
) -> dict[str, Any]:
    """Создаёт новый тикет: чат типа support_ticket с участниками user + staff.
    При наличии body/client_meta — пишет диагностику в support_diagnostic_logs
    и постит первое системное сообщение в чат тикета.
    """
    title = (subject or "").strip()[:120] or "Запрос в поддержку"
    staff_ids = await list_user_ids_with_any_role(
        db.db_path, tuple(OPERATIONAL_STAFF_ROLES)
    )
    members = {user_id, *staff_ids}
    async with aiosqlite.connect(db.db_path) as conn:
        conn.row_factory = aiosqlite.Row
        await conn.execute("BEGIN IMMEDIATE")
        try:
            cur = await conn.execute(
                """
                INSERT INTO chats (
                    type, title, created_by,
                    support_user_id, support_status, support_subject
                )
                VALUES ('support_ticket', ?, ?, ?, ?, ?)
                """,
                (title, user_id, user_id, STATUS_OPEN, title),
            )
            chat_id = int(cur.lastrowid)
            for mid in members:
                role = "owner" if mid == user_id else "member"
                await conn.execute(
                    """
                    INSERT INTO chat_members (chat_id, user_id, role, can_write)
                    VALUES (?, ?, ?, 1)
                    """,
                    (chat_id, mid, role),
                )
            await conn.execute(
                "UPDATE chats SET members_count = ?, updated_at = datetime('now') WHERE id = ?",
                (len(members), chat_id),
            )
            await conn.commit()
        except Exception:
            await conn.rollback()
            raise
        async with conn.execute(
            "SELECT * FROM chats WHERE id = ?", (chat_id,)
        ) as c2:
            row = await c2.fetchone()

    # Авто-прикрепление диагностики к тикету.
    body_text = (body or "").strip()
    if body_text or client_meta:
        from app.database import db_support_diagnostics
        try:
            await db_support_diagnostics.insert_diagnostic_log(
                db, user_id=user_id,
                body=body_text or "(без описания)",
                client_meta=client_meta,
            )
        except Exception:
            logger.exception("ticket %s: diagnostic log insert failed", chat_id)
        meta_summary = _format_meta_for_message(client_meta)
        message_text_lines = ["[diagnostic]"]
        if body_text:
            message_text_lines.append(body_text)
        if meta_summary:
            message_text_lines.append(f"meta: {meta_summary}")
        try:
            await db.create_message(
                chat_id=chat_id,
                sender_id=user_id,
                type="text",
                text="\n".join(message_text_lines),
            )
        except Exception:
            logger.exception("ticket %s: system message insert failed", chat_id)

    logger.info(
        "support ticket created chat=%s user=%s staff=%s",
        chat_id, user_id, len(staff_ids),
    )
    return dict(row)


async def list_my_tickets(db: Database, user_id: int) -> list[dict[str, Any]]:
    async with aiosqlite.connect(db.db_path) as conn:
        conn.row_factory = aiosqlite.Row
        async with conn.execute(
            """
            SELECT id, title, support_subject, support_status, support_user_id,
                   created_at, updated_at
            FROM chats
            WHERE type = 'support_ticket' AND support_user_id = ?
            ORDER BY
                CASE support_status WHEN 'closed_finalized' THEN 1 ELSE 0 END,
                COALESCE(updated_at, created_at) DESC,
                id DESC
            """,
            (user_id,),
        ) as cur:
            rows = await cur.fetchall()
    return [dict(r) for r in rows]


async def list_all_tickets_for_staff(
    db: Database, *, include_finalized: bool = True
) -> list[dict[str, Any]]:
    sql = """
        SELECT c.id, c.title, c.support_subject, c.support_status,
               c.support_user_id, c.created_at, c.updated_at,
               u.login AS user_login, u.display_name AS user_display_name,
               u.username AS user_username
        FROM chats c
        LEFT JOIN users u ON u.id = c.support_user_id
        WHERE c.type = 'support_ticket'
    """
    if not include_finalized:
        sql += " AND COALESCE(c.support_status, 'open') != 'closed_finalized'"
    sql += """
        ORDER BY
            CASE c.support_status WHEN 'closed_finalized' THEN 1 ELSE 0 END,
            COALESCE(c.updated_at, c.created_at) DESC,
            c.id DESC
    """
    async with aiosqlite.connect(db.db_path) as conn:
        conn.row_factory = aiosqlite.Row
        async with conn.execute(sql) as cur:
            rows = await cur.fetchall()
    return [dict(r) for r in rows]


async def get_ticket_for_user(
    db: Database, chat_id: int, actor_id: int
) -> dict[str, Any] | None:
    """Возвращает тикет, если actor — заявитель или staff. Иначе None."""
    ticket = await _get_ticket(db, chat_id)
    if ticket is None:
        return None
    if int(ticket.get("support_user_id") or 0) == actor_id:
        return ticket
    actor_roles = await _user_role_set(db, actor_id)
    if _is_staff(actor_roles):
        return ticket
    return None


async def _get_ticket(db: Database, chat_id: int) -> dict[str, Any] | None:
    async with aiosqlite.connect(db.db_path) as conn:
        conn.row_factory = aiosqlite.Row
        async with conn.execute(
            "SELECT * FROM chats WHERE id = ? AND type = 'support_ticket'",
            (chat_id,),
        ) as cur:
            row = await cur.fetchone()
    return dict(row) if row else None


def _combine_status(user_closed: bool, admin_closed: bool) -> str:
    if user_closed and admin_closed:
        return STATUS_BOTH_CLOSED
    if user_closed:
        return STATUS_USER_CLOSED
    if admin_closed:
        return STATUS_ADMIN_CLOSED
    return STATUS_OPEN


def _flags_from_status(status_str: str | None) -> tuple[bool, bool, bool]:
    """returns (user_closed, admin_closed, finalized)."""
    s = (status_str or STATUS_OPEN).lower()
    if s == STATUS_FINALIZED:
        return True, True, True
    if s == STATUS_BOTH_CLOSED:
        return True, True, False
    if s == STATUS_USER_CLOSED:
        return True, False, False
    if s == STATUS_ADMIN_CLOSED:
        return False, True, False
    return False, False, False


async def mark_ticket_state(
    db: Database, chat_id: int, actor_id: int, *, state: str
) -> dict[str, Any]:
    """state: 'closed' | 'reopen'. Сторона определяется по роли actor_id."""
    if state not in {"closed", "reopen"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="state must be 'closed' or 'reopen'",
        )
    ticket = await _get_ticket(db, chat_id)
    if ticket is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тикет не найден",
        )
    actor_roles = await _user_role_set(db, actor_id)
    is_staff = _is_staff(actor_roles)
    is_requester = int(ticket.get("support_user_id") or 0) == actor_id
    if not (is_staff or is_requester):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ только участникам тикета",
        )
    user_closed, admin_closed, finalized = _flags_from_status(
        ticket.get("support_status")
    )
    if finalized:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Тикет окончательно закрыт. Реоткрытие — только chief_admin/owner.",
        )
    new_user, new_admin = user_closed, admin_closed
    if is_requester:
        new_user = state == "closed"
    if is_staff:
        new_admin = state == "closed"
    new_status = _combine_status(new_user, new_admin)
    async with aiosqlite.connect(db.db_path) as conn:
        await conn.execute(
            "UPDATE chats SET support_status = ?, updated_at = datetime('now') WHERE id = ?",
            (new_status, chat_id),
        )
        await conn.commit()
    ticket["support_status"] = new_status
    return ticket


async def finalize_ticket(
    db: Database, chat_id: int, actor_id: int, *, action: str
) -> dict[str, Any]:
    """action: 'close' (closed_finalized) | 'reopen' (вернуть в open)."""
    if action not in {"close", "reopen"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="action must be 'close' or 'reopen'",
        )
    actor_roles = await _user_role_set(db, actor_id)
    if not _is_chief(actor_roles):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Финальное решение принимает только chief_admin или owner",
        )
    ticket = await _get_ticket(db, chat_id)
    if ticket is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тикет не найден",
        )
    new_status = STATUS_FINALIZED if action == "close" else STATUS_OPEN
    async with aiosqlite.connect(db.db_path) as conn:
        await conn.execute(
            "UPDATE chats SET support_status = ?, updated_at = datetime('now') WHERE id = ?",
            (new_status, chat_id),
        )
        await conn.commit()
    ticket["support_status"] = new_status
    return ticket
