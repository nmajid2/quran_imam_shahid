"""Voice round-trip — the original MVP flow, done safely.

    audio --> STT (Whisper) --> transcript
          --> classify into ALLOW-LISTED intents
          --> (questions) retrieve + reason --> answer intent
    return { transcript, intents[] }   # never raw commands

STT/TTS are powered by OpenAI when ``OPENAI_API_KEY`` is set (see qis/voice/speech.py).
When no key is configured the engine is absent and:
  * ``/v1/stt`` and ``/v1/voice`` accept an optional ``transcript`` form field as a
    dev override so the pipeline stays testable;
  * ``/v1/tts`` returns 503 with a clear message.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile
from fastapi.responses import Response

from qis.ai.provider import AIProvider
from qis.auth import require_token
from qis.content.store import ContentStore, get_store
from qis.schema.intents import AnswerIntent, Lang, NoneIntent
from qis.schema.models import (
    ReasonRequest,
    TtsRequest,
    VoiceResponse,
)
from qis.voice.classify import classify_navigation, looks_like_question
from qis.voice.speech import SpeechEngine

router = APIRouter(prefix="/v1", dependencies=[Depends(require_token)])


def get_provider(request: Request) -> AIProvider:
    return request.app.state.provider


def get_speech(request: Request) -> SpeechEngine | None:
    return request.app.state.speech


_ALLOWED_LANGS = {"fa", "en", "nl"}


def _normalize_lang(detected: str, requested: Lang) -> Lang:
    """Whisper may report a language outside our supported set — fall back safely."""
    return detected if detected in _ALLOWED_LANGS else requested  # type: ignore[return-value]


async def _transcribe(
    audio: UploadFile | None,
    override: str | None,
    lang: Lang,
    speech: SpeechEngine | None,
) -> tuple[str, str]:
    if override:
        return override.strip(), lang
    if audio is not None and speech is not None:
        data = await audio.read()
        text, detected = await speech.transcribe(data, audio.filename or "audio.webm", lang)
        return text, _normalize_lang(detected, lang)
    raise HTTPException(
        status_code=503,
        detail=(
            "Speech-to-text unavailable: set OPENAI_API_KEY to enable Whisper, "
            "or send a 'transcript' field."
        ),
    )


@router.post("/stt")
async def stt(
    audio: UploadFile | None = None,
    transcript: str | None = Form(default=None),
    lang: Lang = Form(default="en"),
    speech: SpeechEngine | None = Depends(get_speech),
) -> dict:
    text, detected = await _transcribe(audio, transcript, lang, speech)
    return {"transcript": text, "lang": detected}


@router.post("/voice", response_model=VoiceResponse)
async def voice(
    audio: UploadFile | None = None,
    transcript: str | None = Form(default=None),
    lang: Lang = Form(default="en"),
    store: ContentStore = Depends(get_store),
    provider: AIProvider = Depends(get_provider),
    speech: SpeechEngine | None = Depends(get_speech),
) -> VoiceResponse:
    text, detected = await _transcribe(audio, transcript, lang, speech)

    # 1) Try a deterministic navigation/recitation command.
    nav = classify_navigation(text, detected)
    if nav is not None:
        return VoiceResponse(transcript=text, lang=detected, intents=[nav])

    # 2) Otherwise treat it as a question -> grounded answer.
    if looks_like_question(text):
        result = await provider.reason(
            ReasonRequest(task="qa", lang=detected, user_text=text, retrieved=[])
        )
        answer = AnswerIntent(
            text=result.text, sources=result.sources, confidence=result.confidence
        )
        return VoiceResponse(transcript=text, lang=detected, intents=[answer])

    # 3) Nothing actionable.
    return VoiceResponse(
        transcript=text,
        lang=detected,
        intents=[NoneIntent(reason="No recognized command or question")],
    )


@router.post("/tts")
async def tts(
    body: TtsRequest,
    speech: SpeechEngine | None = Depends(get_speech),
) -> Response:
    if speech is None:
        raise HTTPException(
            status_code=503,
            detail="Text-to-speech unavailable: set OPENAI_API_KEY to enable TTS.",
        )
    audio = await speech.synthesize(body.text, body.lang, body.voice)
    return Response(content=audio, media_type="audio/mpeg")
