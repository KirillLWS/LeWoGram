"""
Админ-маршруты ролей: include_router(..., prefix='/admin').
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.admin import roles_service as rsvc
from app.admin.roles_schemas import GrantRoleBody, RevokeRoleBody, RoleHistoryEntry, RolesListResponse
from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database

router = APIRouter(tags=["admin", "roles"])


@router.get("/users/{user_id}/roles", response_model=RolesListResponse)
async def admin_get_user_roles(
    user_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> RolesListResponse:
    data = await rsvc.get_user_roles_list(db, user, user_id)
    return RolesListResponse.model_validate(data)


@router.post("/users/{user_id}/grant-role")
async def admin_grant_role(
    user_id: int,
    body: GrantRoleBody,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    return await rsvc.grant_user_role(db, user, user_id, body.role)


@router.post("/users/{user_id}/revoke-role")
async def admin_revoke_role(
    user_id: int,
    body: RevokeRoleBody,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    return await rsvc.revoke_user_role(db, user, user_id, body.role)


@router.get("/role-history", response_model=list[RoleHistoryEntry])
async def admin_role_history(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
    target_user_id: Annotated[int | None, Query(description="Фильтр по пользователю (target)")] = None,
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
) -> list[RoleHistoryEntry]:
    rows = await rsvc.list_role_history(db, user, target_user_id, limit)
    return [RoleHistoryEntry.model_validate(r) for r in rows]
