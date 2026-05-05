"""
Бизнес-логика авторизации: пароли (bcrypt), JWT, регистрация, вход, смена пароля.
"""

from __future__ import annotations

import hashlib
import json
import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import aiosqlite
import bcrypt
import jwt
from fastapi import HTTPException, status
from mnemonic import Mnemonic

from app.auth import invite as invite_module
from app.auth.schemas import (
    ChangePasswordRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    RegisterResponse,
    TokenResponse,
)
from app.config import ACCESS_TOKEN_EXPIRE_MINUTES, REFRESH_TOKEN_EXPIRE_DAYS, SECRET_KEY
from app.database import db_auth_sessions
from app.database.database import Database
from app.device_transfer.schemas import (
    DeviceTransferRequestOut,
    RecoverInitRequest,
)

logger = logging.getLogger(__name__)

JWT_ALGORITHM = "HS256"


def _normalize_jwt_string(raw: str) -> str:
    """
    Убирает пробелы и повторяющийся префикс «Bearer ».
    В Swagger «Authorize» часто вводят уже с «Bearer …», а UI добавляет второй — получается
    «Bearer Bearer eyJ…» в credentials.credentials, что не является валидным JWT.
    """
    t = (raw or "").strip()
    while t.lower().startswith("bearer "):
        t = t[7:].strip()
    return t


def hash_password(password: str) -> str:
    """Хэш пароля для хранения в БД (bcrypt)."""
    pwd = password.encode("utf-8")
    if len(pwd) > 72:
        pwd = pwd[:72]
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(pwd, salt).decode("ascii")


def verify_password(plain: str, hashed: str) -> bool:
    """Проверка пароля против сохранённого bcrypt-хэша."""
    try:
        p = plain.encode("utf-8")
        if len(p) > 72:
            p = p[:72]
        h = hashed.encode("ascii")
        return bool(bcrypt.checkpw(p, h))
    except (ValueError, TypeError):
        return False


def create_access_token(user_id: int, login: str) -> str:
    """JWT access: sub = user id (строка), login, exp (UTC datetime → PyJWT сам в numericdate)."""
    now = datetime.now(timezone.utc)
    exp = now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload: dict[str, Any] = {
        "sub": str(user_id),
        "login": str(login),
        "exp": exp,
        "iat": now,
    }
    # PyJWT: encode/decode и PyJWTError — одна библиотека `import jwt` (пакет PyJWT).
    return jwt.encode(payload, SECRET_KEY, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict[str, Any] | None:
    """Декодирование JWT (PyJWT); при любой ошибке — None (без исключений наружу)."""
    token_clean = _normalize_jwt_string(token)
    if not token_clean:
        return None
    try:
        return jwt.decode(
            token_clean,
            SECRET_KEY,
            algorithms=[JWT_ALGORITHM],
        )
    except jwt.PyJWTError as e:
        logger.debug("JWT decode failed: %s", e)
        return None


def hash_refresh_token(plain: str) -> str:
    """SHA-256 хеш refresh-токена для хранения в БД."""
    return hashlib.sha256(plain.strip().encode("utf-8")).hexdigest()


def new_refresh_token_plain() -> str:
    return secrets.token_urlsafe(48)


def refresh_expires_at_utc_str() -> str:
    return (
        datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    ).strftime("%Y-%m-%d %H:%M:%S")


async def _issue_token_pair(
    db: Database,
    *,
    user_id: int,
    login: str,
    device_fingerprint: str,
    device_model: str | None,
    device_os: str | None,
    client_ip: str | None,
) -> TokenResponse:
    plain = new_refresh_token_plain()
    h = hash_refresh_token(plain)
    exp = refresh_expires_at_utc_str()
    await db_auth_sessions.insert_session(
        db.db_path,
        user_id=user_id,
        refresh_token_hash=h,
        device_fingerprint=device_fingerprint.strip(),
        device_model=device_model,
        device_os=device_os,
        ip_address=client_ip,
        expires_at=exp,
    )
    access = create_access_token(user_id, login)
    return TokenResponse(
        access_token=access,
        refresh_token=plain,
        expires_in=int(ACCESS_TOKEN_EXPIRE_MINUTES * 60),
    )


async def refresh_access_token(
    db: Database,
    body: RefreshRequest,
    client_ip: str | None,
) -> TokenResponse:
    old_h = hash_refresh_token(body.refresh_token)
    new_plain = new_refresh_token_plain()
    new_h = hash_refresh_token(new_plain)
    exp = refresh_expires_at_utc_str()
    meta = await db_auth_sessions.rotate_refresh_session(
        db.db_path,
        old_h,
        new_refresh_hash=new_h,
        new_expires_at=exp,
        client_ip=client_ip,
    )
    if meta is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительный или просроченный refresh-токен",
        )
    uid = int(meta["user_id"])
    login = str(meta["login"])
    access = create_access_token(uid, login)
    return TokenResponse(
        access_token=access,
        refresh_token=new_plain,
        expires_in=int(ACCESS_TOKEN_EXPIRE_MINUTES * 60),
    )


async def logout_with_refresh(db: Database, body: LogoutRequest) -> dict[str, bool]:
    await db_auth_sessions.revoke_session_by_refresh_hash(
        db.db_path,
        hash_refresh_token(body.refresh_token),
    )
    return {"ok": True}


async def logout_all_sessions_for_user(db: Database, user_id: int) -> dict[str, int]:
    n = await db_auth_sessions.revoke_all_sessions_for_user(db.db_path, user_id)
    return {"revoked": n}


