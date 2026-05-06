"""
Бизнес-логика чатов и текстовых сообщений (MVP, без WebSocket и файлов).
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import HTTPException, status

from app.auth import ban_policy
from app.avatar_fields import apply_avatar_fields
from app.database.database import Database
from app.database.db_roles import OPERATIONAL_STAFF_ROLES
from app.messages.schemas import (
    ChatResponse,
    CreateDirectChatRequest,
    CreateGroupChatRequest,
    MarkReadRequest,
    MessageResponse,
    PatchChatRequest,
    SendTextMessageRequest,
)
from app.messages import support_chat as support_chat_util

logger = logging.getLogger(__name__)


async def _ensure_user_not_banned_for_api(db: Database, user_id: int) -> None:
    row = await db.get_user_by_id(user_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден",
        )
    await ban_policy.ensure_not_banned(db, row)


async def _raise_if_peer_blocked_for_messaging(db: Database, peer_row: dict[str, Any]) -> None:
    u = await ban_policy.materialize_user_ban(db, dict(peer_row))
    if u is None:
        return
    if ban_policy.account_block_payload(u) is not None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Собеседник заблокирован — отправка сообщений недоступна",
        )


async def _raise_if_user_blocked_for_contact(db: Database, user_row: dict[str, Any]) -> None:
    u = await ban_policy.materialize_user_ban(db, dict(user_row))
    if u is None:
        return
    if ban_policy.account_block_payload(u) is not None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Пользователь заблокирован — личный чат недоступен",
        )


def _as_bool(v: Any) -> bool:
    return bool(int(v)) if v is not None and str(v).isdigit() else bool(v)


async def _chat_payload_for_user(
    db: Database,
    chat_id: int,
    user_id: int,
) -> dict[str, Any] | None:
    """Объединяет строку chats и membership текущего пользователя (для ChatResponse)."""
    chat = await db.get_chat(chat_id)
    if chat is None:
        return None
    m = await db.get_chat_member(chat_id, user_id)
    if m is None:
        return None
    chat = dict(chat)
    chat["my_role"] = m.get("role")
    chat["my_can_write"] = _as_bool(m.get("can_write", 1))
    chat["is_archived"] = _as_bool(chat.get("is_archived", 0))
    return chat


def _chat_response_from_row(row: dict[str, Any]) -> ChatResponse:
    """Строка из get_user_chats / _chat_payload_for_user (опционально поля превью и unread)."""
    d = dict(row)
    d["is_archived"] = _as_bool(d.get("is_archived", 0))
    if "my_can_write" in d:
        d["my_can_write"] = _as_bool(d.get("my_can_write", 1))
    d.setdefault("last_message_text", None)
    d.setdefault("last_message_created_at", None)
    d.setdefault("unread_count", 0)
    d.setdefault("display_title", None)
    d.setdefault("display_subtitle", None)
    d.setdefault("peer_user_id", None)
    apply_avatar_fields(d)
    return ChatResponse.model_validate(d)


def _strip_or_none(v: Any) -> str | None:
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def _peer_title_subtitle(
    peer_display: Any,
    peer_username: Any,
    peer_login: Any,
) -> tuple[str | None, str | None]:
    """Для direct без кастомного title: title — первый непустой из display_name, username, login; subtitle — следующий отличный."""
    seq = (
        _strip_or_none(peer_display),
        _strip_or_none(peer_username),
        _strip_or_none(peer_login),
    )
    ordered: list[str] = []
    seen: set[str] = set()
    for s in seq:
        if s and s not in seen:
            seen.add(s)
            ordered.append(s)
    if not ordered:
        return None, None
    if len(ordered) == 1:
        return ordered[0], None
    return ordered[0], ordered[1]


async def _enrich_chat_display_fields(
    db: Database,
    row: dict[str, Any],
    viewer_user_id: int,
) -> None:
    """
    display_title / display_subtitle для списка и одиночного чата.
    direct: кастомное chats.title; иначе display_name > username > login;
    subtitle — следующий в цепочке или при кастомном title первый peer-поле, отличное от title.
    """
    peer_id_raw = row.pop("direct_peer_id", None)
    peer_login = _strip_or_none(row.pop("direct_peer_login", None))
    peer_username = _strip_or_none(row.pop("direct_peer_username", None))
    peer_display = _strip_or_none(row.pop("direct_peer_display_name", None))
    ctype = str(row.get("type") or "")
    raw_title = row.get("title")

    if ctype == "direct":
        row["peer_user_id"] = int(peer_id_raw) if peer_id_raw is not None else None
        if peer_login is None and peer_display is None and peer_username is None:
            peer = await db.get_direct_chat_peer_user(int(row["id"]), viewer_user_id)
            if peer:
                row["peer_user_id"] = int(peer["id"])
                peer_login = _strip_or_none(peer.get("login"))
                peer_username = _strip_or_none(peer.get("username"))
                peer_display = _strip_or_none(peer.get("display_name"))
        custom_title = raw_title is not None and str(raw_title).strip() != ""
        if custom_title:
            row["display_title"] = str(raw_title).strip()
            row["display_subtitle"] = None
            for s in (peer_display, peer_username, peer_login):
                if s and s != row["display_title"]:
                    row["display_subtitle"] = s
                    break
        else:
            peer_title, peer_sub = _peer_title_subtitle(peer_display, peer_username, peer_login)
            row["display_title"] = peer_title
            row["display_subtitle"] = peer_sub
    else:
        row["peer_user_id"] = None
        row["display_title"] = _strip_or_none(raw_title)
        row["display_subtitle"] = _strip_or_none(row.get("description"))


async def _finalize_chat_response(
    db: Database,
    row: dict[str, Any],
    viewer_user_id: int,
) -> ChatResponse:
    d = dict(row)
    await _enrich_chat_display_fields(db, d, viewer_user_id)
    return _chat_response_from_row(d)


def _message_response_from_row(row: dict[str, Any]) -> MessageResponse:
    d = dict(row)
    d["is_deleted"] = _as_bool(d.get("is_deleted", 0))
    d["is_edited"] = _as_bool(d.get("is_edited", 0))
    return MessageResponse.model_validate(d)


async def create_direct_chat(
    db: Database,
    current_user_id: int,
    body: CreateDirectChatRequest,
) -> ChatResponse:
    """Личный чат 1:1; при существующем direct между этой парой — возвращает его."""
    await _ensure_user_not_banned_for_api(db, current_user_id)
    other = body.other_user_id
    if other == current_user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Нельзя создать чат с самим собой",
        )

    other_user = await db.get_user_by_id(other)
    if other_user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден",
        )

    await _raise_if_user_blocked_for_contact(db, other_user)

    existing_id = await db.find_direct_chat_id_between(current_user_id, other)
    if existing_id is not None:
        payload = await _chat_payload_for_user(db, existing_id, current_user_id)
        if payload is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Не удалось загрузить существующий чат",
            )
        return await _finalize_chat_response(db, payload, current_user_id)

    chat_id = await db.create_chat("direct", None, current_user_id)
    await db.add_chat_member(chat_id, current_user_id, "member", 1)
    await db.add_chat_member(chat_id, other, "member", 1)

    payload = await _chat_payload_for_user(db, chat_id, current_user_id)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Не удалось загрузить созданный чат",
        )
    return await _finalize_chat_response(db, payload, current_user_id)


async def create_group_chat(
    db: Database,
    current_user_id: int,
    body: CreateGroupChatRequest,
) -> ChatResponse:
    """Групповой чат: создатель — owner, member_ids — участники (без дубликатов)."""
    await _ensure_user_not_banned_for_api(db, current_user_id)
    seen: set[int] = set()
    for mid in body.member_ids:
        if mid == current_user_id or mid in seen:
            continue
        seen.add(mid)
        u = await db.get_user_by_id(mid)
        if u is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Пользователь с id={mid} не найден",
            )

    chat_id = await db.create_chat("group", body.title.strip(), current_user_id)
    await db.add_chat_member(chat_id, current_user_id, "owner", 1)
    for mid in seen:
        await db.add_chat_member(chat_id, mid, "member", 1)

    payload = await _chat_payload_for_user(db, chat_id, current_user_id)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Не удалось загрузить созданный чат",
        )
    return await _finalize_chat_response(db, payload, current_user_id)


async def open_support_chat(db: Database, current_user_id: int) -> ChatResponse:
    """Добавляет пользователя в глобальный чат поддержки и возвращает его карточку."""
    await _ensure_user_not_banned_for_api(db, current_user_id)
    cid = await support_chat_util.ensure_user_in_support_chat(db, current_user_id)
    payload = await _chat_payload_for_user(db, cid, current_user_id)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Не удалось загрузить чат поддержки",
        )
    return await _finalize_chat_response(db, payload, current_user_id)


async def send_text_message(
    db: Database,
    current_user_id: int,
    body: SendTextMessageRequest,
) -> MessageResponse:
    """Текст в чат: проверка членства и права писать (канал с can_write=0 → 403)."""
    text = body.text.strip()
    if not text:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Текст сообщения не может быть пустым",
        )

    await _ensure_user_not_banned_for_api(db, current_user_id)

    member = await db.get_chat_member(body.chat_id, current_user_id)
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Вы не состоите в этом чате",
        )

    chat = await db.get_chat(body.chat_id)
    if chat is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Чат не найден",
        )

    if str(chat.get("type")) == "channel" and not _as_bool(member.get("can_write", 1)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Нельзя отправлять сообщения в этот канал",
        )

    if str(chat.get("type")) == "direct":
        peer_snippet = await db.get_direct_chat_peer_user(body.chat_id, current_user_id)
        if peer_snippet:
            peer_full = await db.get_user_by_id(int(peer_snippet["id"]))
            if peer_full is not None:
                await _raise_if_peer_blocked_for_messaging(db, peer_full)

    reply_to_id = body.reply_to_id
    if reply_to_id is not None:
        parent = await db.get_message_by_id(reply_to_id)
        if parent is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Сообщение для ответа не найдено",
            )
        if int(parent["chat_id"]) != body.chat_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Ответ относится к другому чату",
            )

    ctype = str(chat.get("type") or "")
    if ctype == "support":
        is_staff = await db.rbac_user_has_any_role(current_user_id, OPERATIONAL_STAFF_ROLES)
        if reply_to_id is not None and not is_staff:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Отвечать в чате поддержки могут только сотрудники (admin и выше)",
            )

    msg_id = await db.create_message(
        body.chat_id,
        current_user_id,
        "text",
        text=text,
        reply_to_id=reply_to_id,
    )
    row = await db.get_message_by_id(msg_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Сообщение создано, но не удалось прочитать из БД",
        )
    # Push остальным участникам чата (не блокирует ответ при сбое FCM).
    try:
        from app.push.service import send_push_to_user

        for rid in await db.list_chat_member_user_ids(body.chat_id):
            if rid == current_user_id:
                continue
            await send_push_to_user(
                db,
                user_id=rid,
                title="Новое сообщение",
                body="У тебя новое сообщение",
            )
    except Exception:
        logger.exception("Не удалось отправить push после сообщения в чат %s", body.chat_id)

    return _message_response_from_row(row)


async def list_user_chats(db: Database, current_user_id: int) -> list[ChatResponse]:
    """
    Список чатов с превью последнего сообщения и числом непрочитанных входящих
    (по таблице message_reads).
    """
    await support_chat_util.ensure_user_in_support_chat(db, current_user_id)
    rows = await db.get_user_chats(current_user_id)
    out: list[ChatResponse] = []
    for r in rows:
        d = dict(r)
        cid = int(d["id"])
        last = await db.get_last_message_for_chat(cid)
        if last:
            d["last_message_text"] = last.get("text")
            d["last_message_created_at"] = last.get("created_at")
        else:
            d["last_message_text"] = None
            d["last_message_created_at"] = None
        d["unread_count"] = await db.get_unread_count(cid, current_user_id)
        await _enrich_chat_display_fields(db, d, current_user_id)
        out.append(_chat_response_from_row(d))
    return out


async def patch_chat(
    db: Database,
    current_user_id: int,
    chat_id: int,
    body: PatchChatRequest,
) -> ChatResponse:
    """Обновить title и при необходимости description; direct — любой участник, иначе — owner."""
    await _ensure_user_not_banned_for_api(db, current_user_id)
    member = await db.get_chat_member(chat_id, current_user_id)
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Вы не состоите в этом чате",
        )
    chat = await db.get_chat(chat_id)
    if chat is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Чат не найден",
        )

    ctype = str(chat.get("type") or "")
    if ctype == "support":
        if not await db.rbac_user_has_any_role(current_user_id, OPERATIONAL_STAFF_ROLES):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Переименование чата поддержки доступно только сотрудникам",
            )
    elif ctype != "direct" and member.get("role") != "owner":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Только владелец может менять название этого чата",
        )

    dump = body.model_dump(exclude_unset=True)
    title = str(dump["title"]).strip()
    if not title:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Название не может быть пустым",
        )

    update_description = "description" in dump
    desc_val: str | None = None
    if update_description:
        raw = dump["description"]
        if raw is None:
            desc_val = None
        else:
            desc_val = str(raw).strip() or None

    await db.update_chat_metadata(
        chat_id,
        title=title,
        description=desc_val,
        update_description=update_description,
    )

    payload = await _chat_payload_for_user(db, chat_id, current_user_id)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Не удалось загрузить чат после обновления",
        )
    return await _finalize_chat_response(db, payload, current_user_id)


async def mark_chat_as_read(
    db: Database,
    current_user_id: int,
    body: MarkReadRequest,
) -> dict[str, bool]:
    """
    Прочитать все сообщения чата до message_id включительно + обновить last_read_message_id в настройках.
    """
    await _ensure_user_not_banned_for_api(db, current_user_id)
    member = await db.get_chat_member(body.chat_id, current_user_id)
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Вы не состоите в этом чате",
        )

    msg = await db.get_message_by_id(body.message_id)
    if msg is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сообщение не найдено",
        )
    if int(msg["chat_id"]) != body.chat_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Сообщение не принадлежит этому чату",
        )

    await db.mark_chat_read_up_to(body.chat_id, current_user_id, body.message_id)
    await db.update_last_read_message(current_user_id, body.message_id)
    return {"ok": True}


async def list_chat_messages(
    db: Database,
    current_user_id: int,
    chat_id: int,
    limit: int = 50,
    before_id: int | None = None,
) -> list[MessageResponse]:
    """История сообщений; только для участников чата."""
    if limit < 1 or limit > 200:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Параметр limit должен быть от 1 до 200",
        )

    member = await db.get_chat_member(chat_id, current_user_id)
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Вы не состоите в этом чате",
        )

    rows = await db.get_messages(chat_id, limit=limit, before_id=before_id)
    return [_message_response_from_row(r) for r in rows]
