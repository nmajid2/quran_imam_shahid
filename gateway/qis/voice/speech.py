"""Speech engine — OpenAI Whisper (speech->text) and OpenAI TTS (text->speech).

Built once at startup from settings. If no OpenAI key is configured, the factory
returns ``None`` and the routes degrade gracefully (503 / transcript override), so the
gateway still runs without a key.
"""

from __future__ import annotations

import io
from typing import Protocol

from qis.config import Lang, Settings

# Sensible default voices per language. OpenAI voices are multilingual; these are just
# pleasant defaults and can be overridden per request.
_VOICE_BY_LANG: dict[str, str] = {"fa": "alloy", "en": "alloy", "nl": "alloy"}


class SpeechEngine(Protocol):
    async def transcribe(self, audio: bytes, filename: str, lang: Lang | None) -> tuple[str, str]: ...

    async def synthesize(self, text: str, lang: Lang, voice: str) -> bytes: ...


class OpenAiSpeech:
    def __init__(self, settings: Settings) -> None:
        # Imported lazily so the package imports cleanly even if openai isn't installed.
        from openai import AsyncOpenAI

        self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        self._whisper_model = settings.openai_whisper_model
        self._tts_model = settings.openai_tts_model
        self._default_voice = settings.openai_tts_voice

    async def transcribe(self, audio: bytes, filename: str, lang: Lang | None) -> tuple[str, str]:
        buf = io.BytesIO(audio)
        buf.name = filename or "audio.webm"
        kwargs: dict = {"model": self._whisper_model, "file": buf}
        if lang:
            kwargs["language"] = lang  # ISO-639-1; helps accuracy
        resp = await self._client.audio.transcriptions.create(**kwargs)
        text = resp.text.strip()
        detected = getattr(resp, "language", None) or (lang or "en")
        return text, detected

    async def synthesize(self, text: str, lang: Lang, voice: str) -> bytes:
        chosen = voice if voice and voice != "default" else _VOICE_BY_LANG.get(lang, self._default_voice)
        resp = await self._client.audio.speech.create(
            model=self._tts_model,
            voice=chosen,
            input=text,
        )
        return resp.read()  # mp3 bytes


def build_speech_engine(settings: Settings) -> SpeechEngine | None:
    if not settings.openai_enabled:
        return None
    return OpenAiSpeech(settings)
