"""Чтение журнала аудита (chief_admin / owner)."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from app.auth.dependencies import get_db
from app.database import db_user_audit
from app.database.database import Database
from app.reports.deps import require_chief_admin_or_owner

router = APIRouter(tags=["Admin — аудит"])


@router.get("/audit/events", response_model=list[dict[str, Any]])
async def list_user_audit_events(
    _: Annotated[dict, Depends(require_chief_admin_or_owner)],
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user_id: int | None = Query(None, description="Фильтр по user_id (субъект события)"),
) -> list[dict[str, Any]]:
    return await db_user_audit.list_user_audit_events(
        db.db_path,
        limit=limit,
        offset=offset,
        user_id=user_id,
    )
