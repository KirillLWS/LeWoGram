"""HTTP-маршруты /device-transfer/*."""

from __future__ import annotations

import logging
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.device_transfer import service as dtr_service
from app.device_transfer.schemas import (
    DeviceTransferApproveBody,
    DeviceTransferDenyBody,
    DeviceTransferPollOut,
    DeviceTransferRequestCreate,
    DeviceTransferRequestOut,
)

router = APIRouter()
logger = logging.getLogger(__name__)


def _client_ip(request: Request) -> str | None:
    if request.client is None:
        return None
    return request.client.host


@router.post("/request", response_model=DeviceTransferRequestOut)
async def post_request(
    body: DeviceTransferRequestCreate,
    request: Request,
    db: Annotated[Database, Depends(get_db)],
) -> DeviceTransferRequestOut:
    """Создать pending-запрос (логин + пароль или фраза восстановления)."""
    return await dtr_service.create_request(db, body, _client_ip(request))


@router.post("/{request_id}/cancel")
async def post_cancel(
    request_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    uid = int(user["id"])
    return await dtr_service.cancel(db, uid, request_id)


@router.get("/my")
async def get_my(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[dict[str, Any]]:
    uid = int(user["id"])
    return await dtr_service.list_my_requests(db, uid)


@router.get("/pending")
async def get_pending(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[dict[str, Any]]:
    uid = int(user["id"])
    return await dtr_service.list_pending_for_admin(db, uid)


@router.get("/admin-overview")
async def get_admin_overview(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, Any]:
    """Ожидающие заявки и история (операционный персонал), без poll-токенов."""
    uid = int(user["id"])
    logger.info("device_transfer GET /admin-overview start actor_id=%s", uid)
    try:
        out = await dtr_service.admin_overview(db, uid)
        pending = out.get("pending")
        history = out.get("history")
        n_p = len(pending) if isinstance(pending, list) else 0
        n_h = len(history) if isinstance(history, list) else 0
        logger.info(
            "device_transfer GET /admin-overview ok actor_id=%s pending=%s history=%s",
            uid,
            n_p,
            n_h,
        )
        return out
    except Exception:
        logger.exception(
            "device_transfer GET /admin-overview failed actor_id=%s",
            uid,
        )
        raise


@router.post("/{request_id}/approve")
async def post_approve(
    request_id: int,
    body: DeviceTransferApproveBody,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    uid = int(user["id"])
    return await dtr_service.approve(db, uid, request_id, revoke_old=body.revoke_old)


@router.post("/{request_id}/deny")
async def post_deny(
    request_id: int,
    body: DeviceTransferDenyBody,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    uid = int(user["id"])
    return await dtr_service.deny(db, uid, request_id, body.note)


@router.get("/{request_id}/poll", response_model=DeviceTransferPollOut)
async def get_poll(
    request_id: int,
    code: str,
    db: Annotated[Database, Depends(get_db)],
) -> DeviceTransferPollOut:
    """Новое устройство: опрос по id и 6-значному коду (без JWT)."""
    return await dtr_service.poll(db, request_id, code)
