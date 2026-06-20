"""Recitation audio endpoints.

The app reads the reciter catalog and resolves per-ayah MP3 URLs through the gateway
(single source of truth for the audio scheme), then streams or downloads the static
files for offline use. URLs are validated against the content store so the app never
gets a link to an ayah that doesn't exist.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from qis.auth import require_token
from qis.content.reciters import ReciterCatalog, get_catalog
from qis.content.store import ContentStore, get_store

router = APIRouter(prefix="/v1", dependencies=[Depends(require_token)])


@router.get("/reciters")
async def list_reciters(catalog: ReciterCatalog = Depends(get_catalog)) -> dict:
    return {
        "default": catalog.default_id,
        "reciters": [r.to_payload() for r in catalog.list_reciters()],
    }


@router.get("/audio/{reciter_id}/{surah}/{ayah}")
async def get_ayah_audio(
    reciter_id: str,
    surah: int,
    ayah: int,
    catalog: ReciterCatalog = Depends(get_catalog),
    store: ContentStore = Depends(get_store),
) -> dict:
    if not catalog.get(reciter_id):
        raise HTTPException(status_code=404, detail=f"Unknown reciter '{reciter_id}'")
    if not store.get_ayah(surah, ayah):
        raise HTTPException(status_code=404, detail=f"Ayah {surah}:{ayah} not found")
    return {
        "reciter_id": reciter_id,
        "surah": surah,
        "ayah": ayah,
        "url": catalog.audio_url(reciter_id, surah, ayah),
    }


@router.get("/audio/{reciter_id}/{surah}")
async def get_surah_audio(
    reciter_id: str,
    surah: int,
    catalog: ReciterCatalog = Depends(get_catalog),
    store: ContentStore = Depends(get_store),
) -> dict:
    """All per-ayah URLs for a surah — used by the offline downloader / full-surah play."""
    if not catalog.get(reciter_id):
        raise HTTPException(status_code=404, detail=f"Unknown reciter '{reciter_id}'")
    s = store.get_surah(surah)
    if not s:
        raise HTTPException(status_code=404, detail=f"Surah {surah} not found")
    return {
        "reciter_id": reciter_id,
        "surah": surah,
        "ayah_count": len(s.ayat),
        "urls": [
            {"ayah": a.ayah, "url": catalog.audio_url(reciter_id, surah, a.ayah)}
            for a in s.ayat
        ],
    }
