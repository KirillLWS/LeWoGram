"""
Загрузка APK клиента на сервер (chief_admin / owner): закрытый мессенджер без стора.
Файл раздаётся через StaticFiles GET /releases/<имя>.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from app.auth.dependencies import get_db
from app.database.database import Database
from app.reports.deps import require_chief_admin_or_owner

logger = logging.getLogger(__name__)

router = APIRouter(tags=["admin", "client-release"])

_SERVER_ROOT = Path(__file__).resolve().parent.parent.parent


def _releases_dir(releases_path: str) -> Path:
    return (_SERVER_ROOT / releases_path).resolve()


@router.post("/client-apk")
async def upload_client_apk(
    _: Annotated[dict, Depends(require_chief_admin_or_owner)],
    db: Annotated[Database, Depends(get_db)],
    file: UploadFile = File(..., description="Файл .apk"),
) -> dict[str, str]:
    """Заменить APK в каталоге releases (имя из CLIENT_APK_FILENAME в конфиге)."""
    del db
    from app.config.config import CLIENT_APK_FILENAME, RELEASES_PATH

    if not file.filename or not str(file.filename).lower().endswith(".apk"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ожидается файл с расширением .apk",
        )

    dest_dir = _releases_dir(RELEASES_PATH)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / CLIENT_APK_FILENAME

    data = await file.read()
    if len(data) < 1024:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Файл слишком мал для APK",
        )
    dest.write_bytes(data)
    logger.info("client APK uploaded -> %s (%s bytes)", dest, len(data))
    return {
        "ok": "true",
        "path": f"/releases/{CLIENT_APK_FILENAME}",
        "filename": CLIENT_APK_FILENAME,
    }
