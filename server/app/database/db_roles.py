"""
Роли пользователей: константы, хэш токена владельца, низкоуровневые SQL-операции.
Вызывается из Database и сервисов owner/admin roles.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import aiosqlite

ALL_ROLES: tuple[str, ...] = ("user", "admin", "chief_admin", "developer", "owner")
VALID_ROLES: frozenset[str] = frozenset(ALL_ROLES)

# Операционный персонал: инвайты, смена устройства и т.п. Иерархия прав: owner ≥ chief_admin ≥ admin ≥ user.
OPERATIONAL_STAFF_ROLES: frozenset[str] = frozenset({"owner", "chief_admin", "admin"})


def rbac_granted_intersects_required(
    granted_roles: frozenset[str] | set[str] | list[str] | tuple[str, ...],
    required_roles: frozenset[str],
) -> bool:
    """
    Синхронная проверка пересечения ролей.

    Использовать ТОЛЬКО для множеств, полученных из БД (например list_user_roles),
    никогда из JWT/тела запроса/клиентского JSON.
    """
    return bool(set(granted_roles) & required_roles)


async def rbac_user_has_any_role(
    db_path: Path,
    user_id: int,
    required_roles: frozenset[str],
) -> bool:
    """Проверка доступа по user_roles в БД — основной async-entrypoint для RBAC."""
    granted = await list_user_roles(db_path, user_id)
    return rbac_granted_intersects_required(granted, required_roles)


def hash_initial_owner_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


async def list_user_ids_with_any_role(db_path: Path, roles: tuple[str, ...]) -> list[int]:
    if not roles:
        return []
    placeholders = ",".join("?" * len(roles))
    sql = f"""
        SELECT DISTINCT user_id FROM user_roles
        WHERE role IN ({placeholders})
    """
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(sql, tuple(roles)) as cur:
            rows = await cur.fetchall()
    return [int(r[0]) for r in rows]


async def list_user_roles(db_path: Path, user_id: int) -> list[str]:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            "SELECT role FROM user_roles WHERE user_id = ? ORDER BY role",
            (user_id,),
        ) as cur:
            rows = await cur.fetchall()
    return [str(r[0]) for r in rows]


async def user_has_role(db_path: Path, user_id: int, role: str) -> bool:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            "SELECT 1 FROM user_roles WHERE user_id = ? AND role = ? LIMIT 1",
            (user_id, role),
        ) as cur:
            return (await cur.fetchone()) is not None


async def count_users_with_role(db_path: Path, role: str) -> int:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            "SELECT COUNT(*) FROM user_roles WHERE role = ?",
            (role,),
        ) as cur:
            row = await cur.fetchone()
    return int(row[0]) if row else 0


async def is_owner_claim_consumed(db_path: Path) -> bool:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            "SELECT 1 FROM owner_claim_tokens WHERE id = 1 LIMIT 1",
        ) as cur:
            return (await cur.fetchone()) is not None


async def append_role_history(
    db_path: Path,
    *,
    target_user_id: int,
    actor_user_id: int | None,
    role: str,
    action: str,
    conn: aiosqlite.Connection | None = None,
) -> None:
    if conn is not None:
        await conn.execute(
            """
            INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
            VALUES (?, ?, ?, ?)
            """,
            (target_user_id, actor_user_id, role, action),
        )
        return

    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
            VALUES (?, ?, ?, ?)
            """,
            (target_user_id, actor_user_id, role, action),
        )
        await db.commit()


async def grant_role(
    db_path: Path,
    *,
    target_user_id: int,
    actor_user_id: int | None,
    role: str,
    record_history: bool = True,
    conn: aiosqlite.Connection | None = None,
) -> bool:
    """Returns True if row was inserted (new grant)."""
    if conn is not None:
        cur = await conn.execute(
            "INSERT OR IGNORE INTO user_roles (user_id, role) VALUES (?, ?)",
            (target_user_id, role),
        )
        inserted = cur.rowcount > 0
        if inserted and record_history:
            await append_role_history(
                db_path,
                target_user_id=target_user_id,
                actor_user_id=actor_user_id,
                role=role,
                action="grant",
                conn=conn,
            )
        return inserted

    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            "INSERT OR IGNORE INTO user_roles (user_id, role) VALUES (?, ?)",
            (target_user_id, role),
        )
        inserted = cur.rowcount > 0
        if inserted and record_history:
            await db.execute(
                """
                INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
                VALUES (?, ?, ?, 'grant')
                """,
                (target_user_id, actor_user_id, role),
            )
        await db.commit()
    return inserted


async def revoke_role(
    db_path: Path,
    *,
    target_user_id: int,
    actor_user_id: int | None,
    role: str,
    record_history: bool = True,
    conn: aiosqlite.Connection | None = None,
) -> bool:
    """Returns True if a row was deleted."""
    if conn is not None:
        cur = await conn.execute(
            "DELETE FROM user_roles WHERE user_id = ? AND role = ?",
            (target_user_id, role),
        )
        deleted = cur.rowcount > 0
        if deleted and record_history:
            await append_role_history(
                db_path,
                target_user_id=target_user_id,
                actor_user_id=actor_user_id,
                role=role,
                action="revoke",
                conn=conn,
            )
        return deleted

    async with aiosqlite.connect(db_path) as db:
        cur = await db.execute(
            "DELETE FROM user_roles WHERE user_id = ? AND role = ?",
            (target_user_id, role),
        )
        deleted = cur.rowcount > 0
        if deleted and record_history:
            await db.execute(
                """
                INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
                VALUES (?, ?, ?, 'revoke')
                """,
                (target_user_id, actor_user_id, role),
            )
        await db.commit()
    return deleted


