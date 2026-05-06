"""Журнал диагностики пользователей (chief_admin / owner)."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from app.auth.dependencies import get_db
from app.database.database import Database
from app.database import db_support_access, db_support_diagnostics
from app.owner.owner_deps import require_server_owner
from app.reports.deps import require_chief_admin_or_owner

router = APIRouter(tags=["Admin — поддержка"])


@router.get("/support/diagnostics", response_model=list[dict[str, Any]])
async def list_support_diagnostics(
    _: Annotated[dict, Depends(require_chief_admin_or_owner)],
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user_id: int | None = Query(None, ge=1, description="Фильтр по user_id"),
) -> list[dict[str, Any]]:
    rows = await db_support_diagnostics.list_diagnostic_logs(
        db.db_path,
        limit=limit,
        offset=offset,
        user_id=user_id,
    )
    return rows


@router.get("/support/login-logs", response_model=list[dict[str, Any]])
async def list_support_login_logs(
    _: Annotated[dict, Depends(require_server_owner)],
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user_id: int | None = Query(None, ge=1, description="Фильтр по user_id"),
) -> list[dict[str, Any]]:
    """Логи входов и отпечатков устройств; доступно только owner."""
    return await db_support_diagnostics.list_login_logs(
        db.db_path,
        limit=limit,
        offset=offset,
        user_id=user_id,
    )


@router.get("/support/access-sessions", response_model=list[dict[str, Any]])
async def list_support_access_sessions(
    _: Annotated[dict, Depends(require_server_owner)],
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user_id: int | None = Query(None, ge=1, description="Фильтр по user_id"),
) -> list[dict[str, Any]]:
    """Активные сессии явного согласия на расширенную диагностику (только owner)."""
    return await db_support_access.list_active_support_access_sessions(
        db.db_path,
        limit=limit,
        offset=offset,
        user_id=user_id,
    )
