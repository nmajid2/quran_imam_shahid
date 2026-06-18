"""Liveness probe — unauthenticated by design."""

from __future__ import annotations

from fastapi import APIRouter

from qis import __version__

router = APIRouter()


@router.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok", "version": __version__}
