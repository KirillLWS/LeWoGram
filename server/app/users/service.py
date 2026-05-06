from __future__ import annotations

import json
import re
import uuid

from typing import Any

from fastapi import HTTPException, UploadFile, status

import aiosqlite

from app.auth import ban_policy
from app.avatar_fields import apply_avatar_fields
from app.config.config import AVATAR_MAX_BYTES, USER_ABOUT_MAX_LEN, media_dir
from app.database.database import Database
from app.database import db_support_access, db_support_diagnostics, db_user_audit
from app.database.db_roles import highest_role_from_list
from app.users.schemas import (
    PatchUserMeRequest,
    SupportAccessGrantRequest,
    SupportAccessStateResponse,
    SupportDiagnosticSubmitRequest,
    UserMeResponse,
    UserPublicResponse,
    UserSearchResult,
)
from app.friends.service import get_status_response

_USERNAME_RE = re.compile(r"^[a-zA-Z0-9_.]{3,32}$")
_ALLOWED_AVATAR_EXT = frozenset({"jpg", "jpeg", "png", "webp"})


def _normalize_username(raw: str) -> str:
    return raw.strip()


def _validate_username(username: str) -> str:
    u = _normalize_username(username)
    if not _USERNAME_RE.fullmatch(u):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="username: 3–32 символа, только латиница, цифры, _, .",
        )
    return u


def _validate_display_name(raw: str | None) -> str:
    if raw is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="display_name обязателен и не может быть пустым",
        )
    s = raw.strip()
    if not s:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="display_name не может быть пустым",
        )
    if len(s) > 256:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="display_name не длиннее 256 символов",
        )
    return s


def _validate_about(raw: str | None) -> str:
    if raw is None:
        return ""
    if len(raw) > USER_ABOUT_MAX_LEN:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"about не длиннее {USER_ABOUT_MAX_LEN} символов",
        )
    return raw


async def _me_response(db: Database, user: dict[str, Any]) -> UserMeResponse:
    uid = int(user["id"])
    login = str(user["login"])
    un = user.get("username")
    username = str(un).strip() if un is not None and str(un).strip() else login
    roles = await db.list_user_roles(uid)
    primary_role = highest_role_from_list(roles)
    u = dict(user)
    apply_avatar_fields(u)
    return UserMeResponse(
        id=uid,
        login=login,
        username=username,
        display_name=user.get("display_name"),
        about=str(user.get("about") or ""),
        avatar_path=u.get("avatar_path"),
        avatar_url=u.get("avatar_url"),
        avatar_exists=bool(u.get("avatar_exists")),
        roles=roles,
        primary_role=primary_role,
    )


def _bytes_look_like_image(data: bytes, ext: str) -> bool:
    if len(data) < 12:
        return False
    if ext in ("jpg", "jpeg"):
        return data.startswith(b"\xff\xd8\xff")
    if ext == "png":
        return data.startswith(b"\x89PNG\r\n\x1a\n")
    if ext == "webp":
        return data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    return False


async def get_me(db: Database, user: dict[str, Any]) -> UserMeResponse:
    return await _me_response(db, user)


async def patch_me(db: Database, user: dict[str, Any], body: PatchUserMeRequest) -> UserMeResponse:
    uid = int(user["id"])
    gate = await db.get_user_by_id(uid)
    if gate is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    await ban_policy.ensure_not_banned(db, gate)

    data = body.model_dump(exclude_unset=True)
    if not data:
        fresh = await db.get_user_by_id(uid)
        if fresh is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
        return await _me_response(db, fresh)

    display_name: str | None = None
    username: str | None = None
    about: str | None = None

    if "display_name" in data:
        display_name = _validate_display_name(data["display_name"])
    if "username" in data:
        username = _validate_username(data["username"])
        if await db.is_username_taken(username, exclude_user_id=uid):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Этот username уже занят",
            )
    if "about" in data:
        about = _validate_about(data["about"])

    try:
        await db.patch_user_me(
            uid,
            display_name=display_name,
            username=username,
            about=about,
        )
    except aiosqlite.IntegrityError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Этот username уже занят или конфликт данных",
        ) from e

    fresh = await db.get_user_by_id(uid)
    if fresh is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    return await _me_response(db, fresh)


async def search_users(db: Database, current_user_id: int, q: str) -> list[UserSearchResult]:
    term = q.strip()
    if len(term) < 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Параметр q не может быть пустым",
        )
    rows = await db.search_users(term, current_user_id, limit=50)
    out: list[UserSearchResult] = []
    for r in rows:
        d = dict(r)
        apply_avatar_fields(d)
        out.append(UserSearchResult.model_validate(d))
    return out


