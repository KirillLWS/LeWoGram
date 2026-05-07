"""Пакет настроек: импортируй значения из app.config.config."""

from app.config.config import (
    ACCESS_TOKEN_EXPIRE_MINUTES,
    BACKUP_PATH,
    CLIENT_UPDATE_URL,
    DATABASE_PATH,
    MEDIA_PATH,
    MIN_CLIENT_VERSION,
    REFRESH_TOKEN_EXPIRE_DAYS,
    SECRET_KEY,
    backup_dir,
    media_dir,
)

__all__ = [
    "ACCESS_TOKEN_EXPIRE_MINUTES",
    "BACKUP_PATH",
    "CLIENT_UPDATE_URL",
    "DATABASE_PATH",
    "MEDIA_PATH",
    "MIN_CLIENT_VERSION",
    "REFRESH_TOKEN_EXPIRE_DAYS",
    "SECRET_KEY",
    "backup_dir",
    "media_dir",
]
