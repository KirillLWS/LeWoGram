"""Пакет настроек: импортируй значения из app.config.config."""

from app.config.config import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    BACKUP_PATH,
    DATABASE_PATH,
    MEDIA_PATH,
    SECRET_KEY,
    backup_dir,
    media_dir,
)

__all__ = [
    "ACCESS_TOKEN_EXPIRE_MINUTES",
    "BACKUP_PATH",
    "DATABASE_PATH",
    "MEDIA_PATH",
    "SECRET_KEY",
    "backup_dir",
    "media_dir",
]
