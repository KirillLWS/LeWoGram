"""
Права на создание и просмотр инвайт-ссылок: только owner и chief_admin.
Обычный admin и developer без этих ролей — 403.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database

# Роли, которым разрешена генерация и просмотр списка инвайтов
INVITE_MANAGER_ROLES = frozenset({"owner", "chief_admin"})


async def require_invite_manager(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    """Проверяет, что у пользователя есть owner или chief_admin (по таблице ролей)."""
    uid = int(user["id"])
    roles = await db.list_user_roles(uid)
    if not (INVITE_MANAGER_ROLES & set(roles)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Создавать инвайты могут только владелец и главный администратор",
        )
    return user
