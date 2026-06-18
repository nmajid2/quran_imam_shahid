# Quran Imam Shahid

A personal, cross-platform (Android / iOS / Web) Quran companion focused on **deep
learning**: read daily, hear correct recitation, understand authentic **Shia tafsir**,
ask questions interactively, track reading, **memorize ayah-by-ayah**, and a safe
AI-narrated children's section.

## Documentation

| Doc | What |
|-----|------|
| [REQUIREMENTS.md](REQUIREMENTS.md) | Vision, personas, features, risks, roadmap summary |
| [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) | Architecture, intent schema, API contract, RAG, Hifz engine |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Authoritative phased plan (tasks, deliverables, exit criteria) |

## Repository

```
quran_imam_shahid/
├── gateway/    FastAPI gateway — auth, intent allow-list, AI provider seam, content+RAG (RUNS + TESTED)
├── app/        Flutter app — Quran reader, tafsir, language switch (skeleton; needs Flutter SDK)
└── content/    (future) ingestion scripts for Quran text + vetted tafsir corpus
```

## Architecture (one line)

The **app** talks only to the **gateway** over HTTPS + a device token. The gateway owns
all secrets, validates every model output against a closed **intent allow-list** (no
arbitrary command execution), and abstracts the AI backend so **Claude CLI → OpenAI** is
a config flip, not a rewrite. See [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md).

## Run it (current slice)

```bash
# 1) Gateway
cd gateway
python3 -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env          # set DEVICE_TOKEN
uvicorn qis.main:app --port 8077
# pytest -q   # 22 tests

# 2) App (needs Flutter SDK installed)
cd ../app
flutter pub get
flutter run --dart-define=GATEWAY_URL=http://localhost:8077 --dart-define=DEVICE_TOKEN=<token>
```

## Status

- ✅ **Phase 0–1 backbone:** gateway with auth, intent allow-list, AI-provider seam,
  Quran content (Al-Fatiha + Al-Ikhlas, ar/fa/en/nl), tafsir + Q&A (grounded/cited),
  voice→intent classification. 22 passing tests.
- ✅ **App skeleton:** surah list, ayah reader (Arabic RTL + translation), tafsir sheet
  with citations + confidence, language switch (fa/en/nl).
- ⏭️ **Next:** ayah audio + offline cache, voice round-trip wiring, then Q&A chat,
  recitation coaching, and the Hifz memorization tracker.

Provider/content decisions still open are tracked in [REQUIREMENTS.md §12](REQUIREMENTS.md).
