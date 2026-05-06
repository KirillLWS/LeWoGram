"""Зависимости маршрутов владельца: только роль owner в user_roles."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database


async def require_server_owner(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    uid = int(user["id"])
    if not await db.rbac_user_has_any_role(uid, frozenset({"owner"})):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступно только владельцу сервера",
        )
    return user
