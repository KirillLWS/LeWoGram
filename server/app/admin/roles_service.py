"""
Выдача / отзыв ролей (админка): правила owner vs chief_admin vs остальные роли.
"""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

from app.database.database import Database
from app.database.db_roles import (
    count_users_with_role,
    grant_role,
    revoke_role,
    user_has_role,
    VALID_ROLES,
)


READ_ROLES: frozenset[str] = frozenset({"owner", "chief_admin", "developer"})
MUTATE_ROLES: frozenset[str] = frozenset({"owner", "chief_admin"})


def _actor_roles_set(roles: list[str]) -> set[str]:
    return set(roles)


def _ensure_reader(actor_id: int, actor_roles: list[str]) -> None:
    if not (_actor_roles_set(actor_roles) & READ_ROLES):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для просмотра ролей",
        )


def _ensure_mutator(actor_id: int, actor_roles: list[str]) -> None:
    if not (_actor_roles_set(actor_roles) & MUTATE_ROLES):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для изменения ролей",
        )


def _can_grant(actor_roles: set[str], role: str) -> bool:
    if role not in VALID_ROLES:
        return False
    if role in ("owner", "chief_admin"):
        return "owner" in actor_roles
    return bool(actor_roles & MUTATE_ROLES)


def _can_revoke(actor_roles: set[str], role: str) -> bool:
    if role not in VALID_ROLES:
        return False
    if role == "owner":
        return "owner" in actor_roles
    if role == "chief_admin":
        return "owner" in actor_roles
    return bool(actor_roles & MUTATE_ROLES)


async def get_user_roles_list(
    db: Database,
    actor: dict[str, Any],
    target_user_id: int,
) -> dict[str, Any]:
    actor_roles = await db.list_user_roles(int(actor["id"]))
    _ensure_reader(int(actor["id"]), actor_roles)
    target = await db.get_user_by_id(target_user_id)
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    roles = await db.list_user_roles(target_user_id)
    return {"user_id": target_user_id, "roles": roles}


async def grant_user_role(
    db: Database,
    actor: dict[str, Any],
    target_user_id: int,
    role: str,
) -> dict[str, bool]:
    r = role.strip()
    if r not in VALID_ROLES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Неизвестная роль")

    actor_id = int(actor["id"])
    actor_roles = _actor_roles_set(await db.list_user_roles(actor_id))
    _ensure_mutator(actor_id, list(actor_roles))

    if not _can_grant(actor_roles, r):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для назначения этой роли",
        )

    target = await db.get_user_by_id(target_user_id)
    if target is None or int(target.get("is_blocked", 0)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    await grant_role(
        db._db_path,
        target_user_id=target_user_id,
        actor_user_id=actor_id,
        role=r,
        record_history=True,
    )
    return {"ok": True}


async def revoke_user_role(
    db: Database,
    actor: dict[str, Any],
    target_user_id: int,
    role: str,
) -> dict[str, bool]:
    r = role.strip()
    if r not in VALID_ROLES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Неизвестная роль")

    actor_id = int(actor["id"])
    actor_roles = _actor_roles_set(await db.list_user_roles(actor_id))
    _ensure_mutator(actor_id, list(actor_roles))

    if not _can_revoke(actor_roles, r):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для отзыва этой роли",
        )

    target = await db.get_user_by_id(target_user_id)
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    if r == "owner":
        owners = await count_users_with_role(db._db_path, "owner")
        if owners <= 1 and await user_has_role(db._db_path, target_user_id, "owner"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Нельзя отозвать последнюю роль owner",
            )

    ok = await revoke_role(
        db._db_path,
        target_user_id=target_user_id,
        actor_user_id=actor_id,
        role=r,
        record_history=True,
    )
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="У пользователя нет этой роли",
        )
    return {"ok": True}


async def list_role_history(
    db: Database,
    actor: dict[str, Any],
    target_user_id: int | None,
    limit: int,
) -> list[dict[str, Any]]:
    actor_roles = await db.list_user_roles(int(actor["id"]))
    _ensure_reader(int(actor["id"]), actor_roles)
    rows = await db.get_role_change_history(target_user_id=target_user_id, limit=limit)
    return rows
