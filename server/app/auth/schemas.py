"""
Pydantic-схемы тела запросов и ответов для /auth.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class RegisterRequest(BaseModel):
    """Регистрация по инвайту."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    invite_token: str = Field(..., min_length=1)
    login: str = Field(..., min_length=3, max_length=32)
    password: str = Field(..., min_length=8)
    device_fingerprint: str = Field(..., min_length=1)
    display_name: str | None = Field(default=None, max_length=128)


class LoginRequest(BaseModel):
    """Вход по логину и паролю."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    login: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)
    device_fingerprint: str = Field(..., min_length=1)
    device_model: str | None = Field(default=None, max_length=256)
    device_os: str | None = Field(default=None, max_length=256)


class TokenResponse(BaseModel):
    """Пара access + refresh (OAuth2-подобный ответ)."""

    access_token: str
    refresh_token: str
    expires_in: int
    token_type: str = "bearer"


class RegisterResponse(TokenResponse):
    """Ответ регистрации: токены + фраза восстановления (показать один раз)."""

    recovery_phrase: str


class RefreshRequest(BaseModel):
    """Обновление access по refresh (ротация refresh)."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    refresh_token: str = Field(..., min_length=1)


class LogoutRequest(BaseModel):
    """Выход с одного устройства по refresh-токену."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    refresh_token: str = Field(..., min_length=1)


class AuthSessionResponse(BaseModel):
    """Активная сессия для списка в UI."""

    id: int
    device_model: str | None = None
    device_os: str | None = None
    ip_address: str | None = None
    last_used_at: str | None = None
    created_at: str | None = None


class UserResponse(BaseModel):
    """Публичный профиль (без пароля и служебных полей)."""

    model_config = ConfigDict(extra="ignore")

    id: int
    login: str
    username: str | None = None
    display_name: str | None = None
    about: str = ""
    is_online: bool = False
    created_at: str
    last_seen_at: str | None = None
    must_change_password: bool = False
    roles: list[str] = Field(default_factory=list)
    primary_role: str = "user"
    account_status: str = "active"
    ban_until: str | None = None
    ban_reason: str = ""
    avatar_path: str | None = None
    avatar_url: str | None = None
    avatar_exists: bool = False


class ChangePasswordRequest(BaseModel):
    """Смена пароля авторизованным пользователем."""

    model_config = ConfigDict(extra="forbid")

    old_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=8)
