"""HTTP API друзей и заявок."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.auth.dependencies import get_current_user, get_db
from app.database.database import Database
from app.friends.schemas import (
    FriendRequestCreate,
    FriendRequestItem,
    FriendStatusResponse,
    FriendUserSnippet,
    FriendshipResponse,
)
from app.friends.service import FriendsService, get_status_response

router = APIRouter(tags=["Friends"])


def _svc(db: Database) -> FriendsService:
    return FriendsService(db)


@router.post("/request", response_model=FriendshipResponse, status_code=status.HTTP_201_CREATED)
async def send_friend_request(
    body: FriendRequestCreate,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> FriendshipResponse:
    uid = int(user["id"])
    return await _svc(db).request(uid, body.target_user_id)


@router.post("/accept/{request_id}", response_model=FriendshipResponse)
async def accept_friend_request(
    request_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> FriendshipResponse:
    return await _svc(db).accept(int(user["id"]), request_id)


@router.post("/decline/{request_id}", status_code=status.HTTP_204_NO_CONTENT)
async def decline_friend_request(
    request_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> Response:
    await _svc(db).decline(int(user["id"]), request_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/cancel/{target_user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_outgoing_request(
    target_user_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> Response:
    await _svc(db).cancel(int(user["id"]), target_user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/block/{other_user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unblock_user(
    other_user_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> Response:
    await _svc(db).unblock(int(user["id"]), other_user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{other_user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_friend(
    other_user_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> Response:
    await _svc(db).remove(int(user["id"]), other_user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/block/{other_user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def block_user(
    other_user_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> Response:
    await _svc(db).block(int(user["id"]), other_user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/status/{other_user_id}", response_model=FriendStatusResponse)
async def friendship_status(
    other_user_id: int,
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> FriendStatusResponse:
    return await get_status_response(db, int(user["id"]), other_user_id)


@router.get("/incoming", response_model=list[FriendRequestItem])
async def list_incoming(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[FriendRequestItem]:
    return await _svc(db).list_incoming(int(user["id"]))


@router.get("/outgoing", response_model=list[FriendRequestItem])
async def list_outgoing(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[FriendRequestItem]:
    return await _svc(db).list_outgoing(int(user["id"]))


@router.get("/", response_model=list[FriendUserSnippet])
async def list_friends(
    user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> list[FriendUserSnippet]:
    return await _svc(db).list_friends(int(user["id"]))
