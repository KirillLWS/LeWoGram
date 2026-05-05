"""
Права для маршрутов модерации: те же роли, что и для инвайтов / device transfer —
только таблица user_roles через Database.rbac_user_has_any_role.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.database.db_roles import OPERATIONAL_STAFF_ROLES


async def require_moderation_staff(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    uid = int(user["id"])
    if not await db.rbac_user_has_any_role(uid, OPERATIONAL_STAFF_ROLES):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав (нужна роль admin, chief_admin или owner)",
        )
    return user
