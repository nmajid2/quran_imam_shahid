"""ClaudeCliProvider — bootstrap provider that shells out to the Claude CLI.

The gateway runs on the same Ubuntu box as the CLI, so the CLI is never exposed to
the internet. The provider assembles a strict, retrieval-grounded prompt and forces
JSON output matching ``ReasonResult``.

To keep the system end-to-end functional before the CLI/prompt are tuned (and in
tests), if the CLI is unavailable or returns unparseable output we fall back to a
deterministic, grounded summary built ONLY from the retrieved passages — never from
model imagination.
"""

from __future__ import annotations

import asyncio
import json

from qis.config import Settings
from qis.schema.intents import Citation
from qis.schema.models import ReasonRequest, ReasonResult

SYSTEM_RULES = (
    "You are a careful Shia Quran study assistant. Answer ONLY from the provided "
    "passages. Never invent tafsir or hadith. Never issue fiqh rulings/fatwas — "
    "redirect those to a qualified marja'. Always cite sources. If the passages do "
    "not support an answer, set confidence to 'insufficient'. Reply as strict JSON "
    "with keys: text, sources, confidence."
)


class ClaudeCliProvider:
    name = "claude_cli"

    def __init__(self, settings: Settings) -> None:
        self._cli = settings.claude_cli_path

    def _build_prompt(self, req: ReasonRequest) -> str:
        ref = f"{req.ayah_ref.surah}:{req.ayah_ref.ayah}" if req.ayah_ref else "n/a"
        passages = "\n\n".join(
            f"[{i}] ({p.citation.book} — {p.citation.author}, {p.citation.ref})\n{p.text}"
            for i, p in enumerate(req.retrieved, 1)
        )
        return (
            f"{SYSTEM_RULES}\n\n"
            f"TASK: {req.task}\nLANG: {req.lang}\nAYAH: {ref}\n"
            f"QUESTION: {req.user_text or ''}\n\n"
            f"PASSAGES:\n{passages or '(none)'}\n"
        )

    async def _run_cli(self, prompt: str) -> str:
        """Invoke the Claude CLI. Raises on any failure so callers can fall back."""
        proc = await asyncio.create_subprocess_exec(
            self._cli,
            "-p",
            prompt,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        if proc.returncode != 0:
            raise RuntimeError(f"claude cli failed: {stderr.decode(errors='ignore')[:200]}")
        return stdout.decode(errors="ignore")

    async def reason(self, req: ReasonRequest) -> ReasonResult:
        prompt = self._build_prompt(req)
        try:
            raw = await self._run_cli(prompt)
            data = json.loads(raw)
            return ReasonResult.model_validate(data)
        except (FileNotFoundError, RuntimeError, json.JSONDecodeError, ValueError):
            return self._fallback(req)

    @staticmethod
    def _fallback(req: ReasonRequest) -> ReasonResult:
        """Grounded-only fallback: summarize the retrieved passages, or admit no basis."""
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
