"""
Централизованные настройки LeWoGram (шаг 1: только пути, секрет и срок токена).

Пути к БД, медиа и бэкапам заданы относительно текущей рабочей директории процесса.
Запускай uvicorn из каталога server/, чтобы data/ лежал рядом с app/.
"""

from __future__ import annotations

import os
from pathlib import Path

# --- Пути (относительно cwd, обычно каталог server/) ---

DATABASE_PATH: str = "data/db/lewogram.db"
MEDIA_PATH: str = "data/media/"
BACKUP_PATH: str = "data/backups/"

# --- Безопасность ---

# Секрет для подписи JWT; обязательно задай в окружении (не храни в репозитории).
_SECRET_KEY_RAW = os.environ.get("SECRET_KEY")
if not _SECRET_KEY_RAW:
    raise RuntimeError(
        "Переменная окружения SECRET_KEY не задана. "
        "Установи её перед запуском сервера (например в .env и export)."
    )
SECRET_KEY: str = _SECRET_KEY_RAW

# Срок жизни access-токена в минутах (7 суток = 7 * 24 * 60).
ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080

# Профиль / аватар (users).
USER_ABOUT_MAX_LEN: int = 2000
AVATAR_MAX_BYTES: int = 5 * 1024 * 1024


def media_dir() -> Path:
    """Абсолютный путь к каталогу медиа (удобно для storage)."""
    return Path(MEDIA_PATH).resolve()


def backup_dir() -> Path:
    """Абсолютный путь к каталогу ночных бэкапов БД."""
    return Path(BACKUP_PATH).resolve()
