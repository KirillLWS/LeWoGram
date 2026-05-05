"""
Бизнес-логика авторизации: пароли (bcrypt), JWT, регистрация, вход, смена пароля.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any

import aiosqlite
import bcrypt
import jwt
from fastapi import HTTPException, status

from app.auth import invite as invite_module
from app.auth.schemas import ChangePasswordRequest, LoginRequest, RegisterRequest, TokenResponse
from app.config import ACCESS_TOKEN_EXPIRE_MINUTES, SECRET_KEY
from app.database.database import Database

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


async def register_user(
    db: Database,
    body: RegisterRequest,
    client_ip: str | None,
) -> TokenResponse:
    """Регистрация: инвайт → пользователь → настройки → отметить инвайт → аналитика → JWT."""
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

    try:
        user_id = await db.create_user(login_clean, ph, fp, display_name=dn)
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

    token = create_access_token(user_id, login_clean)
    return TokenResponse(access_token=token)


async def login_user(
    db: Database,
    body: LoginRequest,
    client_ip: str | None,
) -> TokenResponse:
    """Вход: проверки, журнал, аналитика, JWT."""
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
    stored_fp = user.get("device_fingerprint") or ""

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

    if stored_fp:
        if stored_fp != fp:
            await db.add_login_log(uid, fp, client_ip, False)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Неверный логин или пароль",
            )
    else:
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

    return TokenResponse(access_token=create_access_token(uid, user["login"]))


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
