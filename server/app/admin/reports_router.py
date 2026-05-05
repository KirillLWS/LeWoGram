"""
Список и разбор жалоб (staff).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth.dependencies import get_db
from app.database.database import Database
import app.database.db_reports as db_reports
from app.reports.deps import require_moderation_staff
from app.reports.schemas import (
    RejectReportRequest,
    ReportDetail,
    ReportHistoryItem,
    ReportListItem,
    ResolveReportRequest,
)

router = APIRouter(tags=["Admin — жалобы"])


@router.get("/reports", response_model=list[ReportListItem])
async def list_reports_endpoint(
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
    status_filter: str | None = Query(None, alias="status"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[ReportListItem]:
    _ = staff
    if status_filter:
        sf = status_filter.strip().lower()
        if sf not in db_reports.VALID_STATUSES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Недопустимый status",
            )
    else:
        sf = None
    rows = await db_reports.list_reports(
        db,
        status=sf,
        limit=limit,
        offset=offset,
    )
    return [ReportListItem.from_row(r) for r in rows]


@router.get("/reports/{report_id}", response_model=ReportDetail)
async def get_report_endpoint(
    report_id: int,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
) -> ReportDetail:
    _ = staff
    row = await db_reports.get_report_by_id(db, report_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Жалоба не найдена")
    return ReportDetail.from_row(row)


@router.get("/reports/{report_id}/history", response_model=list[ReportHistoryItem])
async def get_report_history_endpoint(
    report_id: int,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
) -> list[ReportHistoryItem]:
    _ = staff
    row = await db_reports.get_report_by_id(db, report_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Жалоба не найдена")
    hist = await db_reports.get_report_history(db, report_id)
    return [ReportHistoryItem.from_row(h) for h in hist]


@router.post("/reports/{report_id}/resolve", response_model=ReportDetail)
async def resolve_report_endpoint(
    report_id: int,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
    body: ResolveReportRequest | None = None,
) -> ReportDetail:
    existing = await db_reports.get_report_by_id(db, report_id)
    if existing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Жалоба не найдена")
    st = str(existing.get("status") or "")
    if st in ("resolved", "rejected", "dismissed"):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Жалоба уже закрыта")
    ok = await db_reports.update_report_status(
        db,
        report_id=report_id,
        actor_id=int(staff["id"]),
        new_status="resolved",
        action="resolve",
        resolution_note=(body.note if body else None),
    )
    if not ok:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Не удалось обновить")
    row = await db_reports.get_report_by_id(db, report_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Не удалось загрузить жалобу")
    return ReportDetail.from_row(row)


@router.post("/reports/{report_id}/reject", response_model=ReportDetail)
async def reject_report_endpoint(
    report_id: int,
    staff: Annotated[dict, Depends(require_moderation_staff)],
    db: Annotated[Database, Depends(get_db)],
    body: RejectReportRequest | None = None,
) -> ReportDetail:
    existing = await db_reports.get_report_by_id(db, report_id)
    if existing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Жалоба не найдена")
    st = str(existing.get("status") or "")
    if st in ("resolved", "rejected", "dismissed"):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Жалоба уже закрыта")
    ok = await db_reports.update_report_status(
        db,
        report_id=report_id,
        actor_id=int(staff["id"]),
        new_status="rejected",
        action="reject",
        resolution_note=(body.note if body else None),
    )
    if not ok:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Не удалось обновить")
    row = await db_reports.get_report_by_id(db, report_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Не удалось загрузить жалобу")
    return ReportDetail.from_row(row)
