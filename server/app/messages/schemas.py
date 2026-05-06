"""
Pydantic-схемы для чатов и текстовых сообщений (MVP).
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class CreateDirectChatRequest(BaseModel):
    """Создать личный чат с другим пользователем (без дубликата пары)."""

    model_config = ConfigDict(extra="forbid")

    other_user_id: int = Field(..., gt=0)


class CreateGroupChatRequest(BaseModel):
    """Создать групповой чат; создатель станет owner, остальные — member."""

    model_config = ConfigDict(extra="forbid")

    title: str = Field(..., min_length=1, max_length=256)
    member_ids: list[int] = Field(default_factory=list)


class SendTextMessageRequest(BaseModel):
    """Отправка текстового сообщения в чат."""

    model_config = ConfigDict(extra="forbid")

    chat_id: int = Field(..., gt=0)
    text: str = Field(..., min_length=1, max_length=16000)
    reply_to_id: int | None = Field(default=None, gt=0)


class MarkReadRequest(BaseModel):
    """Отметить сообщения в чате прочитанными до указанного id включительно."""

    model_config = ConfigDict(extra="forbid")

    chat_id: int = Field(..., gt=0)
    message_id: int = Field(..., gt=0)


class PatchChatRequest(BaseModel):
    """Переименовать чат (в т.ч. direct — пишется в chats.title / description)."""

    model_config = ConfigDict(extra="forbid")

    title: str = Field(..., min_length=1, max_length=256)
    description: str | None = Field(default=None, max_length=2000)


class ChatResponse(BaseModel):
    """Чат + роль текущего пользователя в нём (из JOIN в списке чатов)."""

    model_config = ConfigDict(extra="ignore", protected_namespaces=())

    id: int
    type: str
    title: str | None = None
    description: str | None = None
    avatar_path: str | None = None
    avatar_url: str | None = None
    avatar_exists: bool = False
    created_by: int | None = None
    is_archived: bool = False
    members_count: int = 0
    created_at: str
    updated_at: str
    my_role: str | None = None
    my_can_write: bool = True
    last_message_text: str | None = None
    last_message_created_at: str | None = None
    unread_count: int = 0
    display_title: str | None = None
    display_subtitle: str | None = None
    peer_user_id: int | None = None
    # direct: title = кастомный chats.title или display_name > username > login;
    # subtitle — следующий в цепочке или при кастоме — первое peer-поле, отличное от title.


class MessageResponse(BaseModel):
    """Текстовое сообщение (MVP без вложений)."""

    model_config = ConfigDict(extra="ignore", protected_namespaces=())

    id: int
    chat_id: int
    sender_id: int | None = None
    type: str
    text: str | None = None
    reply_to_id: int | None = None
    is_deleted: bool = False
    is_edited: bool = False
    created_at: str
    edited_at: str | None = None
