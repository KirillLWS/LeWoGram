from __future__ import annotations

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


class PatchUserMeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, max_length=256)
    username: str | None = Field(default=None, min_length=3, max_length=32)
    about: str | None = Field(default=None, max_length=2000)


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


class UserSearchResult(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: int
    username: str | None = None
    display_name: str | None = None
    about: str = ""
    avatar_path: str | None = None
    avatar_url: str | None = None
    avatar_exists: bool = False
