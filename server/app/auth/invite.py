"""
Инвайт-ссылки: генерация токена, создание записи в БД, валидация перед регистрацией.
"""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status

from app.database.database import Database


def generate_invite_token() -> str:
    """Криптостойкая случайная строка для ссылки (≈43 символа base64url)."""
    return secrets.token_urlsafe(32)


async def create_invite(
    db: Database,
    created_by_admin_id: int,
    expires_hours: int = 48,
    note: str | None = None,
) -> str:
    """
    Создаёт инвайт в БД и возвращает токен (его передают в ссылке / вводе при регистрации).
    При редкой коллизии UNIQUE на token — повторяет генерацию.
    """
    import aiosqlite

    for _ in range(5):
        token = generate_invite_token()
        expires = datetime.now(timezone.utc) + timedelta(hours=expires_hours)
        expires_at = expires.strftime("%Y-%m-%d %H:%M:%S")
        try:
            await db.create_invite(
                token,
                created_by_admin_id,
                expires_at,
                note=note,
            )
            return token
        except aiosqlite.IntegrityError:
            continue
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Не удалось сгенерировать уникальный инвайт, попробуйте снова",
    )


async def validate_invite(db: Database, token: str) -> None:
    """
    Проверяет инвайт. При ошибке бросает HTTPException с русским detail.
    Успех — просто return (без True, чтобы не путать с исключениями).
    """
    raw = token.strip()
    if not raw:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Пустой инвайт")

    row = await db.get_invite_by_token(raw)
    if row is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Инвайт не найден")

    if not int(row.get("is_active", 0)):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Инвайт неактивен")

    if row.get("used_at") is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Инвайт уже использован")

    exp = row.get("expires_at")
    if exp:
        exp_s = str(exp).strip()
        exp_dt: datetime | None = None
        try:
            exp_dt = datetime.strptime(exp_s, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        except ValueError:
            try:
                exp_dt = datetime.fromisoformat(exp_s.replace("Z", "+00:00"))
                if exp_dt.tzinfo is None:
                    exp_dt = exp_dt.replace(tzinfo=timezone.utc)
            except ValueError as e:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Некорректная дата истечения инвайта",
                ) from e
        if exp_dt is not None and datetime.now(timezone.utc) > exp_dt:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Срок действия инвайта истёк",
            )


async def use_invite(db: Database, token: str, used_by_user_id: int) -> None:
    """Помечает инвайт использованным; при сбое — HTTP 409."""
    ok = await db.use_invite(token.strip(), used_by_user_id)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Не удалось зафиксировать использование инвайта (уже использован или отозван)",
        )
