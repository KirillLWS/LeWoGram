"""
Маршруты /owner/* — подключение в main: include_router(..., prefix='/owner').
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.owner.owner_deps import require_server_owner
from app.owner.schemas import OwnerClaimRequest, OwnerTransferRequest
from app.owner import service as owner_service

router = APIRouter(tags=["owner"])


@router.post("/claim")
async def owner_claim(
    body: OwnerClaimRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    """Одноразовый claim по INITIAL_OWNER_TOKEN; выдаёт роль owner."""
    return await owner_service.claim_owner(db, user, body)


@router.post("/transfer")
async def owner_transfer(
    body: OwnerTransferRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    """Атомарно: цель получает owner; актор теряет owner и получает new_self_role."""
    return await owner_service.transfer_owner(db, user, body)


@router.get("/server-chats")
async def owner_server_chats(
    _: Annotated[dict, Depends(require_server_owner)],
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict[str, Any]:
    """Список чатов сервера (владелец), с LIMIT/OFFSET."""
    rows = await owner_service.list_server_chats(db, limit=limit, offset=offset)
    return {"data": rows}
