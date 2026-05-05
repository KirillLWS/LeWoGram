"""
HTTP API регистрации FCM-токена авторизованным пользователем.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.push.schemas import PushTokenBody

router = APIRouter(tags=["push"])


@router.post("/token")
async def register_push_token(
    body: PushTokenBody,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    """
    Сохраняет FCM registration token для текущего пользователя.
    Тот же endpoint можно вызывать повторно при обновлении токена на клиенте.
    """
    uid = int(user["id"])
    await db.save_user_push_token(uid, body.token)
    return {"ok": True}
