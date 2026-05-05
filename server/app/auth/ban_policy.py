"""
Состояние блокировки аккаунта: временная/постоянная, авто-снятие истёкшего temp.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.database.database import Database


def _parse_ban_until(raw: str | None) -> datetime | None:
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    if len(s) >= 19 and s[4] == "-" and s[7] == "-":
        try:
            dt = datetime.strptime(s[:19], "%Y-%m-%d %H:%M:%S")
            return dt.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except ValueError:
        return None


def _status(user: dict[str, Any]) -> str:
    raw = user.get("account_status")
    if raw is None or str(raw).strip() == "":
        return "banned" if int(user.get("is_blocked", 0)) else "active"
    s = str(raw).strip().lower()
    if s in ("active", "banned", "temp_banned"):
        return s
    return "banned" if int(user.get("is_blocked", 0)) else "active"


def remaining_seconds_until(ban_until: str | None) -> int | None:
    end = _parse_ban_until(ban_until)
    if end is None:
        return None
    now = datetime.now(timezone.utc)
    sec = int((end - now).total_seconds())
    return max(0, sec)


async def materialize_user_ban(db: Database, user: dict[str, Any] | None) -> dict[str, Any] | None:
    """
    Снимает истёкший temp_banned в БД и возвращает актуальную строку пользователя.
    """
    if user is None:
        return None
    uid = int(user["id"])
    st = _status(user)
    if st != "temp_banned":
        return user
    bu = user.get("ban_until")
    if bu is None or str(bu).strip() == "":
        await db.clear_expired_temp_ban(uid)
        return await db.get_user_by_id(uid)
    end = _parse_ban_until(str(bu))
    if end is None:
        await db.clear_expired_temp_ban(uid)
        return await db.get_user_by_id(uid)
    if datetime.now(timezone.utc) >= end:
        await db.clear_expired_temp_ban(uid)
        return await db.get_user_by_id(uid)
    return user


def account_block_payload(user: dict[str, Any]) -> dict[str, Any] | None:
    """
    Если вход/API для этого пользователя запрещён — тело для HTTP 403 (как detail).
    Иначе None.
    """
    st = _status(user)
    if st == "active":
        return None
    reason = str(user.get("ban_reason") or "").strip() or "Аккаунт заблокирован"
    if st == "banned":
        return {
            "code": "account_blocked",
            "account_status": "banned",
            "reason": reason,
            "ban_until": None,
            "remaining_seconds": None,
        }
    if st == "temp_banned":
        rem = remaining_seconds_until(str(user.get("ban_until") or ""))
        return {
            "code": "account_blocked",
            "account_status": "temp_banned",
            "reason": reason,
            "ban_until": user.get("ban_until"),
            "remaining_seconds": rem,
        }
    return None
