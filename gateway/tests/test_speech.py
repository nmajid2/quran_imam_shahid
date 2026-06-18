"""Speech wiring tests — use a fake engine, never the real OpenAI API."""

from fastapi.testclient import TestClient

from qis.config import get_settings
from qis.main import create_app
from qis.routes.voice import get_speech
from qis.voice.speech import build_speech_engine
from tests.conftest import AUTH


class FakeSpeech:
    async def transcribe(self, audio, filename, lang):
        return "open surah ikhlas", lang or "en"

    async def synthesize(self, text, lang, voice):
        return b"ID3-fake-mp3-bytes"


def _client_with_speech():
    app = create_app()
    app.dependency_overrides[get_speech] = lambda: FakeSpeech()
    return TestClient(app)


def test_no_engine_when_key_absent():
    # conftest forces OPENAI_API_KEY="" -> no engine built.
    assert build_speech_engine(get_settings()) is None


def test_stt_with_audio_uses_engine():
    client = _client_with_speech()
    with client:
        r = client.post(
            "/v1/stt",
            headers=AUTH,
            files={"audio": ("a.webm", b"\x00\x01", "audio/webm")},
            data={"lang": "en"},
        )
    assert r.status_code == 200
    assert r.json()["transcript"] == "open surah ikhlas"


def test_voice_with_audio_classifies_intent():
    client = _client_with_speech()
    with client:
        r = client.post(
            "/v1/voice",
            headers=AUTH,
            files={"audio": ("a.webm", b"\x00\x01", "audio/webm")},
            data={"lang": "en"},
        )
    assert r.status_code == 200
    assert r.json()["intents"][0]["action"] == "open_ayah"
    assert r.json()["intents"][0]["surah"] == 112


def test_tts_returns_audio():
    client = _client_with_speech()
    with client:
        r = client.post("/v1/tts", headers=AUTH, json={"text": "salam", "lang": "en"})
    assert r.status_code == 200
    assert r.headers["content-type"] == "audio/mpeg"
    assert r.content == b"ID3-fake-mp3-bytes"
