"""Запись и выборка user_audit_events."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


async def insert_user_audit_event(
    db_path: Path,
    *,
    user_id: int | None,
    actor_id: int | None,
    event_type: str,
    payload: dict[str, Any] | None = None,
) -> int:
    body = json.dumps(payload or {}, ensure_ascii=False)
    async with aiosqlite.connect(db_path) as dbw:
        cur = await dbw.execute(
            """
            INSERT INTO user_audit_events (user_id, actor_id, event_type, payload)
            VALUES (?, ?, ?, ?)
            """,
            (user_id, actor_id, event_type.strip(), body),
        )
        await dbw.commit()
        return int(cur.lastrowid)


def schedule_user_audit_event(
    db_path: Path,
    *,
    user_id: int | None,
    actor_id: int | None,
    event_type: str,
    payload: dict[str, Any] | None = None,
) -> None:
    """Откладывает вставку в event loop (не блокирует ответ клиенту)."""

    async def _run() -> None:
        try:
            await insert_user_audit_event(
                db_path,
                user_id=user_id,
                actor_id=actor_id,
                event_type=event_type,
                payload=payload,
            )
        except Exception:
            logger.exception("user_audit: не удалось записать событие %s", event_type)

    try:
        asyncio.get_running_loop().create_task(_run())
    except RuntimeError:
        logger.warning("user_audit: нет running loop, событие %s не записано", event_type)


async def list_user_audit_events(
    db_path: Path,
    *,
    limit: int = 50,
    offset: int = 0,
    user_id: int | None = None,
) -> list[dict[str, Any]]:
    lim = max(1, min(limit, 200))
    off = max(0, offset)
    where = "1=1"
    params: list[Any] = []
    if user_id is not None:
        where += " AND user_id = ?"
        params.append(user_id)
    sql = f"""
        SELECT id, user_id, actor_id, event_type, payload, created_at
        FROM user_audit_events
        WHERE {where}
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
    """
    params.extend([lim, off])
    async with aiosqlite.connect(db_path) as dbw:
        dbw.row_factory = aiosqlite.Row
        async with dbw.execute(sql, params) as cur:
            rows = await cur.fetchall()
    out: list[dict[str, Any]] = []
    for r in rows:
        d = _row_to_dict(r)
        raw_payload = d.get("payload")
        if isinstance(raw_payload, str) and raw_payload.strip():
            try:
                d["payload"] = json.loads(raw_payload)
            except json.JSONDecodeError:
                d["payload"] = {"_raw": raw_payload}
        else:
            d["payload"] = {}
        out.append(d)
    return out
