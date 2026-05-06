"""
/admin/users — список всех пользователей и staff-блокировки.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.admin.users_moderation_schemas import (
    AdminUserListItem,
    AdminUserListResponse,
    StaffBanRequest,
)
from app.admin import users_moderation_service as users_mod_svc
from app.admin.staff_moderation_guard import assert_staff_may_ban_target
from app.auth.dependencies import get_db
from app.database import db_auth_sessions, db_user_audit
from app.database.database import Database
from app.reports.deps import require_moderation_staff

router = APIRouter(tags=["Admin — пользователи"])


@router.get("/users", response_model=AdminUserListResponse)
async def admin_list_users(
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    q: str | None = Query(None, description="Поиск по логину, username, display_name"),
) -> AdminUserListResponse:
    _ = staff
    return await users_mod_svc.list_users(db, limit=limit, offset=offset, q=q)


@router.post("/users/{user_id}/ban", response_model=AdminUserListItem)
async def admin_ban_user(
    user_id: int,
    body: StaffBanRequest,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
) -> AdminUserListItem:
    actor_id = int(staff["id"])
    return await users_mod_svc.apply_staff_ban(
        db,
        actor_id=actor_id,
        target_user_id=user_id,
        body=body,
    )


@router.post("/users/{user_id}/unban", response_model=AdminUserListItem)
async def admin_unban_user(
    user_id: int,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
) -> AdminUserListItem:
    actor_id = int(staff["id"])
    return await users_mod_svc.apply_staff_unban(
        db,
        actor_id=actor_id,
        target_user_id=user_id,
    )


@router.post("/users/{user_id}/revoke-sessions")
async def admin_revoke_user_sessions(
    user_id: int,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, int]:
    """Сбросить все активные refresh-сессии пользователя (выйти на всех устройствах)."""
    actor_id = int(staff["id"])
    await assert_staff_may_ban_target(db, actor_id=actor_id, target_user_id=user_id)
    n = await db_auth_sessions.revoke_all_sessions_for_user(db.db_path, user_id)
    db_user_audit.schedule_user_audit_event(
        db.db_path,
        user_id=user_id,
        actor_id=actor_id,
        event_type="admin.revoke_sessions",
        payload={"revoked": n, "target_user_id": user_id},
    )
    return {"revoked": n}