async def get_public_profile(db: Database, viewer_id: int, user_id: int) -> UserPublicResponse:
    row = await db.get_user_public_profile(user_id)
    if row is None or int(row.get("is_blocked", 0)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    d = {
        k: row[k]
        for k in (
            "id",
            "username",
            "display_name",
            "about",
            "avatar_path",
            "account_status",
            "ban_until",
        )
    }
    apply_avatar_fields(d)
    roles = await db.list_user_roles(user_id)
    d["primary_role"] = highest_role_from_list(roles)
    st = await get_status_response(db, viewer_id, user_id)
    d["relation_to_me"] = st.relation
    d["friend_request_id"] = st.request_id
    d["is_friend"] = st.is_friend
    d["incoming_request"] = st.incoming_request
    d["outgoing_request"] = st.outgoing_request
    return UserPublicResponse.model_validate(d)


async def upload_avatar(db: Database, user: dict[str, Any], file: UploadFile) -> UserMeResponse:
    uid = int(user["id"])
    gate = await db.get_user_by_id(uid)
    if gate is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    await ban_policy.ensure_not_banned(db, gate)

    filename = (file.filename or "").lower()
    ext = ""
    if "." in filename:
        ext = filename.rsplit(".", 1)[-1]
    if ext not in _ALLOWED_AVATAR_EXT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Допустимы только изображения: jpg, jpeg, png, webp",
        )
    data = await file.read()
    if len(data) > AVATAR_MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Файл больше {AVATAR_MAX_BYTES // (1024 * 1024)} МБ",
        )
    if not _bytes_look_like_image(data, ext):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Содержимое не похоже на допустимое изображение",
        )

    safe_ext = "jpg" if ext == "jpeg" else ext
    name = f"{uuid.uuid4().hex}.{safe_ext}"
    rel = f"avatars/users/{uid}/{name}"
    base = media_dir()
    dest_dir = base / "avatars" / "users" / str(uid)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_path = dest_dir / name
    dest_path.write_bytes(data)

    try:
        await db.add_user_avatar(uid, rel)
    except Exception:
        try:
            dest_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Не удалось сохранить аватар",
        ) from None

    fresh = await db.get_user_by_id(uid)
    if fresh is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    return await _me_response(db, fresh)


def _support_access_state_from_row(
    row: dict[str, Any] | None,
) -> SupportAccessStateResponse:
    if row is None:
        return SupportAccessStateResponse(active=False)
    return SupportAccessStateResponse(
        active=True,
        session_id=int(row["id"]),
        granted_by_user_id=(
            int(row["granted_by_user_id"])
            if row.get("granted_by_user_id") is not None
            else None
        ),
        created_at=str(row.get("created_at") or ""),
        expires_at=str(row.get("expires_at") or ""),
        scope=str(row.get("scope") or "diagnostics"),
    )


async def get_support_access_state(
    db: Database,
    user: dict[str, Any],
) -> SupportAccessStateResponse:
    uid = int(user["id"])
    active = await db_support_access.get_active_support_access(db.db_path, user_id=uid)
    return _support_access_state_from_row(active)


async def grant_support_access(
    db: Database,
    user: dict[str, Any],
    body: SupportAccessGrantRequest,
) -> SupportAccessStateResponse:
    uid = int(user["id"])
    gate = await db.get_user_by_id(uid)
    if gate is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    await ban_policy.ensure_not_banned(db, gate)

    row = await db_support_access.grant_support_access(
        db.db_path,
        user_id=uid,
        granted_by_user_id=uid,
        minutes=body.minutes,
    )
    db_user_audit.schedule_user_audit_event(
        db.db_path,
        user_id=uid,
        actor_id=uid,
        event_type="support.access_granted",
        payload={
            "session_id": int(row["id"]),
            "minutes": int(body.minutes),
            "scope": str(row.get("scope") or "diagnostics"),
            "expires_at": row.get("expires_at"),
        },
    )
    return _support_access_state_from_row(row)


async def revoke_support_access(
    db: Database,
    user: dict[str, Any],
) -> dict[str, Any]:
    uid = int(user["id"])
    gate = await db.get_user_by_id(uid)
    if gate is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    await ban_policy.ensure_not_banned(db, gate)

    revoked = await db_support_access.revoke_active_support_access(db.db_path, user_id=uid)
    db_user_audit.schedule_user_audit_event(
        db.db_path,
        user_id=uid,
        actor_id=uid,
        event_type="support.access_revoked",
        payload={"revoked_sessions": int(revoked)},
    )
    return {"ok": True, "revoked_sessions": int(revoked)}


async def submit_support_diagnostic(
    db: Database,
    user: dict[str, Any],
    body: SupportDiagnosticSubmitRequest,
) -> dict[str, Any]:
    uid = int(user["id"])
    gate = await db.get_user_by_id(uid)
    if gate is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    await ban_policy.ensure_not_banned(db, gate)

    meta_str: str | None = None
    if body.client_meta is not None:
        has_meta = bool(body.client_meta)
        if has_meta:
            active = await db_support_access.get_active_support_access(
                db.db_path,
                user_id=uid,
            )
            if active is None:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        "Для расширенной диагностики сначала включите временный доступ поддержке "
                        "(/users/me/support-access/grant)"
                    ),
                )
        meta_str = json.dumps(body.client_meta, ensure_ascii=False)

    rid = await db_support_diagnostics.insert_diagnostic_log(
        db,
        user_id=uid,
        body=body.body,
        client_meta=meta_str,
    )
    db_user_audit.schedule_user_audit_event(
        db.db_path,
        user_id=uid,
        actor_id=None,
        event_type="support.diagnostic_submit",
        payload={
            "diagnostic_log_id": rid,
            "body_chars": len(body.body or ""),
            "has_client_meta": meta_str is not None,
        },
    )
    return {"id": rid, "ok": True}
