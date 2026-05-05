"""
Публичные маршруты жалоб (авторизованные пользователи).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.reports import service as reports_service
from app.reports.schemas import CreateReportRequest, CreateReportResponse

router = APIRouter(tags=["Reports"])


@router.post("/reports", response_model=CreateReportResponse)
async def create_report_endpoint(
    body: CreateReportRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> CreateReportResponse:
    uid = int(user["id"])
    rid = await reports_service.submit_report(
        db,
        reporter_id=uid,
        target_type=body.target_type,
        target_user_id=body.target_user_id,
        target_message_id=body.target_message_id,
        reason_code=body.reason_code,
        description=body.description,
    )
    return CreateReportResponse(id=rid, status="open")
