"""
Схемы API для инвайт-ссылок (админка).
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class CreateInviteRequest(BaseModel):
    """Создание инвайта; по умолчанию 48 ч."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    expires_hours: int = Field(default=48, ge=1, le=24 * 365 * 2, description="Срок жизни в часах")
    note: str | None = Field(default=None, max_length=500, description="Заметка для себя (опционально)")
    max_uses: int | None = Field(
        default=None,
        ge=1,
        description="Зарезервировано на будущее; в MVP не используется",
    )


class InviteCreatedResponse(BaseModel):
    """Ответ после POST: токен и метаданные."""

    token: str
    expires_at: str
    created_at: str
    created_by_user_id: int


class InviteListItemResponse(BaseModel):
    """Одна строка в списке инвайтов."""

    model_config = ConfigDict(extra="ignore")

    id: int
    token: str
    is_active: bool
    used_at: str | None
    expires_at: str | None
    created_at: str | None
    created_by_user_id: int
    note: str | None = None