async def ensure_default_user_role(db_path: Path, user_id: int) -> None:
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            "INSERT OR IGNORE INTO user_roles (user_id, role) VALUES (?, 'user')",
            (user_id,),
        )
        await db.commit()


async def fetch_role_history(
    db_path: Path,
    *,
    target_user_id: int | None = None,
    limit: int = 200,
) -> list[dict[str, Any]]:
    lim = max(1, min(limit, 500))
    sql = """
        SELECT id, target_user_id, actor_user_id, role, action, created_at
        FROM role_change_history
    """
    params: list[Any] = []
    if target_user_id is not None:
        sql += " WHERE target_user_id = ?"
        params.append(target_user_id)
    sql += " ORDER BY id DESC LIMIT ?"
    params.append(lim)
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(sql, params) as cur:
            rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]


async def transfer_owner_atomic(
    db_path: Path,
    *,
    actor_user_id: int,
    target_user_id: int,
    new_self_role: str,
) -> None:
    if new_self_role not in VALID_ROLES:
        raise ValueError("invalid new_self_role")
    if new_self_role == "owner":
        raise ValueError("new_self_role cannot be owner")
    if actor_user_id == target_user_id:
        raise ValueError("cannot transfer to self")

    async with aiosqlite.connect(db_path) as db:
        await db.execute("BEGIN IMMEDIATE")
        try:
            async with db.execute(
                "SELECT is_blocked FROM users WHERE id = ?",
                (target_user_id,),
            ) as cur:
                trow = await cur.fetchone()
            if trow is None or int(trow[0]):
                await db.rollback()
                raise ValueError("target_not_found_or_blocked")

            async with db.execute(
                "SELECT 1 FROM user_roles WHERE user_id = ? AND role = 'owner' LIMIT 1",
                (actor_user_id,),
            ) as cur:
                if await cur.fetchone() is None:
                    await db.rollback()
                    raise ValueError("actor_not_owner")

            await db.execute(
                "INSERT OR IGNORE INTO user_roles (user_id, role) VALUES (?, 'owner')",
                (target_user_id,),
            )
            await db.execute(
                "DELETE FROM user_roles WHERE user_id = ? AND role = 'owner'",
                (actor_user_id,),
            )
            await db.execute(
                "INSERT OR IGNORE INTO user_roles (user_id, role) VALUES (?, ?)",
                (actor_user_id, new_self_role),
            )

            await db.execute(
                """
                INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
                VALUES (?, ?, 'owner', 'grant')
                """,
                (target_user_id, actor_user_id),
            )
            await db.execute(
                """
                INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
                VALUES (?, ?, 'owner', 'revoke')
                """,
                (actor_user_id, actor_user_id),
            )
            await db.execute(
                """
                INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
                VALUES (?, ?, ?, 'grant')
                """,
                (actor_user_id, actor_user_id, new_self_role),
            )

            async with db.execute(
                "SELECT COUNT(*) FROM user_roles WHERE role = 'owner'",
            ) as cur:
                oc = int((await cur.fetchone())[0])
            if oc < 1:
                await db.rollback()
                raise ValueError("no_owner_after_transfer")

            await db.commit()
        except Exception:
            await db.rollback()
            raise


async def claim_initial_owner_atomic(
    db_path: Path,
    *,
    claimer_user_id: int,
    token_hash: str,
) -> None:
    """Grants owner to claimer; records singleton claim row."""
    roles_to_add = ("owner",)
    async with aiosqlite.connect(db_path) as db:
        await db.execute("BEGIN IMMEDIATE")
        try:
            async with db.execute(
                "SELECT 1 FROM owner_claim_tokens WHERE id = 1 LIMIT 1",
            ) as cur:
                if await cur.fetchone() is not None:
                    await db.rollback()
                    raise ValueError("already_claimed")

            await db.execute(
                """
                INSERT INTO owner_claim_tokens (id, token_hash, claimed_at, claimed_by_user_id)
                VALUES (1, ?, datetime('now'), ?)
                """,
                (token_hash, claimer_user_id),
            )

            for r in roles_to_add:
                cur = await db.execute(
                    "INSERT OR IGNORE INTO user_roles (user_id, role) VALUES (?, ?)",
                    (claimer_user_id, r),
                )
                if cur.rowcount > 0:
                    await db.execute(
                        """
                        INSERT INTO role_change_history (target_user_id, actor_user_id, role, action)
                        VALUES (?, ?, ?, 'grant')
                        """,
                        (claimer_user_id, claimer_user_id, r),
                    )

            await db.commit()
        except Exception:
            await db.rollback()
            raise
