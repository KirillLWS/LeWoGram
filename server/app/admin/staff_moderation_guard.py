"""
Единая точка проверки staff-действий над целевым пользователем (бан, разбан, смена ролей и т.п.).

Запрещено: действие на себя; цель с равной или более высокой ролью (иерархия в db_roles).
"""

from __future__ import annotations

from fastapi import HTTPException, status

from app.database.database import Database
from app.database.db_roles import actor_may_staff_ban_target


async def assert_staff_may_ban_target(
    db: Database,
    *,
    actor_id: int,
    target_user_id: int,
) -> None:
    if actor_id == target_user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Нельзя применить действие к самому себе",
        )
    target = await db.get_user_by_id(target_user_id)
    if target is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден",
        )
    actor_roles = await db.list_user_roles(actor_id)
    target_roles = await db.list_user_roles(target_user_id)
    ok_hier, hier_msg = actor_may_staff_ban_target(actor_roles, target_roles)
    if not ok_hier:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=hier_msg)
