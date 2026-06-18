"""The intent allow-list — the gateway's hard security boundary.

The model and gateway communicate with the app ONLY via this closed set of typed
intents. Anything that does not validate against this union is rejected before it
ever reaches the app. There is deliberately no "run command" / "eval" intent: the
app maps each intent to a pre-built, safe handler. This is what replaces the original
"execute the command embedded in the response" idea.
"""

from __future__ import annotations

from typing import Annotated, Literal, Union

from pydantic import BaseModel, Field

Lang = Literal["fa", "en", "nl"]
Confidence = Literal["grounded", "partial", "insufficient"]

# Quran bounds — used to validate any surah/ayah reference.
SURAH_COUNT = 114
AYAH_COUNTS: dict[int, int] = {
    # surah_number -> number of ayat. Seeded for what we ship; extend as content grows.
    1: 7,
    2: 286,
    36: 83,
    112: 4,
    113: 5,
    114: 6,
}


class Citation(BaseModel):
    """Source attribution attached to every interpretive answer."""

    book: str
    author: str
    ref: str
    lang: Lang
    excerpt: str | None = None


class SpeakIntent(BaseModel):
    action: Literal["speak"] = "speak"
    lang: Lang
    text: str
    voice: str = "default"


class OpenAyahIntent(BaseModel):
    action: Literal["open_ayah"] = "open_ayah"
    surah: int = Field(ge=1, le=SURAH_COUNT)
    ayah: int = Field(ge=1)


class PlayRecitationIntent(BaseModel):
    action: Literal["play_recitation"] = "play_recitation"
    surah: int = Field(ge=1, le=SURAH_COUNT)
    from_ayah: int = Field(ge=1, alias="from")
    to_ayah: int = Field(ge=1, alias="to")
    qari: str | None = None
    repeat: int = Field(default=1, ge=1, le=100)

    model_config = {"populate_by_name": True}


class ShowTafsirIntent(BaseModel):
    action: Literal["show_tafsir"] = "show_tafsir"
    surah: int = Field(ge=1, le=SURAH_COUNT)
    ayah: int = Field(ge=1)
    text: str
    sources: list[Citation] = Field(default_factory=list)


class AnswerIntent(BaseModel):
    action: Literal["answer"] = "answer"
    text: str
    sources: list[Citation] = Field(default_factory=list)
    confidence: Confidence = "partial"


class ShowStoryIntent(BaseModel):
    action: Literal["show_story"] = "show_story"
    story_id: str
    lang: Lang


class SetBookmarkIntent(BaseModel):
    action: Literal["set_bookmark"] = "set_bookmark"
    surah: int = Field(ge=1, le=SURAH_COUNT)
    ayah: int = Field(ge=1)


class NoneIntent(BaseModel):
    action: Literal["none"] = "none"
    reason: str = ""


Intent = Annotated[
    Union[
        SpeakIntent,
        OpenAyahIntent,
        PlayRecitationIntent,
        ShowTafsirIntent,
        AnswerIntent,
        ShowStoryIntent,
        SetBookmarkIntent,
        NoneIntent,
    ],
    Field(discriminator="action"),
]


def ayah_in_bounds(surah: int, ayah: int) -> bool:
    """Range-check an ayah against the known surah length (defense in depth)."""
    max_ayah = AYAH_COUNTS.get(surah)
    if max_ayah is None:
        # Unknown surah length: accept the surah bound only, let content layer 404.
        return 1 <= surah <= SURAH_COUNT and ayah >= 1
    return 1 <= ayah <= max_ayah
