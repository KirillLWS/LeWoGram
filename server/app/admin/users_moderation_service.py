"""
Список пользователей и staff-бан (owner / admin / chief_admin).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import HTTPException, status

from app.admin.users_moderation_schemas import (
    AdminUserListItem,
    AdminUserListResponse,
    StaffBanRequest,
)
from app.admin.staff_moderation_guard import assert_staff_may_ban_target
from app.database import db_auth_sessions
from app.database.database import Database

_STAFF_BAN_DURATION_MIN_MINUTES = 1
_STAFF_BAN_DURATION_MAX_MINUTES = 20 * 365 * 24 * 60  # 20 лет


def _row_to_list_item(row: dict[str, Any]) -> AdminUserListItem:
    return AdminUserListItem(
        id=int(row["id"]),
        login=str(row["login"]),
        username=row.get("username"),
        display_name=row.get("display_name"),
        avatar_path=row.get("avatar_path"),
        account_status=str(row.get("account_status") or "active"),
        ban_until=row.get("ban_until"),
        ban_reason=str(row.get("ban_reason") or ""),
        staff_ban=bool(int(row.get("staff_ban", 0))),
        is_blocked=bool(int(row.get("is_blocked", 0))),
        created_at=str(row.get("created_at") or ""),
        last_seen_at=row.get("last_seen_at"),
    )


async def list_users(
    db: Database,
    *,
    limit: int,
    offset: int,
    q: str | None,
) -> AdminUserListResponse:
    rows, total = await db.list_users_for_staff(
        limit=limit,
        offset=offset,
        query=q,
    )
    return AdminUserListResponse(
        users=[_row_to_list_item(r) for r in rows],
        total=total,
    )


async def apply_staff_ban(
    db: Database,
    *,
    actor_id: int,
    target_user_id: int,
    body: StaffBanRequest,
) -> AdminUserListItem:
    await assert_staff_may_ban_target(db, actor_id=actor_id, target_user_id=target_user_id)

    reason = body.reason.strip() if body.reason else ""

    if body.kind == "temporary":
        if body.duration_minutes is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Для временной блокировки укажите duration_minutes",
            )
        dm = int(body.duration_minutes)
        if dm < _STAFF_BAN_DURATION_MIN_MINUTES or dm > _STAFF_BAN_DURATION_MAX_MINUTES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"duration_minutes: от {_STAFF_BAN_DURATION_MIN_MINUTES} до {_STAFF_BAN_DURATION_MAX_MINUTES}",
            )
        until = (datetime.now(timezone.utc) + timedelta(minutes=dm)).strftime(
            "%Y-%m-%d %H:%M:%S",
        )
        await db.staff_set_temp_ban(target_user_id, reason, until)
    else:
        await db.staff_set_perm_ban(target_user_id, reason)

    await db_auth_sessions.revoke_all_sessions_for_user(db.db_path, target_user_id)
    fresh = await db.get_user_by_id(target_user_id)
    if fresh is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Ошибка БД")
    return _row_to_list_item(fresh)


async def apply_staff_unban(
    db: Database,
    *,
    actor_id: int,
    target_user_id: int,
) -> AdminUserListItem:
    await assert_staff_may_ban_target(db, actor_id=actor_id, target_user_id=target_user_id)
    await db.staff_unban(target_user_id)
    fresh = await db.get_user_by_id(target_user_id)
    if fresh is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Ошибка БД")
    return _row_to_list_item(fresh)
