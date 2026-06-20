"""Book-tafsir endpoints — verified Shia commentary the user can read and choose.

Distinct from `POST /v1/tafsir` (the AI-grounded summary). These serve the raw,
human-authored tafsir text per ayah from the bundled Shia sources.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from qis.auth import require_token
from qis.content.store import ContentStore, get_store
from qis.content.tafsir import ATTRIBUTION, TafsirStore, get_tafsir_store

router = APIRouter(prefix="/v1", dependencies=[Depends(require_token)])


@router.get("/tafsirs")
async def list_tafsirs(tafsir: TafsirStore = Depends(get_tafsir_store)) -> dict:
    return {
        "attribution": ATTRIBUTION,
        "tafsirs": [e.to_payload() for e in tafsir.list_editions()],
    }


@router.get("/tafsir/{tafsir_id}/{surah}/{ayah}")
async def get_tafsir(
    tafsir_id: str,
    surah: int,
    ayah: int,
    tafsir: TafsirStore = Depends(get_tafsir_store),
    store: ContentStore = Depends(get_store),
) -> dict:
    if tafsir.get_edition(tafsir_id) is None:
        raise HTTPException(status_code=404, detail=f"Unknown tafsir '{tafsir_id}'")
    if store.get_ayah(surah, ayah) is None:
        raise HTTPException(status_code=404, detail=f"Ayah {surah}:{ayah} not found")
    result = tafsir.retrieve(tafsir_id, surah, ayah)
    if result is None:
        raise HTTPException(
            status_code=404,
            detail=f"No {tafsir_id} commentary for {surah}:{ayah}",
        )
    return {
        "tafsir_id": tafsir_id,
        "surah": surah,
        "ayah": ayah,
        "ayah_start": result.ayah_start,
        "ayah_end": result.ayah_end,
        "content": result.content,
        "format": "markdown",
        "attribution": ATTRIBUTION,
    }


@router.get("/tafsir/{tafsir_id}/{surah}")
async def get_surah_tafsir(
    tafsir_id: str,
    surah: int,
    tafsir: TafsirStore = Depends(get_tafsir_store),
    store: ContentStore = Depends(get_store),
) -> dict:
    """All commentary for a surah (deduped blocks + ayah→block index) — offline use."""
    if tafsir.get_edition(tafsir_id) is None:
        raise HTTPException(status_code=404, detail=f"Unknown tafsir '{tafsir_id}'")
    if store.get_surah(surah) is None:
        raise HTTPException(status_code=404, detail=f"Surah {surah} not found")
    data = tafsir.retrieve_surah(tafsir_id, surah)
    if data is None:
        raise HTTPException(status_code=404, detail="No commentary for this surah")
    return {
        "tafsir_id": tafsir_id,
        "surah": surah,
        "format": "markdown",
        "attribution": ATTRIBUTION,
        "blocks": data["blocks"],
        "ayah_to_block": {str(k): v for k, v in data["ayah_to_block"].items()},
    }
