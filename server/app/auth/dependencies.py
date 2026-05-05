"""
Зависимости FastAPI: доступ к БД и текущему пользователю по Bearer-токену.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth import service as auth_service
from app.database.database import Database

security = HTTPBearer(auto_error=True)


async def get_db(request: Request) -> Database:
    """База из lifespan (app.state.db)."""
    return request.app.state.db


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    """Authorization: Bearer <JWT> → строка users из БД (или HTTP 401/403)."""
    return await auth_service.get_current_user(credentials.credentials, db)
