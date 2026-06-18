"""Quran content endpoints — seeded into the app for offline use."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from qis.auth import require_token
from qis.content.store import ContentStore, get_store

router = APIRouter(prefix="/v1", dependencies=[Depends(require_token)])


def _surah_payload(s, include_ayat: bool = True) -> dict:
    payload = {
        "number": s.number,
        "name_ar": s.name_ar,
        "name_translit": s.name_translit,
        "names": s.names,
        "revelation_place": s.revelation_place,
        "ayah_count": len(s.ayat),
    }
    if include_ayat:
        payload["ayat"] = [
            {"ayah": a.ayah, "text_ar": a.text_ar, "translations": a.translations}
            for a in s.ayat
        ]
    return payload


@router.get("/quran")
async def list_surahs(store: ContentStore = Depends(get_store)) -> dict:
    return {"surahs": [_surah_payload(s, include_ayat=False) for s in store.list_surahs()]}


@router.get("/quran/{surah}")
async def get_surah(surah: int, store: ContentStore = Depends(get_store)) -> dict:
    s = store.get_surah(surah)
    if not s:
        raise HTTPException(status_code=404, detail=f"Surah {surah} not in content store")
    return _surah_payload(s)
