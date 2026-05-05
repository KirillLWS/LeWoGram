"""
POST /owner/claim и /owner/transfer: токен из INITIAL_OWNER_TOKEN, атомарная передача owner.
"""

from __future__ import annotations

import hmac
import os
from typing import Any

from fastapi import HTTPException, status

from app.database.database import Database
from app.database.db_roles import claim_initial_owner_atomic, hash_initial_owner_token, transfer_owner_atomic
from app.owner.schemas import OwnerClaimRequest, OwnerTransferRequest, validate_non_owner_role


def _compare_tokens_constant_time(a: str, b: str) -> bool:
    try:
        aa = a.encode("utf-8")
        bb = b.encode("utf-8")
    except Exception:
        return False
    return hmac.compare_digest(aa, bb)


async def claim_owner(
    db: Database,
    claimer: dict[str, Any],
    body: OwnerClaimRequest,
) -> dict[str, bool]:
    env_raw = os.environ.get("INITIAL_OWNER_TOKEN")
    if not env_raw or not str(env_raw).strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Первичный токен владельца не настроен на сервере",
        )
    expected = str(env_raw).strip()
    if not _compare_tokens_constant_time(body.token.strip(), expected):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Неверный токен",
        )

    uid = int(claimer["id"])
    token_hash = hash_initial_owner_token(expected)

    try:
        await claim_initial_owner_atomic(db._db_path, claimer_user_id=uid, token_hash=token_hash)
    except ValueError as e:
        code = str(e)
        if code == "already_claimed":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Токен первичного владельца уже использован",
            ) from None
        raise

    return {"ok": True}


async def transfer_owner(
    db: Database,
    actor: dict[str, Any],
    body: OwnerTransferRequest,
) -> dict[str, bool]:
    try:
        new_role = validate_non_owner_role(body.new_self_role.strip())
    except ValueError as e:
        msg = str(e)
        if msg == "unknown_role":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Неизвестная роль",
            ) from None
        if msg == "cannot_be_owner":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="new_self_role не может быть owner (передайте owner целевому пользователю)",
            ) from None
        raise

    actor_id = int(actor["id"])
    target_id = int(body.target_user_id)

    try:
        await transfer_owner_atomic(
            db._db_path,
            actor_user_id=actor_id,
            target_user_id=target_id,
            new_self_role=new_role,
        )
    except ValueError as e:
        code = str(e)
        if code == "target_not_found_or_blocked":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Пользователь не найден или заблокирован",
            ) from None
        if code == "actor_not_owner":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Только владелец может передать роль owner",
            ) from None
        if code == "no_owner_after_transfer":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Невозможно оставить систему без владельца",
            ) from None
        raise

    return {"ok": True}
