"""
HTTP API чатов и текстовых сообщений (только для авторизованных пользователей).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.messages.schemas import (
    ChatResponse,
    CreateDirectChatRequest,
    CreateGroupChatRequest,
    MarkReadRequest,
    MessageResponse,
    PatchChatRequest,
    SendTextMessageRequest,
)
from app.messages import service as messages_service

router = APIRouter()


@router.post("/chats/direct", response_model=ChatResponse)
async def create_direct_chat_endpoint(
    body: CreateDirectChatRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> ChatResponse:
    """Создать (или вернуть существующий) direct-чат с другим пользователем."""
    uid = int(user["id"])
    return await messages_service.create_direct_chat(db, uid, body)


@router.post("/chats/group", response_model=ChatResponse)
async def create_group_chat_endpoint(
    body: CreateGroupChatRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> ChatResponse:
    """Создать групповой чат."""
    uid = int(user["id"])
    return await messages_service.create_group_chat(db, uid, body)


@router.get("/support/chat", response_model=ChatResponse)
async def get_support_chat(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> ChatResponse:
    """Глобальный чат поддержки (все пользователи пишут; ответы по цитате — только staff)."""
    uid = int(user["id"])
    return await messages_service.open_support_chat(db, uid)


@router.get("/chats", response_model=list[ChatResponse])
async def list_chats_endpoint(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[ChatResponse]:
    """Список чатов текущего пользователя."""
    uid = int(user["id"])
    return await messages_service.list_user_chats(db, uid)


@router.patch("/chats/{chat_id}", response_model=ChatResponse)
async def patch_chat_endpoint(
    chat_id: int,
    body: PatchChatRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> ChatResponse:
    """Переименовать чат (title; description — опционально)."""
    uid = int(user["id"])
    return await messages_service.patch_chat(db, uid, chat_id, body)


@router.post("/send-text", response_model=MessageResponse)
async def send_text_endpoint(
    body: SendTextMessageRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> MessageResponse:
    """Отправить текстовое сообщение."""
    uid = int(user["id"])
    return await messages_service.send_text_message(db, uid, body)


@router.post("/mark-read")
async def mark_read_endpoint(
    body: MarkReadRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict[str, bool]:
    """Отметить сообщения в чате прочитанными до указанного id включительно."""
    uid = int(user["id"])
    return await messages_service.mark_chat_as_read(db, uid, body)


@router.get("/{chat_id}", response_model=list[MessageResponse])
async def list_messages_endpoint(
    chat_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
    limit: int = Query(50, ge=1, le=200),
    before_id: int | None = Query(None, description="Сообщения с id строго меньше этого (подгрузка истории)"),
) -> list[MessageResponse]:
    """История текстовых сообщений чата."""
    uid = int(user["id"])
    return await messages_service.list_chat_messages(db, uid, chat_id, limit, before_id)
