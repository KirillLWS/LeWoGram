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
from app.auth.dependencies import get_db
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
    _ = staff
    return await users_mod_svc.apply_staff_unban(
        db,
        target_user_id=user_id,
    )

