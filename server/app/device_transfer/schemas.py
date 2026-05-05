"""Схемы /device-transfer и связанные."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class DeviceTransferRequestCreate(BaseModel):
    """Создание запроса (без JWT): пароль или фраза восстановления."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    login: str = Field(..., min_length=1)
    password: str | None = Field(default=None, min_length=1)
    recovery_phrase: str | None = Field(default=None, min_length=1)
    mode: Literal["add", "transfer"]
    device_fingerprint: str = Field(..., min_length=1)
    device_model: str | None = Field(default=None, max_length=256)
    device_os: str | None = Field(default=None, max_length=256)
    reason: str = Field(..., min_length=10, max_length=2000)
    geo_lat: float | None = None
    geo_lng: float | None = None
    geo_accuracy_m: float | None = None


class DeviceTransferRequestOut(BaseModel):
    id: int
    short_code: str
    expires_at: str


class DeviceTransferApproveBody(BaseModel):
    model_config = ConfigDict(extra="forbid")

    revoke_old: bool = False


class DeviceTransferDenyBody(BaseModel):
    model_config = ConfigDict(extra="forbid")

    note: str | None = Field(default=None, max_length=2000)


class DeviceTransferPollOut(BaseModel):
    status: str
    access_token: str | None = None
    refresh_token: str | None = None
    expires_in: int | None = None
    token_type: str | None = "bearer"
    reason: str | None = None


class RecoverInitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    login: str = Field(..., min_length=1)
    phrase: str = Field(..., min_length=1)
    device_fingerprint: str = Field(..., min_length=1)
    device_model: str | None = Field(default=None, max_length=256)
    device_os: str | None = Field(default=None, max_length=256)
