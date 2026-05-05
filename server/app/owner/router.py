"""
Маршруты /owner/* — подключение в main: include_router(..., prefix='/owner').
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
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
