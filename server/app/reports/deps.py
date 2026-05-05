"""
Права для маршрутов модерации: staff-роль из users.system_role (или role, если задана соглашением).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.auth.dependencies import get_current_user

STAFF_ROLES = frozenset({"admin", "chief_admin", "owner"})


def _user_system_role(user: dict) -> str:
    r = user.get("system_role") or user.get("role") or "user"
    return str(r).strip().lower() or "user"


async def require_moderation_staff(
    user: Annotated[dict, Depends(get_current_user)],
) -> dict:
    if _user_system_role(user) not in STAFF_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав (нужна роль admin, chief_admin или owner)",
        )
    return user
