"""Turn a transcript into a small set of validated intents.

This is a deliberately simple, deterministic classifier for the MVP: it recognizes a
few navigation/recitation commands and otherwise routes to the grounded Q&A path. It
NEVER produces free-form commands — only members of the intent allow-list. A smarter
model-based classifier can replace this later without changing the contract.
"""

from __future__ import annotations

import re

from qis.schema.intents import (
    Lang,
    OpenAyahIntent,
    PlayRecitationIntent,
)

# Minimal surah-name resolution (extend as content grows). Keys are lowercased.
SURAH_NAMES: dict[str, int] = {
    "fatiha": 1,
    "fatihah": 1,
    "al-fatiha": 1,
    "opening": 1,
    "baqara": 2,
    "baqarah": 2,
    "yasin": 36,
    "ya-sin": 36,
    "ikhlas": 112,
    "tawhid": 112,
    "sincerity": 112,
    "falaq": 113,
    "nas": 114,
}

OPEN_WORDS = ("open", "go to", "show", "navigate", "take me to")
PLAY_WORDS = ("play", "recite", "recitation", "listen")
QUESTION_WORDS = ("what", "why", "how", "who", "meaning", "explain", "tafsir", "tell me")


def _resolve_surah(text: str) -> int | None:
    for name, num in SURAH_NAMES.items():
        if name in text:
            return num
    m = re.search(r"\bsurah\s+(\d{1,3})", text)
    if m:
        n = int(m.group(1))
        if 1 <= n <= 114:
            return n
    return None


def _resolve_ayah(text: str) -> int | None:
    m = re.search(r"\b(?:ayah|verse|aya)\s+(\d{1,3})", text)
    return int(m.group(1)) if m else None


def looks_like_question(text: str) -> bool:
    t = text.lower()
    return t.strip().endswith("?") or any(w in t for w in QUESTION_WORDS)


def classify_navigation(transcript: str, lang: Lang):
    """Return a navigation/recitation intent if the transcript is a clear command.

    Returns None when the transcript should instead go through the Q&A path.
    """
    t = transcript.lower().strip()
    surah = _resolve_surah(t)
    ayah = _resolve_ayah(t)

    if any(w in t for w in PLAY_WORDS) and surah is not None:
        start = ayah or 1
        return PlayRecitationIntent(surah=surah, **{"from": start, "to": start})

    if any(w in t for w in OPEN_WORDS) and surah is not None:
        return OpenAyahIntent(surah=surah, ayah=ayah or 1)

    return None
