"""Бизнес-логика запросов на смену / добавление устройства."""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import aiosqlite
from fastapi import HTTPException, status

from app.auth import ban_policy
from app.auth.service import (
    create_access_token,
    hash_refresh_token,
    new_refresh_token_plain,
    refresh_expires_at_utc_str,
    verify_password,
)
from app.config import ACCESS_TOKEN_EXPIRE_MINUTES
from app.database import db_auth_sessions, db_device_transfer
from app.database.db_roles import (
    OPERATIONAL_STAFF_ROLES,
    list_user_ids_with_any_role,
)
from app.database.database import Database
from app.device_transfer.schemas import (
    DeviceTransferPollOut,
    DeviceTransferRequestCreate,
    DeviceTransferRequestOut,
)
from app.push.service import send_push_to_user

logger = logging.getLogger(__name__)

_STAFF_TUPLE: tuple[str, ...] = tuple(sorted(OPERATIONAL_STAFF_ROLES))


def _norm_phrase(phrase: str) -> str:
    return " ".join(phrase.strip().lower().split())


def _dtr_expires_str() -> str:
    return (datetime.now(timezone.utc) + timedelta(hours=24)).strftime("%Y-%m-%d %H:%M:%S")


def _parse_expires_utc(expires_at: str | None) -> datetime | None:
    if not expires_at or not str(expires_at).strip():
        return None
    try:
        return datetime.strptime(str(expires_at).strip(), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _is_expired(expires_at: str | None) -> bool:
    dt = _parse_expires_utc(expires_at)
    if dt is None:
        return True
    return datetime.now(timezone.utc) > dt


def _gen_short_code() -> str:
    return str(secrets.randbelow(900_000) + 100_000)


async def _verify_actor_admin(db: Database, actor_id: int) -> None:
    if not await db.rbac_user_has_any_role(actor_id, OPERATIONAL_STAFF_ROLES):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Нужна роль владельца, главного администратора или администратора",
        )


async def _notify_admins(db: Database, title: str, body: str) -> None:
    ids = await list_user_ids_with_any_role(db.db_path, _STAFF_TUPLE)
    for uid in ids:
        await send_push_to_user(db, uid, title, body)


async def create_request(
    db: Database,
    body: DeviceTransferRequestCreate,
    client_ip: str | None,
) -> DeviceTransferRequestOut:
    pw = (body.password or "").strip() if body.password else ""
    phrase = (body.recovery_phrase or "").strip() if body.recovery_phrase else ""
    if not pw and not phrase:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Укажите password или recovery_phrase",
        )
    if pw and phrase:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Укажите только один способ: пароль или фразу восстановления",
        )

    login = body.login.strip()
    user = await db.get_user_by_login(login)
    if user is None:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Неверный логин или проверочные данные",
        )

    uid = int(user["id"])
    user = await ban_policy.ensure_not_banned(db, user)

    ok = False
    if pw:
        ok = verify_password(pw, str(user["password_hash"]))
    else:
        phash = user.get("recovery_phrase_hash")
        if not phash:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Фраза восстановления для этого аккаунта не задана",
            )
        ok = verify_password(_norm_phrase(phrase), str(phash))

    fp = body.device_fingerprint.strip()
    if not ok:
        await db.add_login_log(uid, fp, client_ip, False)
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Неверный логин или проверочные данные",
        )

    code = ""
    h = ""
    for _ in range(20):
        code = _gen_short_code()
        h = db_device_transfer.hash_short_code(code)

        async with aiosqlite.connect(db.db_path) as conn:
            async with conn.execute(
                """
                SELECT 1 FROM device_transfer_requests
                WHERE short_code_hash = ? AND status = 'pending'
                LIMIT 1
                """,
                (h,),
            ) as cur:
                exists = (await cur.fetchone()) is not None
        if not exists:
            break
    else:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Не удалось сгенерировать код",
        )

    exp = _dtr_expires_str()
    rid = await db_device_transfer.insert_request(
        db.db_path,
        user_id=uid,
        mode=body.mode,
        req_device_fingerprint=fp,
        req_device_model=body.device_model,
        req_device_os=body.device_os,
        req_ip_address=client_ip,
        req_geo_lat=body.geo_lat,
        req_geo_lng=body.geo_lng,
        req_geo_accuracy_m=body.geo_accuracy_m,
        reason=body.reason.strip(),
        short_code=code,
        short_code_hash=h,
        expires_at=exp,
    )

    label = str(user.get("login") or uid)
    await _notify_admins(
        db,
        "Новый запрос на устройство",
        f"Пользователь {label}. Откройте Админ → Смена устройства (запрос #{rid}).",
    )

    await db.add_login_log(uid, fp, client_ip, True)

    return DeviceTransferRequestOut(id=rid, short_code=code, expires_at=exp)


async def cancel(db: Database, user_id: int, request_id: int) -> dict[str, bool]:
    actor = await db.get_user_by_id(user_id)
    if actor is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Пользователь не найден")
    await ban_policy.ensure_not_banned(db, actor)
    ok = await db_device_transfer.update_status_cancelled(db.db_path, request_id, user_id)
    if not ok:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Запрос не найден или уже не в статусе ожидания",
        )
    return {"ok": True}


