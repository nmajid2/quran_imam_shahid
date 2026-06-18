"""Tafsir + interactive Q&A — retrieval-grounded, always cited."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from qis.ai.provider import AIProvider
from qis.auth import require_token
from qis.content.store import ContentStore, get_store
from qis.schema.models import (
    AskRequest,
    AskResponse,
    ReasonRequest,
    TafsirRequest,
    TafsirResponse,
)

router = APIRouter(prefix="/v1", dependencies=[Depends(require_token)])


def get_provider(request: Request) -> AIProvider:
    return request.app.state.provider


@router.post("/tafsir", response_model=TafsirResponse)
async def tafsir(
    body: TafsirRequest,
    store: ContentStore = Depends(get_store),
    provider: AIProvider = Depends(get_provider),
) -> TafsirResponse:
    if store.get_ayah(body.surah, body.ayah) is None:
        raise HTTPException(status_code=404, detail="Ayah not in content store")
    passages = store.retrieve(body.surah, body.ayah, body.lang)
    result = await provider.reason(
        ReasonRequest(
            task="tafsir",
            lang=body.lang,
            ayah_ref={"surah": body.surah, "ayah": body.ayah},
            retrieved=passages,
        )
    )
    return TafsirResponse(
        surah=body.surah,
        ayah=body.ayah,
        text=result.text,
        sources=result.sources,
        confidence=result.confidence,
    )


@router.post("/ask", response_model=AskResponse)
async def ask(
    body: AskRequest,
    store: ContentStore = Depends(get_store),
    provider: AIProvider = Depends(get_provider),
) -> AskResponse:
    passages = []
    if body.ayah_ref is not None:
        passages = store.retrieve(body.ayah_ref.surah, body.ayah_ref.ayah, body.lang)
    result = await provider.reason(
        ReasonRequest(
            task="qa",
            lang=body.lang,
            ayah_ref=body.ayah_ref,
            user_text=body.text,
            retrieved=passages,
        )
    )
    return AskResponse(
        answer=result.text,
        sources=result.sources,
        confidence=result.confidence,
    )
