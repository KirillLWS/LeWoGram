"""
Выдача / отзыв ролей (админка): иерархия owner > chief_admin > admin > developer > user.
Владелец может назначать и снимать любые роли (с ограничением на последнего owner).
Остальные операторы — только роли строго ниже своей; chief_admin и owner назначает/снимает только owner.
"""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

from app.admin.staff_moderation_guard import assert_staff_may_ban_target
from app.database import db_user_audit
from app.database.database import Database
from app.database.db_roles import (
    count_users_with_role,
    highest_role_from_list,
    rbac_granted_intersects_required,
    revoke_role,
    role_rank,
    set_single_role,
    VALID_ROLES,
)


READ_ROLES: frozenset[str] = frozenset({"owner", "chief_admin", "admin", "developer"})
MUTATE_ROLES: frozenset[str] = frozenset({"owner", "chief_admin", "admin"})


def _actor_roles_set(roles: list[str]) -> set[str]:
    return set(roles)


async def _ensure_reader(db: Database, actor_id: int) -> None:
    if not await db.rbac_user_has_any_role(actor_id, READ_ROLES):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для просмотра ролей",
        )


async def _ensure_mutator(db: Database, actor_id: int) -> None:
    if not await db.rbac_user_has_any_role(actor_id, MUTATE_ROLES):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для изменения ролей",
        )


def _actor_highest_role(actor_roles: set[str]) -> str:
    return highest_role_from_list(list(actor_roles))


def _can_grant(actor_roles: set[str], role: str) -> bool:
    """
    Назначить роль R можно только если R строго ниже наивысшей роли актора,
    либо актор — owner (тогда допускаются все VALID_ROLES, включая chief_admin и owner).
    """
    if role not in VALID_ROLES:
        return False
    if not rbac_granted_intersects_required(actor_roles, MUTATE_ROLES):
        return False
    if "owner" in actor_roles:
        return True
    return role_rank(role) < role_rank(_actor_highest_role(actor_roles))


def _can_revoke(actor_roles: set[str], role: str) -> bool:
    """
    Снять роль R: owner/chief_admin — только owner; остальное — строго ниже ранга актора;
    owner может снять любую роль кроме последнего owner (отдельная проверка ниже).
    """
    if role not in VALID_ROLES:
        return False
    if role == "owner":
        return "owner" in actor_roles
    if role == "chief_admin":
        return "owner" in actor_roles
    if not rbac_granted_intersects_required(actor_roles, MUTATE_ROLES):
        return False
    if "owner" in actor_roles:
        return True
    return role_rank(role) < role_rank(_actor_highest_role(actor_roles))


async def get_user_roles_list(
    db: Database,
    actor: dict[str, Any],
    target_user_id: int,
) -> dict[str, Any]:
    actor_id = int(actor["id"])
    await _ensure_reader(db, actor_id)
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
    r = role.strip().lower()
    if r not in VALID_ROLES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Неизвестная роль")

    actor_id = int(actor["id"])
    await assert_staff_may_ban_target(db, actor_id=actor_id, target_user_id=target_user_id)
    actor_roles = _actor_roles_set(await db.list_user_roles(actor_id))
    await _ensure_mutator(db, actor_id)

    if not _can_grant(actor_roles, r):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав для назначения этой роли",
        )

    target = await db.get_user_by_id(target_user_id)
    if target is None or int(target.get("is_blocked", 0)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    await set_single_role(
        db._db_path,
        target_user_id=target_user_id,
        role=r,
        actor_user_id=actor_id,
        record_history=True,
    )
    db_user_audit.schedule_user_audit_event(
        db.db_path,
        user_id=target_user_id,
        actor_id=actor_id,
        event_type="admin.role_grant",
        payload={"role": r, "target_user_id": target_user_id},
    )
    return {"ok": True}


async def revoke_user_role(
    db: Database,
    actor: dict[str, Any],
    target_user_id: int,
    role: str,
) -> dict[str, bool]:
    r = role.strip().lower()
    if r not in VALID_ROLES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Неизвестная роль")

    actor_id = int(actor["id"])
    await assert_staff_may_ban_target(db, actor_id=actor_id, target_user_id=target_user_id)
    actor_roles = _actor_roles_set(await db.list_user_roles(actor_id))
    await _ensure_mutator(db, actor_id)

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
        if owners <= 1 and await db.rbac_user_has_any_role(target_user_id, frozenset({"owner"})):
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
    remaining = await db.list_user_roles(target_user_id)
    if not remaining:
        await set_single_role(
            db._db_path,
            target_user_id=target_user_id,
            role="user",
            actor_user_id=actor_id,
            record_history=True,
        )
    db_user_audit.schedule_user_audit_event(
        db.db_path,
        user_id=target_user_id,
        actor_id=actor_id,
        event_type="admin.role_revoke",
        payload={"role": r, "target_user_id": target_user_id},
    )
    return {"ok": True}


async def list_role_history(
    db: Database,
    actor: dict[str, Any],
    target_user_id: int | None,
    limit: int,
) -> list[dict[str, Any]]:
    actor_id = int(actor["id"])
    await _ensure_reader(db, actor_id)
    rows = await db.get_role_change_history(target_user_id=target_user_id, limit=limit)
    return rows
