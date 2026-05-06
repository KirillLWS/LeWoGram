from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class UserMeResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    login: str
    username: str
    display_name: str | None = None
    about: str = ""
    avatar_path: str | None = None
    avatar_url: str | None = None
    avatar_exists: bool = False
    roles: list[str] = Field(default_factory=list)
    primary_role: str = "user"


class PatchUserMeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, max_length=256)
    username: str | None = Field(default=None, min_length=3, max_length=32)
    about: str | None = Field(default=None, max_length=2000)


class SupportDiagnosticSubmitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=32000)
    client_meta: dict[str, Any] | None = Field(default=None)


class SupportDiagnosticEntry(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    user_id: int
    user_login: str | None = None
    user_username: str | None = None
    body: str
    client_meta: str | None = None
    created_at: str | None = None


class SupportAccessGrantRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    minutes: int = Field(default=30, ge=5, le=240)


class SupportAccessStateResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    active: bool
    session_id: int | None = None
    granted_by_user_id: int | None = None
    created_at: str | None = None
    expires_at: str | None = None
    scope: str = "diagnostics"


class UserPublicResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    username: str | None = None
    display_name: str | None = None
    about: str = ""
    avatar_path: str | None = None
    avatar_url: str | None = None
    avatar_exists: bool = False
    relation_to_me: str = "none"
    friend_request_id: int | None = None
    is_friend: bool = False
    incoming_request: bool = False
    outgoing_request: bool = False
    account_status: str = "active"
    ban_until: str | None = None
    primary_role: str = "user"


class UserSearchResult(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    username: str | None = None
    display_name: str | None = None
    about: str = ""
    avatar_path: str | None = None
    avatar_url: str | None = None
    avatar_exists: bool = False
