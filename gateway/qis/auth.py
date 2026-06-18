"""Single-user Bearer-token auth. The whole gateway sits behind this."""

from __future__ import annotations

import hmac

from fastapi import Depends, Header, HTTPException, status

from qis.config import Settings, get_settings


def require_token(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> None:
    """Reject anything without the correct ``Authorization: Bearer <device-token>``.

    Uses a constant-time compare so the token can't be guessed by timing.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = authorization.removeprefix("Bearer ").strip()
    if not hmac.compare_digest(token, settings.device_token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
            headers={"WWW-Authenticate": "Bearer"},
        )
