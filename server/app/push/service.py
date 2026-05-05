"""
Отправка push через Firebase Cloud Messaging HTTP v1 API.

Требуются переменные окружения:
- FCM_PROJECT_ID — идентификатор проекта Firebase (не секрет).
- FCM_ACCESS_TOKEN — OAuth2 access token со scope для FCM (короткоживущий;
  в проде обычно получают через service account / workload identity).

Без них отправка тихо пропускается (лог debug), чтобы не ломать обмен сообщениями.
"""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx

from app.database.database import Database

logger = logging.getLogger(__name__)

# Частые коды ошибок FCM для удаления «битого» токена из БД
_TOKEN_ERROR_MARKERS = ("UNREGISTERED", "INVALID_ARGUMENT", "NOT_FOUND", "registration-token-not-registered")


async def send_push_to_user(db: Database, user_id: int, title: str, body: str) -> None:
    """
    Доставляет уведомление всем зарегистрированным устройствам пользователя.
    Невалидные токены удаляются из user_push_tokens.
    """
    project_id = os.environ.get("FCM_PROJECT_ID", "").strip()
    access_token = os.environ.get("FCM_ACCESS_TOKEN", "").strip()
    if not project_id or not access_token:
        logger.debug(
            "FCM: пропуск отправки (не заданы FCM_PROJECT_ID / FCM_ACCESS_TOKEN), user_id=%s",
            user_id,
        )
        return

    tokens = await db.get_user_push_tokens(user_id)
    if not tokens:
        return

    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; charset=utf-8",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        for device_token in tokens:
            payload = _build_v1_message(device_token, title, body)
            try:
                resp = await client.post(url, headers=headers, json=payload)
            except httpx.RequestError as e:
                logger.warning("FCM: сетевой сбой для user_id=%s: %s", user_id, e)
                continue

            if resp.status_code == 200:
                continue

            err_text = resp.text
            logger.warning(
                "FCM: ошибка %s для user_id=%s: %s",
                resp.status_code,
                user_id,
                err_text[:500],
            )
            if resp.status_code in (400, 404) and _should_drop_token(err_text):
                await db.remove_push_token(device_token)
                logger.info("FCM: удалён невалидный токен из БД")


def _should_drop_token(err_body: str) -> bool:
    """Эвристика: ответ FCM указывает на мёртвый registration token."""
    upper = err_body.upper()
    return any(m in upper or m in err_body for m in _TOKEN_ERROR_MARKERS)


def _build_v1_message(device_token: str, title: str, body: str) -> dict[str, Any]:
    """Тело запроса messages:send (HTTP v1)."""
    return {
        "message": {
            "token": device_token,
            "notification": {
                "title": title,
                "body": body,
            },
        }
    }
