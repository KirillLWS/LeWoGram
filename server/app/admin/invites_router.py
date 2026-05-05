"""
Маршруты инвайтов: POST/GET /admin/invites (только owner и chief_admin).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.admin.invite_deps import require_invite_manager
from app.admin.invites_schemas import (
    CreateInviteRequest,
    InviteCreatedResponse,
    InviteListItemResponse,
)
from app.admin import invites_service as invsvc
from app.auth.dependencies import get_db
from app.database.database import Database

router = APIRouter(tags=["admin", "invites"])


@router.post("/invites", response_model=InviteCreatedResponse)
async def post_create_invite(
    body: CreateInviteRequest,
    user: Annotated[dict, Depends(require_invite_manager)],
    db: Annotated[Database, Depends(get_db)],
) -> InviteCreatedResponse:
    """Создать одноразовый инвайт-токен (регистрация как раньше по этому токену)."""
    uid = int(user["id"])
    note = body.note.strip() if body.note else None
    data = await invsvc.create_invite_for_admin(
        db,
        uid,
        expires_hours=body.expires_hours,
        note=note,
    )
    return InviteCreatedResponse.model_validate(data)


@router.get("/invites", response_model=list[InviteListItemResponse])
async def get_invites_list(
    user: Annotated[dict, Depends(require_invite_manager)],
    db: Annotated[Database, Depends(get_db)],
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> list[InviteListItemResponse]:
    """Список последних инвайтов (метаданные; токен виден для копирования)."""
    rows = await invsvc.list_invites_for_admin(db, limit=limit)
    return [InviteListItemResponse.model_validate(r) for r in rows]
