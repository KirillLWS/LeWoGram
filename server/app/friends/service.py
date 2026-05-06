"""
Бизнес-логика friendships: заявки, принятие, блок, списки, статус пары.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import aiosqlite
from fastapi import HTTPException, status

from app.avatar_fields import apply_avatar_fields
from app.auth import ban_policy
from app.database.database import Database
from app.friends.schemas import (
    FriendRequestItem,
    FriendUserSnippet,
    FriendshipResponse,
    FriendStatusResponse,
)

logger = logging.getLogger(__name__)

_ST_PENDING = "pending"
_ST_ACCEPTED = "accepted"
_ST_DECLINED = "declined"
_ST_BLOCKED = "blocked"


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


def _friendship_from_row(row: aiosqlite.Row | dict[str, Any]) -> FriendshipResponse:
    d = _row_to_dict(row) if hasattr(row, "keys") else dict(row)
    return FriendshipResponse(
        id=int(d["id"]),
        from_user_id=int(d["from_user_id"]),
        to_user_id=int(d["to_user_id"]),
        status=str(d["status"]),
        created_at=str(d["created_at"]),
        updated_at=str(d["updated_at"]),
    )


async def _fetch_pair_rows(
    db: aiosqlite.Connection,
    a: int,
    b: int,
) -> list[dict[str, Any]]:
    db.row_factory = aiosqlite.Row
    async with db.execute(
        """
        SELECT id, from_user_id, to_user_id, status, created_at, updated_at
        FROM friendships
        WHERE (from_user_id = ? AND to_user_id = ?)
           OR (from_user_id = ? AND to_user_id = ?)
        """,
        (a, b, b, a),
    ) as cur:
        rows = await cur.fetchall()
    return [_row_to_dict(r) for r in rows]


def _is_banned_row(d: dict[str, Any]) -> bool:
    st = str(d.get("account_status") or "active").strip().lower()
    if st in ("banned", "temp_banned"):
        return True
    return bool(int(d.get("is_blocked", 0)))


def _apply_friend_ban_metadata(d: dict[str, Any]) -> None:
    st = str(d.get("account_status") or "active").strip().lower()
    d["ban_reason"] = str(d.get("ban_reason") or "")
    d["is_banned"] = _is_banned_row(d)
    d["is_permanent_ban"] = st == "banned"


async def _user_snippet(db_path: Path, user_id: int) -> FriendUserSnippet | None:
    async with aiosqlite.connect(db_path) as conn:
        conn.row_factory = aiosqlite.Row
        async with conn.execute(
            """
            SELECT id, username, display_name, avatar_path,
                   account_status, ban_until, ban_reason, is_blocked
            FROM users
            WHERE id = ? AND is_blocked = 0
            """,
            (user_id,),
        ) as cur:
            row = await cur.fetchone()
    if row is None:
        return None
    d = _row_to_dict(row)
    apply_avatar_fields(d)
    d.setdefault("account_status", "active")
    d.setdefault("ban_until", None)
    _apply_friend_ban_metadata(d)
    return FriendUserSnippet.model_validate(d)


class FriendsService:
    def __init__(self, db: Database) -> None:
        self._db = db
        self._path = db.db_path

    async def _ensure_actor_not_banned(self, user_id: int) -> None:
        row = await self._db.get_user_by_id(user_id)
        if row is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
        await ban_policy.ensure_not_banned(self._db, row)

    async def get_status(self, viewer_id: int, other_id: int) -> dict[str, Any]:
        if viewer_id == other_id:
            return {"relation": "none", "request_id": None}
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            rows = await _fetch_pair_rows(conn, viewer_id, other_id)
        return self._status_from_rows(viewer_id, other_id, rows)

    @staticmethod
    def _status_from_rows(viewer_id: int, other_id: int, rows: list[dict[str, Any]]) -> dict[str, Any]:
        by_dir: dict[tuple[int, int], dict[str, Any]] = {}
        for r in rows:
            by_dir[(int(r["from_user_id"]), int(r["to_user_id"]))] = r

        fwd = by_dir.get((viewer_id, other_id))
        rev = by_dir.get((other_id, viewer_id))

        if fwd and str(fwd["status"]) == _ST_ACCEPTED:
            return {"relation": "friends", "request_id": None}
        if rev and str(rev["status"]) == _ST_ACCEPTED:
            return {"relation": "friends", "request_id": None}

        if fwd and str(fwd["status"]) == _ST_BLOCKED:
            return {"relation": "blocked_by_me", "request_id": None}
        if rev and str(rev["status"]) == _ST_BLOCKED:
            return {"relation": "blocked_me", "request_id": None}

        if fwd and str(fwd["status"]) == _ST_PENDING:
            return {"relation": "pending_outgoing", "request_id": int(fwd["id"])}
        if rev and str(rev["status"]) == _ST_PENDING:
            return {"relation": "pending_incoming", "request_id": int(rev["id"])}

        return {"relation": "none", "request_id": None}

    async def request(self, from_user_id: int, to_user_id: int) -> FriendshipResponse:
        await self._ensure_actor_not_banned(from_user_id)
        if from_user_id == to_user_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Нельзя отправить заявку самому себе")

        target = await _user_snippet(self._path, to_user_id)
        if target is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            rows = await _fetch_pair_rows(conn, from_user_id, to_user_id)
            by_dir: dict[tuple[int, int], dict[str, Any]] = {}
            for r in rows:
                by_dir[(int(r["from_user_id"]), int(r["to_user_id"]))] = r

            fwd = by_dir.get((from_user_id, to_user_id))
            rev = by_dir.get((to_user_id, from_user_id))

            if any(str(r["status"]) == _ST_ACCEPTED for r in rows):
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Уже друзья")

            if rev and str(rev["status"]) == _ST_BLOCKED:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Пользователь недоступен")
            if fwd and str(fwd["status"]) == _ST_BLOCKED:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Сначала разблокируйте пользователя",
                )

            # Второй подал заявку, пока висит входящая от первого — взаимное принятие
            if rev and str(rev["status"]) == _ST_PENDING:
                await conn.execute(
                    """
                    UPDATE friendships
                    SET status = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    (_ST_ACCEPTED, int(rev["id"])),
                )
                await conn.commit()
                out = await self._get_friendship_by_id(conn, int(rev["id"]))
                await self._notify_friendship_push("accepted_pair", out)
                return out

            if fwd and str(fwd["status"]) == _ST_PENDING:
                return await self._get_friendship_by_id(conn, int(fwd["id"]))

            if fwd and str(fwd["status"]) == _ST_DECLINED:
                await conn.execute(
                    """
                    UPDATE friendships
                    SET status = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    (_ST_PENDING, int(fwd["id"])),
                )
                await conn.commit()
                out = await self._get_friendship_by_id(conn, int(fwd["id"]))
                await self._notify_friendship_push("request", out)
                return out

            cur = await conn.execute(
                """
                INSERT INTO friendships (from_user_id, to_user_id, status)
                VALUES (?, ?, ?)
                """,
                (from_user_id, to_user_id, _ST_PENDING),
            )
            await conn.commit()
            fid = int(cur.lastrowid)
            out = await self._get_friendship_by_id(conn, fid)
        await self._notify_friendship_push("request", out)
        return out

    async def _get_friendship_by_id(self, conn: aiosqlite.Connection, fid: int) -> FriendshipResponse:
        conn.row_factory = aiosqlite.Row
        async with conn.execute(
            """
            SELECT id, from_user_id, to_user_id, status, created_at, updated_at
            FROM friendships WHERE id = ?
            """,
            (fid,),
        ) as cur:
            row = await cur.fetchone()
        if row is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Запись не найдена")
        return _friendship_from_row(row)

    async def _notify_friendship_push(self, kind: str, row: FriendshipResponse) -> None:
        try:
            from app.push import service as push_service

            if kind == "request":
                from_uid = int(row.from_user_id)
                to_uid = int(row.to_user_id)
                from_name = await self._display_name_hint(from_uid)
                await push_service.send_push_to_user(
                    self._db,
                    to_uid,
                    "Новая заявка в друзья",
                    f"{from_name} хочет добавить вас в друзья",
                )
            elif kind == "accepted_pair":
                # Было pending B→A; A «ответил» заявкой — строка стала accepted; уведомляем инициатора B.
                original_from = int(row.from_user_id)
                accepter = int(row.to_user_id)
                name = await self._display_name_hint(accepter)
                await push_service.send_push_to_user(
                    self._db,
                    original_from,
                    "Друзья",
                    f"{name} принял(а) вашу заявку",
                )
            elif kind == "accepted":
                requester = int(row.from_user_id)
                name = await self._display_name_hint(int(row.to_user_id))
                await push_service.send_push_to_user(
                    self._db,
                    requester,
                    "Друзья",
                    f"{name} принял(а) вашу заявку",
                )
        except Exception as e:
            logger.warning("friends push: пропуск/ошибка (%s): %s", kind, e, exc_info=False)

    async def _display_name_hint(self, user_id: int) -> str:
        u = await self._db.get_user_by_id(user_id)
        if u is None:
            return "Пользователь"
        for k in ("display_name", "username", "login"):
            v = u.get(k)
            if v is not None and str(v).strip():
                return str(v).strip()
        return f"Пользователь #{user_id}"

    async def accept(self, current_user_id: int, request_id: int) -> FriendshipResponse:
        await self._ensure_actor_not_banned(current_user_id)
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            conn.row_factory = aiosqlite.Row
            async with conn.execute(
                """
                SELECT id, from_user_id, to_user_id, status, created_at, updated_at
                FROM friendships WHERE id = ?
                """,
                (request_id,),
            ) as cur:
                row = await cur.fetchone()
            if row is None:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Заявка не найдена")
            r = _row_to_dict(row)
            if int(r["to_user_id"]) != current_user_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Это не ваша входящая заявка")
            if str(r["status"]) != _ST_PENDING:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Заявка уже обработана")

            await conn.execute(
                """
                UPDATE friendships
                SET status = ?, updated_at = datetime('now')
                WHERE id = ?
                """,
                (_ST_ACCEPTED, request_id),
            )
            await conn.commit()
            out = await self._get_friendship_by_id(conn, request_id)
        await self._notify_friendship_push("accepted", out)
        return out

    async def decline(self, current_user_id: int, request_id: int) -> None:
        await self._ensure_actor_not_banned(current_user_id)
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            conn.row_factory = aiosqlite.Row
            async with conn.execute(
                "SELECT id, from_user_id, to_user_id, status FROM friendships WHERE id = ?",
                (request_id,),
            ) as cur:
                row = await cur.fetchone()
            if row is None:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Заявка не найдена")
            r = _row_to_dict(row)
            if int(r["to_user_id"]) != current_user_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Это не ваша входящая заявка")
            if str(r["status"]) != _ST_PENDING:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Заявка уже обработана")

            await conn.execute(
                """
                UPDATE friendships
                SET status = ?, updated_at = datetime('now')
                WHERE id = ?
                """,
                (_ST_DECLINED, request_id),
            )
            await conn.commit()

    async def cancel(self, from_user_id: int, target_user_id: int) -> None:
        await self._ensure_actor_not_banned(from_user_id)
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            cur = await conn.execute(
                """
                DELETE FROM friendships
                WHERE from_user_id = ? AND to_user_id = ? AND status = ?
                """,
                (from_user_id, target_user_id, _ST_PENDING),
            )
            await conn.commit()
            if cur.rowcount == 0:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Исходящей заявки нет")

    async def remove(self, user_id: int, other_user_id: int) -> None:
        await self._ensure_actor_not_banned(user_id)
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            cur = await conn.execute(
                """
                DELETE FROM friendships
                WHERE status = ?
                  AND (
                    (from_user_id = ? AND to_user_id = ?)
                    OR (from_user_id = ? AND to_user_id = ?)
                  )
                """,
                (_ST_ACCEPTED, user_id, other_user_id, other_user_id, user_id),
            )
            await conn.commit()
            if cur.rowcount == 0:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Дружба не найдена")

    async def block(self, from_user_id: int, to_user_id: int) -> None:
        await self._ensure_actor_not_banned(from_user_id)
        if from_user_id == to_user_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Некорректная операция")
        target = await _user_snippet(self._path, to_user_id)
        if target is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            await conn.execute(
                """
                DELETE FROM friendships
                WHERE (from_user_id = ? AND to_user_id = ?)
                   OR (from_user_id = ? AND to_user_id = ?)
                """,
                (from_user_id, to_user_id, to_user_id, from_user_id),
            )
            await conn.execute(
                """
                INSERT INTO friendships (from_user_id, to_user_id, status)
                VALUES (?, ?, ?)
                """,
                (from_user_id, to_user_id, _ST_BLOCKED),
            )
            await conn.commit()

    async def unblock(self, from_user_id: int, to_user_id: int) -> None:
        await self._ensure_actor_not_banned(from_user_id)
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            cur = await conn.execute(
                """
                DELETE FROM friendships
                WHERE from_user_id = ? AND to_user_id = ? AND status = ?
                """,
                (from_user_id, to_user_id, _ST_BLOCKED),
            )
            await conn.commit()
            if cur.rowcount == 0:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Блок не найден")

    async def list_friends(self, user_id: int, limit: int = 200) -> list[FriendUserSnippet]:
        lim = max(1, min(limit, 500))
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            conn.row_factory = aiosqlite.Row
            async with conn.execute(
                """
                SELECT u.id, u.username, u.display_name, u.avatar_path,
                       u.account_status, u.ban_until, u.ban_reason, u.is_blocked
                FROM friendships f
                JOIN users u ON u.id = CASE
                    WHEN f.from_user_id = ? THEN f.to_user_id
                    ELSE f.from_user_id
                END
                WHERE f.status = ?
                  AND (f.from_user_id = ? OR f.to_user_id = ?)
                ORDER BY f.updated_at DESC
                LIMIT ?
                """,
                (user_id, _ST_ACCEPTED, user_id, user_id, lim),
            ) as cur:
                rows = await cur.fetchall()
        out_snippets: list[FriendUserSnippet] = []
        for r in rows:
            d = _row_to_dict(r)
            apply_avatar_fields(d)
            _apply_friend_ban_metadata(d)
            out_snippets.append(FriendUserSnippet.model_validate(d))
        return out_snippets

    async def list_incoming(self, user_id: int) -> list[FriendRequestItem]:
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            conn.row_factory = aiosqlite.Row
            async with conn.execute(
                """
                SELECT f.id AS request_id,
                       u.id AS peer_id, u.username, u.display_name, u.avatar_path,
                       u.account_status, u.ban_until, u.ban_reason, u.is_blocked
                FROM friendships f
                JOIN users u ON u.id = f.from_user_id
                WHERE f.to_user_id = ? AND f.status = ? AND u.is_blocked = 0
                ORDER BY f.created_at DESC
                """,
                (user_id, _ST_PENDING),
            ) as cur:
                rows = await cur.fetchall()
        out: list[FriendRequestItem] = []
        for r in rows:
            d = _row_to_dict(r)
            sn = {
                "id": int(d["peer_id"]),
                "username": d.get("username"),
                "display_name": d.get("display_name"),
                "avatar_path": d.get("avatar_path"),
                "account_status": d.get("account_status") or "active",
                "ban_until": d.get("ban_until"),
                "ban_reason": d.get("ban_reason"),
                "is_blocked": d.get("is_blocked", 0),
            }
            apply_avatar_fields(sn)
            _apply_friend_ban_metadata(sn)
            out.append(
                FriendRequestItem(
                    request_id=int(d["request_id"]),
                    user=FriendUserSnippet.model_validate(sn),
                )
            )
        return out

    async def list_outgoing(self, user_id: int) -> list[FriendRequestItem]:
        async with aiosqlite.connect(self._path) as conn:
            await conn.execute("PRAGMA foreign_keys = ON")
            conn.row_factory = aiosqlite.Row
            async with conn.execute(
                """
                SELECT f.id AS request_id,
                       u.id AS peer_id, u.username, u.display_name, u.avatar_path,
                       u.account_status, u.ban_until, u.ban_reason, u.is_blocked
                FROM friendships f
                JOIN users u ON u.id = f.to_user_id
                WHERE f.from_user_id = ? AND f.status = ? AND u.is_blocked = 0
                ORDER BY f.created_at DESC
                """,
                (user_id, _ST_PENDING),
            ) as cur:
                rows = await cur.fetchall()
        out: list[FriendRequestItem] = []
        for r in rows:
            d = _row_to_dict(r)
            sn = {
                "id": int(d["peer_id"]),
                "username": d.get("username"),
                "display_name": d.get("display_name"),
                "avatar_path": d.get("avatar_path"),
                "account_status": d.get("account_status") or "active",
                "ban_until": d.get("ban_until"),
                "ban_reason": d.get("ban_reason"),
                "is_blocked": d.get("is_blocked", 0),
            }
            apply_avatar_fields(sn)
            _apply_friend_ban_metadata(sn)
            out.append(
                FriendRequestItem(
                    request_id=int(d["request_id"]),
                    user=FriendUserSnippet.model_validate(sn),
                )
            )
        return out


async def get_status_response(db: Database, viewer_id: int, other_id: int) -> FriendStatusResponse:
    svc = FriendsService(db)
    d = await svc.get_status(viewer_id, other_id)
    return FriendStatusResponse(
        relation=str(d["relation"]),
        request_id=d.get("request_id"),
    )
