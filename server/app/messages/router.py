"""
HTTP API чатов и текстовых сообщений (только для авторизованных пользователей).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from pydantic import BaseModel, Field

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
from app.messages import support_tickets


class CreateSupportTicketRequest(BaseModel):
    subject: str | None = Field(default=None, max_length=120)


class TicketStateRequest(BaseModel):
    state: str = Field(..., pattern="^(closed|reopen)$")


class TicketFinalizeRequest(BaseModel):
    action: str = Field(..., pattern="^(close|reopen)$")

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


@router.post("/support/tickets")
async def create_support_ticket_endpoint(
    body: CreateSupportTicketRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    """Создать новый тикет поддержки. Все админы и владелец автоматически получают доступ."""
    uid = int(user["id"])
    return await support_tickets.create_support_ticket(db, uid, subject=body.subject)


@router.get("/support/tickets/mine")
async def list_my_support_tickets_endpoint(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    uid = int(user["id"])
    rows = await support_tickets.list_my_tickets(db, uid)
    return {"data": rows}


@router.get("/support/tickets/all")
async def list_all_support_tickets_endpoint(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    """Список всех тикетов (для staff: admin / chief_admin / owner)."""
    from app.database.db_roles import list_user_roles, OPERATIONAL_STAFF_ROLES
    uid = int(user["id"])
    roles = {r.lower() for r in await list_user_roles(db.db_path, uid)}
    if not (roles & OPERATIONAL_STAFF_ROLES):
        from fastapi import HTTPException, status as st
        raise HTTPException(
            status_code=st.HTTP_403_FORBIDDEN,
            detail="Недостаточно прав",
        )
    rows = await support_tickets.list_all_tickets_for_staff(db)
    return {"data": rows}


@router.get("/support/tickets/{chat_id}")
async def get_support_ticket(
    chat_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    uid = int(user["id"])
    t = await support_tickets.get_ticket_for_user(db, chat_id, uid)
    if t is None:
        from fastapi import HTTPException, status as st
        raise HTTPException(
            status_code=st.HTTP_404_NOT_FOUND,
            detail="Тикет не найден или нет доступа",
        )
    return t


@router.post("/support/tickets/{chat_id}/mark")
async def mark_support_ticket_state(
    chat_id: int,
    body: TicketStateRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    uid = int(user["id"])
    return await support_tickets.mark_ticket_state(db, chat_id, uid, state=body.state)


@router.post("/support/tickets/{chat_id}/finalize")
async def finalize_support_ticket(
    chat_id: int,
    body: TicketFinalizeRequest,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> dict:
    uid = int(user["id"])
    return await support_tickets.finalize_ticket(db, chat_id, uid, action=body.action)


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
