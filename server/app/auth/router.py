"""
HTTP-маршруты /auth/*: регистрация, вход, «я», смена пароля.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import JSONResponse

from app.auth.dependencies import get_current_user, get_db
from app.auth.schemas import (
    AuthSessionResponse,
    ChangePasswordRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    RegisterResponse,
    TokenResponse,
    UserResponse,
)
from app.auth import service as auth_service
from app.database.database import Database
from app.device_transfer.schemas import DeviceTransferRequestOut, RecoverInitRequest


router = APIRouter()


def _client_ip(request: Request) -> str | None:
    if request.client is None:
        return None
    return request.client.host


@router.post("/register", response_model=RegisterResponse)
async def register(
    body: RegisterRequest,
    request: Request,
    db: Annotated[Database, Depends(get_db)],
) -> RegisterResponse:
    """Регистрация по инвайт-токену."""
    return await auth_service.register_user(db, body, _client_ip(request))


@router.post("/login", response_model=None)
async def login(
    body: LoginRequest,
    request: Request,
    db: Annotated[Database, Depends(get_db)],
) -> TokenResponse | JSONResponse:
    """Вход; при новом устройстве — 202 и must_request_transfer."""
    out = await auth_service.login_user(db, body, _client_ip(request))
    if isinstance(out, dict):
        return JSONResponse(status_code=202, content=out)
    return out


@router.post("/recover-init", response_model=DeviceTransferRequestOut)
async def recover_init(
    body: RecoverInitRequest,
    request: Request,
    db: Annotated[Database, Depends(get_db)],
) -> DeviceTransferRequestOut:
    """Инициация смены устройства по фразе восстановления (создаёт pending-запрос)."""
    return await auth_service.recover_init(db, body, _client_ip(request))


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    body: RefreshRequest,
    request: Request,
    db: Annotated[Database, Depends(get_db)],
) -> TokenResponse:
    """Новая пара access+refresh; старый refresh после успеха недействителен (ротация)."""
    return await auth_service.refresh_access_token(db, body, _client_ip(request))


@router.post("/logout")
async def logout(
    body: LogoutRequest,
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    """Отзыв сессии по refresh-токену (текущее устройство)."""
    return await auth_service.logout_with_refresh(db, body)


@router.post("/logout-all")
async def logout_all(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, int]:
    """Отозвать все refresh-сессии пользователя (нужен access JWT)."""
    uid = int(user["id"])
    return await auth_service.logout_all_sessions_for_user(db, uid)


@router.get("/sessions", response_model=list[AuthSessionResponse])
async def list_sessions(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[AuthSessionResponse]:
    """Активные сессии (устройства) для UI."""
    uid = int(user["id"])
    rows = await auth_service.list_user_auth_sessions(db, uid)
    return [AuthSessionResponse.model_validate(r) for r in rows]


@router.delete("/sessions/{session_id}", status_code=204)
async def delete_session(
    session_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> Response:
    """Отозвать конкретную сессию по id."""
    uid = int(user["id"])
    await auth_service.revoke_user_auth_session(db, uid, session_id)
    return Response(status_code=204)


@router.get("/me", response_model=UserResponse)
async def me(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> UserResponse:
    """Текущий пользователь по JWT."""
    uid = int(user["id"])
    roles = await db.list_user_roles(uid)
    payload = {**user, "roles": roles}
    return UserResponse.model_validate(payload)


@router.post("/change-password")
async def change_password(
    body: ChangePasswordRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    """Смена пароля (нужен Bearer-токен)."""
    uid = int(user["id"])
    return await auth_service.change_password(db, uid, body)
