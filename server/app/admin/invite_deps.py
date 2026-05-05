"""
Права на создание и просмотр инвайт-ссылок: owner, chief_admin и admin
(константа OPERATIONAL_STAFF_ROLES в db_roles). Developer / только user — 403.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.database.db_roles import OPERATIONAL_STAFF_ROLES


async def require_invite_manager(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    """Проверяет операционную роль (владелец, главный или обычный админ)."""
    uid = int(user["id"])
    if not await db.rbac_user_has_any_role(uid, OPERATIONAL_STAFF_ROLES):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Создавать инвайты могут владелец, главный администратор или администратор",
        )
    return user
