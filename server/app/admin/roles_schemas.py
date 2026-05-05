"""Схемы для roles_* admin API."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class GrantRoleBody(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    role: str = Field(..., min_length=1)


class RevokeRoleBody(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    role: str = Field(..., min_length=1)


class RolesListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_id: int
    roles: list[str]


class RoleHistoryEntry(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    target_user_id: int
    actor_user_id: int | None = None
    role: str
    action: str
    created_at: str
