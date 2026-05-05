from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from app.database.db_roles import VALID_ROLES


class OwnerClaimRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    token: str = Field(..., min_length=1)


class OwnerTransferRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_user_id: int = Field(..., gt=0)
    new_self_role: str = Field(..., description="Роль актора после передачи owner (не owner)")


def validate_non_owner_role(role: str) -> str:
    r = role.strip()
    if r not in VALID_ROLES:
        raise ValueError("unknown_role")
    if r == "owner":
        raise ValueError("cannot_be_owner")
    return r