async def list_user_auth_sessions(db: Database, user_id: int) -> list[dict[str, Any]]:
    return await db_auth_sessions.list_active_sessions(db.db_path, user_id)


async def revoke_user_auth_session(db: Database, user_id: int, session_id: int) -> None:
    ok = await db_auth_sessions.revoke_session_by_id(db.db_path, session_id, user_id)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сессия не найдена",
        )


async def get_current_user(token: str, db: Database) -> dict[str, Any]:
    """
    Загружает пользователя по Bearer-токену.
    HTTP 401 если токен невалиден или пользователь не найден / заблокирован.
    """
    payload = decode_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительный или просроченный токен",
        )
    try:
        uid = int(payload.get("sub", ""))
    except (TypeError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительный токен",
        )

    user = await db.get_user_by_id(uid)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Пользователь не найден",
        )
    if int(user.get("is_blocked", 0)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Аккаунт заблокирован",
        )
    return user


def _norm_recovery_phrase(phrase: str) -> str:
    return " ".join(phrase.strip().lower().split())


def _generate_recovery_phrase() -> str:
    return Mnemonic("english").generate(strength=128)


async def register_user(
    db: Database,
    body: RegisterRequest,
    client_ip: str | None,
) -> RegisterResponse:
    """Регистрация: инвайт → пользователь → настройки → отметить инвайт → аналитика → JWT + фраза."""
    await invite_module.validate_invite(db, body.invite_token)

    login_clean = body.login.strip()
    if await db.get_user_by_login(login_clean):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Этот логин уже занят",
        )

    ph = hash_password(body.password)
    fp = body.device_fingerprint.strip()
    dn = body.display_name.strip() if body.display_name else None
    recovery_phrase = _generate_recovery_phrase()
    r_hash = hash_password(_norm_recovery_phrase(recovery_phrase))

    try:
        user_id = await db.create_user(
            login_clean,
            ph,
            fp,
            display_name=dn,
            recovery_phrase_hash=r_hash,
        )
    except aiosqlite.IntegrityError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Этот логин уже занят",
        ) from None

    await invite_module.use_invite(db, body.invite_token, user_id)
    await db.create_user_settings(user_id)

    await db.log_event(
        user_id,
        "registered",
        json.dumps({"login": login_clean}, ensure_ascii=False),
        client_ip,
        None,
    )

    pair = await _issue_token_pair(
        db,
        user_id=user_id,
        login=login_clean,
        device_fingerprint=fp,
        device_model=None,
        device_os=None,
        client_ip=client_ip,
    )
    return RegisterResponse(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
        token_type=pair.token_type,
        recovery_phrase=recovery_phrase,
    )


async def login_user(
    db: Database,
    body: LoginRequest,
    client_ip: str | None,
) -> TokenResponse | dict[str, Any]:
    """Вход: проверки, журнал, аналитика, JWT или тело для 202 при новом устройстве."""
    login_clean = body.login.strip()
    fp = body.device_fingerprint.strip()

    user = await db.get_user_by_login(login_clean)
    if user is None:
        await db.add_login_log(None, fp, client_ip, False)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный логин или пароль",
        )

    uid = int(user["id"])

    if int(user.get("is_blocked", 0)):
        await db.add_login_log(uid, fp, client_ip, False)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Аккаунт заблокирован",
        )

    if not verify_password(body.password, user["password_hash"]):
        await db.add_login_log(uid, fp, client_ip, False)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный логин или пароль",
        )

    has_any = await db_auth_sessions.user_has_any_active_session(db.db_path, uid)
    has_fp_match = await db_auth_sessions.user_has_active_session_with_fingerprint(
        db.db_path,
        uid,
        fp,
    )
    if has_any and not has_fp_match:
        await db.add_login_log(uid, fp, client_ip, False)
        return {"must_request_transfer": True, "reason": "new_device"}

    await db.bind_user_fingerprint_if_missing(uid, fp)

    await db.update_last_seen(uid)
    await db.update_user_device(uid, body.device_model, body.device_os)
    await db.add_login_log(uid, fp, client_ip, True)

    await db.log_event(
        uid,
        "login",
        json.dumps({"login": login_clean}, ensure_ascii=False),
        client_ip,
        body.device_model,
    )

    return await _issue_token_pair(
        db,
        user_id=uid,
        login=str(user["login"]),
        device_fingerprint=fp,
        device_model=body.device_model,
        device_os=body.device_os,
        client_ip=client_ip,
    )


async def recover_init(
    db: Database,
    body: RecoverInitRequest,
    client_ip: str | None,
) -> DeviceTransferRequestOut:
    """Создать pending-запрос смены устройства по фразе восстановления (без JWT)."""
    from app.device_transfer.schemas import DeviceTransferRequestCreate
    from app.device_transfer import service as dtr_service

    cri = DeviceTransferRequestCreate(
        login=body.login,
        password=None,
        recovery_phrase=body.phrase,
        mode="add",
        device_fingerprint=body.device_fingerprint,
        device_model=body.device_model,
        device_os=body.device_os,
        reason="Восстановление по контрольной фразе",
    )
    return await dtr_service.create_request(db, cri, client_ip)


async def change_password(
    db: Database,
    user_id: int,
    body: ChangePasswordRequest,
) -> dict[str, bool]:
    """Смена пароля при знании старого; снимает флаг must_change_password."""
    user = await db.get_user_by_id(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    if not verify_password(body.old_password, user["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Неверный текущий пароль",
        )

    new_hash = hash_password(body.new_password)
    await db.update_user_password(user_id, new_hash)
    return {"ok": True}
