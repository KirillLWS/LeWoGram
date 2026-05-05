"""
Нормализация полей аватара для API: относительный путь в хранилище, URL под /media/, флаг наличия файла.
"""

from __future__ import annotations

from typing import Any

from app.config.config import media_dir


def avatar_fields(raw_path: str | None) -> dict[str, Any]:
    """
    Убирает «битые» пути из БД (файла нет на диске), добавляет avatar_url и avatar_exists.
    """
    if raw_path is None:
        return {"avatar_path": None, "avatar_url": None, "avatar_exists": False}
    rel = str(raw_path).strip().lstrip("/")
    if not rel:
        return {"avatar_path": None, "avatar_url": None, "avatar_exists": False}
    full = media_dir() / rel
    if not full.is_file():
        return {"avatar_path": None, "avatar_url": None, "avatar_exists": False}
    return {
        "avatar_path": rel,
        "avatar_url": f"/media/{rel}",
        "avatar_exists": True,
    }


def apply_avatar_fields(d: dict[str, Any]) -> None:
    """Обновляет dict на месте ключами avatar_path, avatar_url, avatar_exists."""
    d.update(avatar_fields(d.get("avatar_path")))
