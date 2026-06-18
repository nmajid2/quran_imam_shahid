# Gateway — Quran Imam Shahid

FastAPI gateway that sits between the Flutter app and the AI/speech backends. It owns
all secrets, enforces the **intent allow-list** (the security boundary), and abstracts
the AI provider so we can swap **Claude CLI → OpenAI** without touching the app.

See [../TECHNICAL_DESIGN.md](../TECHNICAL_DESIGN.md) for the full design.

## Quick start

```bash
cd gateway
python3 -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env          # set DEVICE_TOKEN at minimum
uvicorn qis.main:app --reload --port 8077
```

Test it:

```bash
curl localhost:8077/healthz
curl -H "Authorization: Bearer <DEVICE_TOKEN>" localhost:8077/v1/quran/1
```

Run tests:

```bash
. .venv/bin/activate && pytest -q
```

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET  | `/healthz` | no | Liveness |
| GET  | `/v1/quran` | yes | List surahs (metadata) |
| GET  | `/v1/quran/{surah}` | yes | Surah text + fa/en/nl translations |
| POST | `/v1/tafsir` | yes | Per-ayah tafsir, cited & grounded |
| POST | `/v1/ask` | yes | RAG Q&A, cited & grounded |
| POST | `/v1/voice` | yes | Audio/transcript → validated intents |
| POST | `/v1/stt` | yes | Speech → text |
| POST | `/v1/tts` | yes | Text → speech |

## Design notes

- **Auth:** single-user `Authorization: Bearer <DEVICE_TOKEN>`, constant-time compare.
- **Intent allow-list:** [`qis/schema/intents.py`](qis/schema/intents.py) is a closed
  discriminated union. Anything else is rejected — there is no "run command" intent.
- **AI provider seam:** [`qis/ai/provider.py`](qis/ai/provider.py) selects
  `ClaudeCliProvider` (now) or `OpenAiProvider` (Phase 7) via `AI_PROVIDER`.
- **Grounding:** reasoning answers only from retrieved passages and cites sources; with
  no corpus match it returns `confidence: "insufficient"` instead of guessing.

## OpenAI integration

Set `OPENAI_API_KEY` (in the **project-root `.env`** — loaded automatically — or
`gateway/.env`, or a real env var) to enable:

- **Whisper STT** — `/v1/stt` and `/v1/voice` transcribe uploaded audio.
- **TTS** — `/v1/tts` returns `audio/mpeg`.
- **OpenAI reasoning** — set `AI_PROVIDER=openai` to use `OpenAiProvider` instead of the
  Claude CLI (same interface, no app changes).

Without a key the gateway still runs: STT/TTS degrade to a `transcript` form override / 503.
Verified live: TTS → Whisper round-trip and a real TTS synthesis both succeed.

## Not wired yet (needs decisions)

- **Real tafsir corpus + vector retrieval** — currently RAG-lite (exact ayah match over
  a small seed). Replace `ContentStore.retrieve` with pgvector search.
- **Claude CLI prompt tuning** — provider falls back to a grounded summary if the CLI is
  absent or returns non-JSON.
