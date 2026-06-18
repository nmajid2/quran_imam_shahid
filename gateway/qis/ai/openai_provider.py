"""OpenAiProvider — reasoning backed by OpenAI (the migration target).

Implements the same AIProvider interface as ClaudeCliProvider. Flip
``AI_PROVIDER=openai`` to use it — zero app changes required. Uses JSON-mode chat
completions and validates the output against ReasonResult; on any failure it falls
back to a grounded, citation-only summary (never invents content).
"""

from __future__ import annotations

import json

from qis.config import Settings
from qis.schema.intents import Citation
from qis.schema.models import ReasonRequest, ReasonResult

SYSTEM_RULES = (
    "You are a careful Shia Quran study assistant. Answer ONLY from the provided "
    "passages. Never invent tafsir or hadith. Never issue fiqh rulings/fatwas — "
    "redirect those to a qualified marja'. Always cite sources. If the passages do "
    "not support an answer, set confidence to 'insufficient'. Reply as strict JSON "
    "with keys: text (string), sources (array of {book, author, ref, lang, excerpt}), "
    "confidence (one of 'grounded'|'partial'|'insufficient')."
)


class OpenAiProvider:
    name = "openai"

    def __init__(self, settings: Settings) -> None:
        from openai import AsyncOpenAI

        self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        self._model = settings.openai_chat_model

    def _user_content(self, req: ReasonRequest) -> str:
        ref = f"{req.ayah_ref.surah}:{req.ayah_ref.ayah}" if req.ayah_ref else "n/a"
        passages = "\n\n".join(
            f"[{i}] ({p.citation.book} — {p.citation.author}, {p.citation.ref})\n{p.text}"
            for i, p in enumerate(req.retrieved, 1)
        )
        return (
            f"TASK: {req.task}\nLANG: {req.lang}\nAYAH: {ref}\n"
            f"QUESTION: {req.user_text or ''}\n\n"
            f"PASSAGES:\n{passages or '(none)'}\n"
        )

    async def reason(self, req: ReasonRequest) -> ReasonResult:
        messages = [
            {"role": "system", "content": SYSTEM_RULES},
            {"role": "user", "content": self._user_content(req)},
        ]
        try:
            resp = await self._client.chat.completions.create(
                model=self._model,
                messages=messages,
                response_format={"type": "json_object"},
                temperature=0.2,
            )
            data = json.loads(resp.choices[0].message.content or "{}")
            return ReasonResult.model_validate(data)
        except Exception:  # network / parse / validation -> grounded fallback
            return self._fallback(req)

    @staticmethod
    def _fallback(req: ReasonRequest) -> ReasonResult:
        if not req.retrieved:
            return ReasonResult(
                text=(
                    "I don't have a sourced basis to answer this yet. Once the tafsir "
                    "corpus is connected I can answer from cited references."
                ),
                sources=[],
                confidence="insufficient",
            )
        sources: list[Citation] = [p.citation for p in req.retrieved]
        joined = " ".join(p.text for p in req.retrieved)
        return ReasonResult(text=joined, sources=sources, confidence="grounded")
