"""
Маршруты модерации для санкций (staff).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.auth.dependencies import get_db
from app.database.database import Database
import app.database.db_reports as db_reports
from app.reports.deps import require_moderation_staff
from app.reports.schemas import CreateSanctionRequest, RevokeSanctionBody, SanctionResponse

router = APIRouter(tags=["Admin — санкции"])


@router.post("/sanctions", response_model=SanctionResponse)
async def create_sanction_endpoint(
    body: CreateSanctionRequest,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
) -> SanctionResponse:
    """Создать санкцию (ban выставляет users.is_blocked при активной санкции)."""
    actor_id = int(staff["id"])
    target = await db.get_user_by_id(body.user_id)
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    if body.report_id is not None:
        rep = await db_reports.get_report_by_id(db, body.report_id)
        if rep is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Жалоба не найдена")
    sid = await db_reports.create_sanction(
        db,
        user_id=body.user_id,
        sanction_type=body.sanction_type,
        reason=body.reason,
        created_by=actor_id,
        report_id=body.report_id,
        ends_at=body.ends_at,
    )
    row = await db_reports.get_sanction_by_id(db, sid)
    if row is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Санкция не сохранена")
    return SanctionResponse.from_row(row)


@router.post("/sanctions/{sanction_id}/revoke", response_model=SanctionResponse)
async def revoke_sanction_endpoint(
    sanction_id: int,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
    body: RevokeSanctionBody | None = None,
) -> SanctionResponse:
    _ = body
    row = await db_reports.revoke_sanction(
        db,
        sanction_id=sanction_id,
        revoked_by=int(staff["id"]),
    )
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Санкция не найдена")
    return SanctionResponse.from_row(row)
