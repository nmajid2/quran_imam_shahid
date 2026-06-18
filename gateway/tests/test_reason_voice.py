from tests.conftest import AUTH


# ---- tafsir / ask (grounded fallback when CLI is unavailable) ----


def test_tafsir_returns_grounded_cited_passage(client):
    r = client.post("/v1/tafsir", json={"surah": 1, "ayah": 5, "lang": "en"}, headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    assert data["confidence"] == "grounded"
    assert data["sources"], "tafsir must carry source citations"
    assert "worship" in data["text"].lower()


def test_tafsir_unknown_ayah_404(client):
    r = client.post("/v1/tafsir", json={"surah": 1, "ayah": 99, "lang": "en"}, headers=AUTH)
    assert r.status_code == 404


def test_ask_without_corpus_is_insufficient_not_a_guess(client):
    r = client.post("/v1/ask", json={"text": "What is the meaning of life?", "lang": "en"}, headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    # No retrieved passages -> must admit insufficiency rather than fabricate.
    assert data["confidence"] == "insufficient"
    assert data["sources"] == []


def test_ask_with_ayah_ref_is_grounded(client):
    r = client.post(
        "/v1/ask",
        json={"text": "Explain this verse", "lang": "en", "ayah_ref": {"surah": 112, "ayah": 1}},
        headers=AUTH,
    )
    assert r.status_code == 200
    assert r.json()["confidence"] == "grounded"


# ---- voice round-trip ----


def test_voice_navigation_intent(client):
    r = client.post("/v1/voice", data={"transcript": "open surah fatiha ayah 5", "lang": "en"}, headers=AUTH)
    assert r.status_code == 200
    intents = r.json()["intents"]
    assert intents[0]["action"] == "open_ayah"
    assert intents[0]["surah"] == 1 and intents[0]["ayah"] == 5


def test_voice_play_intent(client):
    r = client.post("/v1/voice", data={"transcript": "play surah yasin", "lang": "en"}, headers=AUTH)
    assert r.status_code == 200
    assert r.json()["intents"][0]["action"] == "play_recitation"


def test_voice_question_routes_to_answer(client):
    r = client.post("/v1/voice", data={"transcript": "what is the meaning of tawhid?", "lang": "en"}, headers=AUTH)
    assert r.status_code == 200
    assert r.json()["intents"][0]["action"] == "answer"


def test_voice_requires_transcript_until_stt_configured(client):
    r = client.post("/v1/voice", data={"lang": "en"}, headers=AUTH)
    assert r.status_code == 503


def test_tts_not_configured_yet(client):
    r = client.post("/v1/tts", json={"text": "salam", "lang": "en"}, headers=AUTH)
    assert r.status_code == 503
