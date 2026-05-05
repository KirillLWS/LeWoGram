"""
Создание жалоб и валидация целей (пользователь / сообщение).
"""

from __future__ import annotations

from fastapi import HTTPException, status

from app.database.db_reports import (
    create_report,
)
from app.database.database import Database


async def submit_report(
    db: Database,
    *,
    reporter_id: int,
    target_type: str,
    target_user_id: int | None,
    target_message_id: int | None,
    reason_code: str,
    description: str,
) -> int:
    tt = target_type.strip().lower()
    uid = target_user_id
    mid = target_message_id

    if tt in ("user", "profile"):
        if uid is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="target_user_id обязателен для target_type user/profile",
            )
        if mid is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="target_message_id не используется для user/profile",
            )
        target = await db.get_user_public_profile(uid)
        if target is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
        if uid == reporter_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Нельзя пожаловаться на себя")

    elif tt == "message":
        if mid is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="target_message_id обязателен для target_type message",
            )
        msg = await db.get_message_by_id(mid)
        if msg is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Сообщение не найдено")
        chat_id = int(msg["chat_id"])
        member = await db.get_chat_member(chat_id, reporter_id)
        if member is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Нет доступа к чату этого сообщения",
            )
        sender_id = msg.get("sender_id")
        if sender_id is not None and int(sender_id) == reporter_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Нельзя пожаловаться на своё сообщение")
        if sender_id is not None:
            uid = int(sender_id)

    rid = await create_report(
        db,
        reporter_id=reporter_id,
        target_type=tt,
        target_user_id=uid,
        target_message_id=mid,
        reason_code=reason_code,
        description=description,
    )
    return rid
