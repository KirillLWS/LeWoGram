"""
Схемы списка пользователей и staff-блокировок (/admin/users/*).
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class AdminUserListItem(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    login: str
    username: str | None = None
    display_name: str | None = None
    avatar_path: str | None = None
    account_status: str = "active"
    ban_until: str | None = None
    ban_reason: str = ""
    staff_ban: bool = False
    is_blocked: bool = False
    created_at: str
    last_seen_at: str | None = None


class AdminUserListResponse(BaseModel):
    users: list[AdminUserListItem]
    total: int


class StaffBanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    kind: Literal["permanent", "temporary"]
    reason: str = Field(default="", max_length=2000)
    duration_minutes: int | None = Field(
        default=None,
        ge=1,
        le=10_512_000,
        description="Для kind=temporary: минуты (макс. 20 лет).",
    )


class StaffUnbanResponse(BaseModel):
    ok: bool = True
