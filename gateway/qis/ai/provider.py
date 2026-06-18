"""AIProvider abstraction — the single seam that lets us swap Claude CLI -> OpenAI.

The gateway depends ONLY on this protocol. Providers are selected by config
(``AI_PROVIDER``). Swapping providers must never require an app change.
"""

from __future__ import annotations

from typing import Protocol

from qis.config import Settings
from qis.schema.models import ReasonRequest, ReasonResult


class AIProvider(Protocol):
    name: str

    async def reason(self, req: ReasonRequest) -> ReasonResult:
        """Produce grounded, cited text from the retrieved corpus.

        Must NOT invent tafsir/hadith outside ``req.retrieved`` and must prefer
        ``confidence="insufficient"`` over guessing.
        """
        ...


def build_provider(settings: Settings) -> AIProvider:
    """Factory: pick the provider from config. This is the whole migration switch."""
    if settings.ai_provider == "openai":
        from qis.ai.openai_provider import OpenAiProvider

        return OpenAiProvider(settings)
    from qis.ai.claude_cli import ClaudeCliProvider

    return ClaudeCliProvider(settings)
