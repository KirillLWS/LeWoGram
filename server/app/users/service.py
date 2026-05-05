from __future__ import annotations

import re
import uuid

from typing import Any

from fastapi import HTTPException, UploadFile, status

import aiosqlite

from app.config.config import AVATAR_MAX_BYTES, USER_ABOUT_MAX_LEN, media_dir
from app.database.database import Database
from app.users.schemas import PatchUserMeRequest, UserMeResponse, UserPublicResponse, UserSearchResult

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
    return UserMeResponse(
        id=uid,
        login=login,
        username=username,
        display_name=user.get("display_name"),
        about=str(user.get("about") or ""),
        avatar_path=user.get("avatar_path"),
        roles=roles,
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
    return [UserSearchResult.model_validate(r) for r in rows]


async def get_public_profile(db: Database, user_id: int) -> UserPublicResponse:
    row = await db.get_user_public_profile(user_id)
    if row is None or int(row.get("is_blocked", 0)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    d = {k: row[k] for k in ("id", "username", "display_name", "about", "avatar_path")}
    return UserPublicResponse.model_validate(d)


async def upload_avatar(db: Database, user: dict[str, Any], file: UploadFile) -> UserMeResponse:
    uid = int(user["id"])
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
