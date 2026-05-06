"""
Состояние блокировки аккаунта: временная/постоянная, авто-снятие истёкшего temp.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException, status

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


async def ensure_not_banned(db: Database, user: dict[str, Any] | None) -> dict[str, Any] | None:
    """
    Единая точка для pre-auth и auth: актуализирует temp-бан и бросает HTTP 403 с телом account_blocked.
    Возвращает пользователя, если активен; None только если на входе user is None.
    """
    if user is None:
        return None
    u = await materialize_user_ban(db, user)
    if u is None:
        return None
    payload = account_block_payload(u)
    if payload is not None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=payload)
    return u


async def materialize_user_ban(db: Database, user: dict[str, Any] | None) -> dict[str, Any] | None:
    """
    Снимает истёкший temp_banned в БД и возвращает актуальную строку пользователя.

    temp_banned без даты окончания (ban_until пустой) не снимается автоматически
    (нет условия «NULL истёк» — постоянный по смыслу блок до смены статуса в БД).
    """
    if user is None:
        return None
    uid = int(user["id"])
    st = _status(user)
    if st != "temp_banned":
        return user
    bu = user.get("ban_until")
    if bu is None or str(bu).strip() == "":
        return user
    end = _parse_ban_until(str(bu))
    if end is None:
        return user
    if datetime.now(timezone.utc) >= end:
        await db.clear_expired_temp_ban(uid)
        return await db.get_user_by_id(uid)
    return user


def account_block_payload(user: dict[str, Any]) -> dict[str, Any] | None:
    """
    Если вход/API для этого пользователя запрещён — тело ответа HTTP 403 (без обёртки detail).

    Формат фиксированный: code, ban_until, reason, is_permanent.
    """
    st = _status(user)
    if st == "active":
        return None
    reason = str(user.get("ban_reason") or "").strip() or "Аккаунт заблокирован"
    if st == "banned":
        return {
            "code": "account_blocked",
            "reason": reason,
            "ban_until": None,
            "is_permanent": True,
        }
    if st == "temp_banned":
        bu = user.get("ban_until")
        bu_out: str | None
        if bu is None:
            bu_out = None
        else:
            s = str(bu).strip()
            bu_out = s if s else None
        return {
            "code": "account_blocked",
            "reason": reason,
            "ban_until": bu_out,
            "is_permanent": False,
        }
    return None
