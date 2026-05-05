"""
Бизнес-логика инвайтов для админ-маршрутов (owner / chief_admin).
"""

from __future__ import annotations

from typing import Any

from app.auth import invite as invite_module
from app.database.database import Database


async def create_invite_for_admin(
    db: Database,
    created_by_user_id: int,
    *,
    expires_hours: int,
    note: str | None,
) -> dict[str, Any]:
    """
    Создаёт запись в invite_links и возвращает словарь для InviteCreatedResponse.
    """
    token = await invite_module.create_invite(
        db,
        created_by_user_id,
        expires_hours=expires_hours,
        note=note,
    )
    row = await db.get_invite_by_token(token)
    if row is None:
        raise RuntimeError("инвайт создан, но не найден по токену")
    return {
        "token": token,
        "expires_at": str(row.get("expires_at") or ""),
        "created_at": str(row.get("created_at") or ""),
        "created_by_user_id": created_by_user_id,
    }


async def list_invites_for_admin(db: Database, limit: int = 100) -> list[dict[str, Any]]:
    return await db.list_invite_links(limit=limit)
