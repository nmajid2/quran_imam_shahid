"""Request/response models for the gateway API and the AI provider interface."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

from qis.schema.intents import Citation, Confidence, Intent, Lang

# ---- AI provider interface (the migration seam) ----

ReasonTask = Literal["tafsir", "qa", "child_story", "translate_explain"]


class AyahRef(BaseModel):
    surah: int = Field(ge=1, le=114)
    ayah: int = Field(ge=1)


class Passage(BaseModel):
    """A retrieved chunk from the vetted corpus — the ONLY ground truth for reasoning."""

    text: str
    citation: Citation


class Turn(BaseModel):
    role: Literal["user", "assistant"]
    text: str


class ReasonRequest(BaseModel):
    task: ReasonTask
    lang: Lang
    ayah_ref: AyahRef | None = None
    user_text: str | None = None
    retrieved: list[Passage] = Field(default_factory=list)
    history: list[Turn] = Field(default_factory=list)


class ReasonResult(BaseModel):
    text: str
    sources: list[Citation] = Field(default_factory=list)
    confidence: Confidence = "partial"
    suggested_intents: list[Intent] = Field(default_factory=list)


# ---- API request bodies ----


class AskRequest(BaseModel):
    text: str
    lang: Lang = "en"
    ayah_ref: AyahRef | None = None


class TafsirRequest(BaseModel):
    surah: int = Field(ge=1, le=114)
    ayah: int = Field(ge=1)
    lang: Lang = "en"


class TtsRequest(BaseModel):
    text: str
    lang: Lang = "en"
    voice: str = "default"


# ---- API response bodies ----


class AskResponse(BaseModel):
    answer: str
    sources: list[Citation]
    confidence: Confidence


class TafsirResponse(BaseModel):
    surah: int
    ayah: int
    text: str
    sources: list[Citation]
    confidence: Confidence


class VoiceResponse(BaseModel):
    transcript: str
    lang: Lang
    intents: list[Intent]
