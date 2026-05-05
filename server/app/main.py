"""
Точка входа FastAPI: загрузка .env, lifespan (каталоги + БД), CORS, роутеры.
Запуск из каталога server/: uvicorn app.main:app --reload --port 8000
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

# Важно: .env до любого импорта app.config (там проверяется SECRET_KEY).
from dotenv import load_dotenv

_SERVER_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(_SERVER_ROOT / ".env")

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.admin.invites_router import router as admin_invites_router
from app.admin.roles_router import router as admin_roles_router
from app.auth.router import router as auth_router
from app.config import BACKUP_PATH, DATABASE_PATH, MEDIA_PATH
from app.device_transfer.router import router as device_transfer_router
from app.database.database import Database
from app.friends.router import router as friends_router
from app.messages.router import router as messages_router
from app.owner.router import router as owner_router
from app.push.router import router as push_router
from app.users.router import router as users_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Старт: каталоги data/* и инициализация SQLite.
    Остановка: запись в лог (корректное завершение воркера uvicorn).
    """
    # --- startup ---
    db_file = _SERVER_ROOT / DATABASE_PATH
    db_file.parent.mkdir(parents=True, exist_ok=True)
    (_SERVER_ROOT / MEDIA_PATH).mkdir(parents=True, exist_ok=True)
    (_SERVER_ROOT / BACKUP_PATH).mkdir(parents=True, exist_ok=True)

    db = Database(db_file)
    await db.init_db()
    app.state.db = db
    logger.info("LeWoGram: каталоги и БД готовы (%s)", db_file)

    yield

    # --- shutdown ---
    logger.info("сервер остановлен")


app = FastAPI(title="LeWoGram", lifespan=lifespan)

# Пока разрешаем любые источники (в проде — конкретные origin).
# С allow_origins=["*"] нельзя allow_credentials=True (ограничение CORS в браузерах).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/auth")
app.include_router(device_transfer_router, prefix="/device-transfer")
app.include_router(messages_router, prefix="/messages")
app.include_router(users_router, prefix="/users")
app.include_router(friends_router, prefix="/friends")
app.include_router(push_router, prefix="/push")
app.include_router(owner_router, prefix="/owner")
app.include_router(admin_roles_router, prefix="/admin")
app.include_router(admin_invites_router, prefix="/admin")

_media_root = (_SERVER_ROOT / MEDIA_PATH).resolve()
_media_root.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=str(_media_root)), name="media")


@app.get("/")
async def root() -> dict[str, str]:
    """Проверка живости сервера."""
    return {"status": "ok", "app": "LeWoGram"}
