from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field

from app.auth.dependencies import get_current_user, get_db
from app.database import db_live_geo, db_support_access
from app.database.database import Database
from app.users import service as users_service
from app.users.schemas import (
    PatchUserMeRequest,
    SupportAccessGrantRequest,
    SupportAccessStateResponse,
    SupportDiagnosticSubmitRequest,
    UserMeResponse,
    UserPublicResponse,
    UserSearchResult,
)

router = APIRouter(tags=["users"])


@router.get("/me", response_model=UserMeResponse)
async def read_me(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> UserMeResponse:
    return await users_service.get_me(db, user)


@router.patch("/me", response_model=UserMeResponse)
async def update_me(
    body: PatchUserMeRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> UserMeResponse:
    return await users_service.patch_me(db, user, body)


@router.post("/me/avatar", response_model=UserMeResponse)
async def upload_my_avatar(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
    avatar: UploadFile = File(..., description="Изображение jpg/png/webp до ~5 МБ"),
) -> UserMeResponse:
    return await users_service.upload_avatar(db, user, avatar)


@router.post("/me/support-diagnostic")
async def submit_support_diagnostic_endpoint(
    body: SupportDiagnosticSubmitRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, Any]:
    """Сохранить диагностическое описание и метаданные клиента (для поддержки)."""
    return await users_service.submit_support_diagnostic(db, user, body)


@router.get("/me/support-access", response_model=SupportAccessStateResponse)
async def get_my_support_access_endpoint(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> SupportAccessStateResponse:
    """Статус временного доступа поддержки к расширенной диагностике."""
    return await users_service.get_support_access_state(db, user)


@router.post("/me/support-access/grant", response_model=SupportAccessStateResponse)
async def grant_my_support_access_endpoint(
    body: SupportAccessGrantRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> SupportAccessStateResponse:
    """Включить временный доступ поддержки к расширенной диагностике."""
    return await users_service.grant_support_access(db, user, body)


@router.post("/me/support-access/revoke")
async def revoke_my_support_access_endpoint(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, Any]:
    """Отключить ранее выданный временный доступ поддержки."""
    return await users_service.revoke_support_access(db, user)


class LiveGeoPointRequest(BaseModel):
    lat: float = Field(..., ge=-90.0, le=90.0)
    lng: float = Field(..., ge=-180.0, le=180.0)
    accuracy_m: float | None = Field(default=None, ge=0.0, le=100000.0)
    recorded_at: str | None = Field(default=None, max_length=64)


@router.post("/me/live-geo")
async def post_my_live_geo_endpoint(
    body: LiveGeoPointRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, Any]:
    """Записать точку лайв-геолокации. Требуется активный support-access (согласие пользователя)."""
    uid = int(user["id"])
    active = await db_support_access.get_active_support_access(db.db_path, user_id=uid)
    if not active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Лайв-геолокация требует активного доступа поддержки. "
            "Включите его (/users/me/support-access/grant) и подтвердите согласие.",
        )
    pid = await db_live_geo.insert_live_geo(
        db,
        user_id=uid,
        lat=float(body.lat),
        lng=float(body.lng),
        accuracy_m=float(body.accuracy_m) if body.accuracy_m is not None else None,
        recorded_at=body.recorded_at,
    )
    return {"id": pid, "ok": True}


@router.get("/search", response_model=list[UserSearchResult])
async def search_users_endpoint(
    q: Annotated[str, Query(min_length=1)],
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[UserSearchResult]:
    return await users_service.search_users(db, int(user["id"]), q)


@router.get("/{user_id}", response_model=UserPublicResponse)
async def read_public_profile(
    user_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> UserPublicResponse:
    return await users_service.get_public_profile(db, int(user["id"]), user_id)
