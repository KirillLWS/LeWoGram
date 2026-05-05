from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class FriendRequestCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_user_id: int = Field(..., ge=1)


class FriendshipResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    from_user_id: int
    to_user_id: int
    status: str
    created_at: str
    updated_at: str


class FriendUserSnippet(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    username: str | None = None
    display_name: str | None = None
    avatar_path: str | None = None


class FriendRequestItem(BaseModel):
    """Входящая или исходящая заявка: id строки friendships для accept/decline."""

    request_id: int
    user: FriendUserSnippet


class FriendStatusResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    relation: str
    request_id: int | None = None
