from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, field_validator


class CreateReportRequest(BaseModel):
    target_type: str
    target_user_id: int | None = None
    target_message_id: int | None = None
    reason_code: str = "other"
    description: str = ""

    @field_validator("target_type")
    @classmethod
    def _tt(cls, v: str) -> str:
        t = (v or "").strip().lower()
        if t not in ("user", "profile", "message"):
            raise ValueError("target_type must be user, profile, or message")
        return t


class CreateReportResponse(BaseModel):
    id: int
    status: str = "open"


class ReportListItem(BaseModel):
    id: int
    reporter_id: int
    target_type: str
    target_user_id: int | None
    target_message_id: int | None
    reason_code: str
    description: str
    status: str
    created_at: str | None
    updated_at: str | None
    reporter_login: str | None = None
    reporter_username: str | None = None

    @classmethod
    def from_row(cls, r: dict[str, Any]) -> ReportListItem:
        return cls(
            id=int(r["id"]),
            reporter_id=int(r["reporter_id"]),
            target_type=str(r["target_type"]),
            target_user_id=int(r["target_user_id"]) if r.get("target_user_id") is not None else None,
            target_message_id=int(r["target_message_id"])
            if r.get("target_message_id") is not None
            else None,
            reason_code=str(r.get("reason_code") or "other"),
            description=str(r.get("description") or ""),
            status=str(r.get("status") or "open"),
            created_at=r.get("created_at"),
            updated_at=r.get("updated_at"),
            reporter_login=r.get("reporter_login"),
            reporter_username=r.get("reporter_username"),
        )


class ReportDetail(ReportListItem):
    resolution_note: str | None = None
    resolved_at: str | None = None
    resolved_by: int | None = None
    target_user_login: str | None = None
    target_user_username: str | None = None

    @classmethod
    def from_row(cls, r: dict[str, Any]) -> ReportDetail:
        return cls(
            id=int(r["id"]),
            reporter_id=int(r["reporter_id"]),
            target_type=str(r["target_type"]),
            target_user_id=int(r["target_user_id"]) if r.get("target_user_id") is not None else None,
            target_message_id=int(r["target_message_id"])
            if r.get("target_message_id") is not None
            else None,
            reason_code=str(r.get("reason_code") or "other"),
            description=str(r.get("description") or ""),
            status=str(r.get("status") or "open"),
            created_at=r.get("created_at"),
            updated_at=r.get("updated_at"),
            reporter_login=r.get("reporter_login"),
            reporter_username=r.get("reporter_username"),
            resolution_note=r.get("resolution_note"),
            resolved_at=r.get("resolved_at"),
            resolved_by=int(r["resolved_by"]) if r.get("resolved_by") is not None else None,
            target_user_login=r.get("target_user_login"),
            target_user_username=r.get("target_user_username"),
        )


class ReportHistoryItem(BaseModel):
    id: int
    report_id: int
    actor_id: int
    action: str
    from_status: str | None
    to_status: str | None
    note: str | None
    created_at: str | None
    actor_login: str | None = None
    actor_username: str | None = None

    @classmethod
    def from_row(cls, r: dict[str, Any]) -> ReportHistoryItem:
        return cls(
            id=int(r["id"]),
            report_id=int(r["report_id"]),
            actor_id=int(r["actor_id"]),
            action=str(r.get("action") or ""),
            from_status=r.get("from_status"),
            to_status=r.get("to_status"),
            note=r.get("note"),
            created_at=r.get("created_at"),
            actor_login=r.get("actor_login"),
            actor_username=r.get("actor_username"),
        )


class ResolveReportRequest(BaseModel):
    note: str | None = None


class RejectReportRequest(BaseModel):
    note: str | None = None


class CreateSanctionRequest(BaseModel):
    user_id: int
    sanction_type: str
    reason: str | None = None
    report_id: int | None = None
    ends_at: str | None = None

    @field_validator("sanction_type")
    @classmethod
    def _st(cls, v: str) -> str:
        t = (v or "").strip().lower()
        if t not in ("warning", "mute", "ban", "shadow_ban", "other"):
            raise ValueError("invalid sanction_type")
        return t


class SanctionResponse(BaseModel):
    id: int
    user_id: int
    sanction_type: str
    reason: str | None
    report_id: int | None
    created_by: int
    is_active: int
    starts_at: str | None
    ends_at: str | None
    revoked_at: str | None
    revoked_by: int | None
    created_at: str | None

    @classmethod
    def from_row(cls, r: dict[str, Any]) -> SanctionResponse:
        return cls(
            id=int(r["id"]),
            user_id=int(r["user_id"]),
            sanction_type=str(r.get("sanction_type") or ""),
            reason=r.get("reason"),
            report_id=int(r["report_id"]) if r.get("report_id") is not None else None,
            created_by=int(r["created_by"]),
            is_active=int(r.get("is_active", 0)),
            starts_at=r.get("starts_at"),
            ends_at=r.get("ends_at"),
            revoked_at=r.get("revoked_at"),
            revoked_by=int(r["revoked_by"]) if r.get("revoked_by") is not None else None,
            created_at=r.get("created_at"),
        )


class RevokeSanctionBody(BaseModel):
    """Тело опционально (расширение без изменения схемы БД)."""

    note: str | None = Field(default=None, description="Зарезервировано для аудита на стороне координатора")