async def deny(db: Database, actor_id: int, request_id: int, note: str | None) -> dict[str, bool]:
    await _verify_actor_admin(db, actor_id)
    admin_row = await db.get_user_by_id(actor_id)
    if admin_row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Пользователь не найден")
    await ban_policy.ensure_not_banned(db, admin_row)
    row = await db_device_transfer.get_request_by_id(db.db_path, request_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Запрос не найден")
    if row["status"] != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "Запрос уже обработан")
    if _is_expired(row.get("expires_at")):
        raise HTTPException(status.HTTP_410_GONE, "Срок запроса истёк")

    ok = await db_device_transfer.update_status_denied(
        db.db_path,
        request_id,
        decided_by=actor_id,
        note=note,
    )
    if not ok:
        raise HTTPException(status.HTTP_409_CONFLICT, "Не удалось отклонить запрос")

    uid = int(row["user_id"])
    await send_push_to_user(
        db,
        uid,
        "Запрос на устройство отклонён",
        (note or "Администратор отклонил запрос.").strip()[:500],
    )
    return {"ok": True}


async def approve(
    db: Database,
    actor_id: int,
    request_id: int,
    *,
    revoke_old: bool,
) -> dict[str, bool]:
    await _verify_actor_admin(db, actor_id)
    admin_row = await db.get_user_by_id(actor_id)
    if admin_row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Пользователь не найден")
    await ban_policy.ensure_not_banned(db, admin_row)
    row = await db_device_transfer.get_request_by_id(db.db_path, request_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Запрос не найден")
    if row["status"] != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "Запрос уже обработан")
    if _is_expired(row.get("expires_at")):
        raise HTTPException(status.HTTP_410_GONE, "Срок запроса истёк")

    uid = int(row["user_id"])
    user = await db.get_user_by_id(uid)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Пользователь не найден")

    await ban_policy.ensure_not_banned(db, user)

    login = str(user["login"])
    req_fp = str(row["req_device_fingerprint"]).strip()

    plain = new_refresh_token_plain()
    rh = hash_refresh_token(plain)
    sess_exp = refresh_expires_at_utc_str()

    if revoke_old:
        await db_auth_sessions.revoke_all_sessions_for_user(db.db_path, uid)

    await db_auth_sessions.insert_session(
        db.db_path,
        user_id=uid,
        refresh_token_hash=rh,
        device_fingerprint=req_fp,
        device_model=row.get("req_device_model"),
        device_os=row.get("req_device_os"),
        ip_address=row.get("req_ip_address"),
        expires_at=sess_exp,
    )

    access = create_access_token(uid, login)

    ok = await db_device_transfer.update_status_approved(
        db.db_path,
        request_id,
        decided_by=actor_id,
        revoke_old=revoke_old,
        access_token=access,
        refresh_token=plain,
    )
    if not ok:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Состояние запроса изменилось; сессия могла быть создана — обратитесь к администратору",
        )

    await send_push_to_user(
        db,
        uid,
        "Устройство подтверждено",
        "На новом устройстве введите 6-значный код и дождитесь входа.",
    )
    return {"ok": True}


async def list_pending_for_admin(db: Database, actor_id: int) -> list[dict[str, Any]]:
    await _verify_actor_admin(db, actor_id)
    raw = await db_device_transfer.list_pending_all(db.db_path)
    return raw if isinstance(raw, list) else []


async def admin_overview(db: Database, actor_id: int) -> dict[str, Any]:
    """Активные pending и история для UI администратора."""
    await _verify_actor_admin(db, actor_id)
    pending = await db_device_transfer.list_pending_all(db.db_path)
    history = await db_device_transfer.list_admin_history(db.db_path)
    return {
        "pending": pending if isinstance(pending, list) else [],
        "history": history if isinstance(history, list) else [],
    }


async def list_my_requests(db: Database, user_id: int) -> dict[str, Any]:
    rows = await db_device_transfer.list_my_requests(db.db_path, user_id)
    if not isinstance(rows, list):
        rows = []
    pending: list[dict[str, Any]] = []
    history: list[dict[str, Any]] = []
    for r in rows:
        st = str(r.get("status") or "").strip().lower()
        if st == "pending":
            pending.append(r)
        else:
            history.append(r)
    return {"pending": pending, "history": history}


async def poll(db: Database, request_id: int, code_plain: str) -> DeviceTransferPollOut:
    code_plain = code_plain.strip()
    if len(code_plain) != 6 or not code_plain.isdigit():
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный код")

    ch = db_device_transfer.hash_short_code(code_plain)
    row = await db_device_transfer.fetch_for_poll_by_id(db.db_path, request_id, ch)
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный код или запрос")

    st = str(row["status"])
    if st == "pending" and _is_expired(row.get("expires_at")):
        return DeviceTransferPollOut(status="expired")

    if st == "pending":
        return DeviceTransferPollOut(status="pending")

    if st == "denied":
        return DeviceTransferPollOut(
            status="denied",
            reason=row.get("decision_note"),
        )

    if st in ("expired", "cancelled"):
        return DeviceTransferPollOut(status=st)

    if st != "approved":
        return DeviceTransferPollOut(status=st)

    acc = row.get("poll_access_token")
    ref = row.get("poll_refresh_token")
    if acc and ref:
        await db_device_transfer.mark_tokens_consumed(db.db_path, request_id)
        return DeviceTransferPollOut(
            status="approved",
            access_token=str(acc),
            refresh_token=str(ref),
            expires_in=int(ACCESS_TOKEN_EXPIRE_MINUTES * 60),
        )

    raise HTTPException(
        status.HTTP_410_GONE,
        "Токены уже получены на этом устройстве",
    )
