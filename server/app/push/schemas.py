"""Схемы тела запросов для маршрутов /push/*."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class PushTokenBody(BaseModel):
    """Регистрация FCM-токена после авторизации клиента."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    token: str = Field(..., min_length=8, description="FCM registration token")
