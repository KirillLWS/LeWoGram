"""
HTTP-маршруты /auth/*: регистрация, вход, «я», смена пароля.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.auth.dependencies import get_current_user, get_db
from app.auth.schemas import (
    ChangePasswordRequest,
    LoginRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from app.auth import service as auth_service
from app.database.database import Database

router = APIRouter()


def _client_ip(request: Request) -> str | None:
    if request.client is None:
        return None
    return request.client.host


@router.post("/register", response_model=TokenResponse)
async def register(
    body: RegisterRequest,
    request: Request,
    db: Annotated[Database, Depends(get_db)],
) -> TokenResponse:
    """Регистрация по инвайт-токену."""
    return await auth_service.register_user(db, body, _client_ip(request))


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    request: Request,
    db: Annotated[Database, Depends(get_db)],
) -> TokenResponse:
    """Вход; при любой ошибке учётных данных — 401/403 и запись в login_logs."""
    return await auth_service.login_user(db, body, _client_ip(request))


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
