# Quran Imam Shahid — Technical Design

> Companion to [REQUIREMENTS.md](REQUIREMENTS.md). This doc defines the data models,
> the gateway API contract, the action/intent schema, the AI provider abstraction,
> and the RAG design.

**Status:** Draft v0.1 · **Owner:** Majid · **Last updated:** 2026-06-18

### Decisions locked (from requirements review)
- **Scope:** Personal, single-user. → Lighter auth (one shared secret + device token),
  no multi-tenant concerns, no app-store/licensing pressure for now.
- **Languages:** UI + translation + tafsir + narration in **Persian (fa)**,
  **English (en)**, **Dutch (nl)**. Quran source text is always **Arabic (ar)**, RTL.
- **AI backend:** **Now** → Claude CLI on your Ubuntu box, behind a gateway.
  **Later** → migrate **fully to OpenAI**. So everything goes through a provider-
  agnostic interface; swapping providers must not touch the app.

---

## 1. System Overview

```
┌─────────────────────────────┐        HTTPS + Bearer token
│  Flutter app (Android/iOS/   │ ───────────────────────────────┐
│  Web)                        │                                 │
│  • Offline Quran + audio     │ ◄───────────────────────────────┤
│  • Local progress (SQLite)   │     structured JSON (intents)    │
└─────────────────────────────┘                                  │
                                                                  ▼
                                              ┌──────────────────────────────────┐
                                              │  Gateway  (FastAPI, Ubuntu box)   │
                                              │  • auth, rate-limit, schema guard │
                                              │  • owns all API keys/secrets      │
                                              │  • caches AI responses            │
                                              └───────┬───────────┬───────────┬───┘
                                                      │           │           │
                                  AIProvider (swap)   │           │           │
                                      ┌───────────────┘           │           │
                                      ▼                           ▼           ▼
                          ┌────────────────────┐   ┌────────────────┐  ┌────────────┐
                          │ ClaudeCliProvider  │   │  STT (Whisper) │  │ TTS engine │
                          │  (now)             │   │                │  │ (fa/en/nl) │
                          │ OpenAiProvider     │   └────────────────┘  └────────────┘
                          │  (later, full)     │
                          └─────────┬──────────┘
                                    ▼
                          ┌────────────────────┐
                          │  RAG: vetted Shia   │
                          │  tafsir corpus +    │
                          │  vector index       │
                          └────────────────────┘
```

**Golden rule:** the app never receives or runs executable commands. It only receives
**typed intents** from a fixed allow-list (§4). All secrets live on the gateway.

---

## 2. Components & Responsibilities

| Component | Responsibility | Tech |
|-----------|----------------|------|
| **App** | UI, offline reading/audio, local progress, render intents | Flutter (Dart), Drift/SQLite, Riverpod |
| **Gateway** | Auth, rate-limit, schema validation, caching, orchestration | FastAPI (Python), Pydantic |
| **AIProvider** | Reasoning/tafsir/Q&A — pluggable (Claude CLI → OpenAI) | abstract interface |
| **STT** | Recitation/voice → text | Whisper (OpenAI now or local) |
| **TTS** | Text → speech in fa/en/nl | OpenAI TTS / ElevenLabs |
| **RAG** | Retrieve cited tafsir passages for grounding | pgvector + embeddings |
| **Content store** | Quran text, translations, audio manifests, tafsir corpus | Postgres + object storage/CDN |

---

## 3. AI Provider Abstraction (the migration seam)

The single most important design decision for "CLI now, OpenAI later." The gateway
depends only on this interface; providers are swapped by config.

```python
# gateway/ai/provider.py
class AIProvider(Protocol):
    async def reason(self, req: ReasonRequest) -> ReasonResult: ...
    # reason() returns grounded text + cited sources, NOT free commands.

@dataclass
class ReasonRequest:
    task: Literal["tafsir", "qa", "child_story", "translate_explain"]
    lang: Literal["fa", "en", "nl"]
    ayah_ref: AyahRef | None          # e.g. {surah: 2, ayah: 255}
    user_text: str | None             # the question / instruction
    retrieved: list[Passage]          # RAG context (vetted corpus only)
    history: list[Turn]               # session memory (bounded)

@dataclass
class ReasonResult:
    text: str
    sources: list[SourceCitation]     # every claim traceable
    confidence: Literal["grounded", "partial", "insufficient"]
    suggested_intents: list[Intent]   # optional follow-up actions (allow-listed)
```

- **`ClaudeCliProvider` (now):** shells out to your Claude CLI on the Ubuntu box via a
  local subprocess wrapper (the gateway runs on the same box, so the CLI is never
  exposed to the internet). Prompt assembled from `retrieved` passages; forced to
  return JSON matching `ReasonResult`.
- **`OpenAiProvider` (later):** same interface, calls OpenAI with structured output /
  function calling. **Swapping providers requires zero app changes** and only a config
  flag on the gateway.

Provider selected by env: `AI_PROVIDER=claude_cli | openai`.

---

## 4. Action / Intent Schema (security-critical)

The model and gateway communicate with the app **only** via this closed allow-list.
Anything not matching the schema is rejected by the gateway before reaching the app.
No shell, no `eval`, no arbitrary commands — ever.

```jsonc
// Discriminated union on "action"
{ "action": "speak",            "lang": "fa|en|nl", "text": "…", "voice": "default" }
{ "action": "open_ayah",        "surah": 2, "ayah": 255 }
{ "action": "play_recitation",  "surah": 36, "from": 1, "to": 5, "qari": "…", "repeat": 1 }
{ "action": "show_tafsir",      "surah": 2, "ayah": 255, "sources": [Citation], "text": "…" }
{ "action": "answer",           "text": "…", "sources": [Citation], "confidence": "grounded|partial|insufficient" }
{ "action": "show_story",       "story_id": "yunus-01", "lang": "nl" }
{ "action": "set_bookmark",     "surah": 2, "ayah": 255 }
{ "action": "none",             "reason": "…" }   // explicit no-op
```

```jsonc
// Citation — attached to every interpretive answer
{ "book": "al-Mizan", "author": "Tabataba'i", "ref": "vol 16, Surah Yasin", "lang": "fa", "excerpt": "…" }
```

Gateway enforcement:
1. Validate provider output against the Pydantic union → reject/repair on mismatch.
2. Re-validate every field range (surah 1–114, ayah within surah, lang in {fa,en,nl}).
3. App has a **handler per action**; an unknown action is dropped and logged.

---

## 5. Gateway API Contract

Base URL: your Cloudflare-Tunnel host. Auth: `Authorization: Bearer <device-token>`
(single user → one long-lived token minted once, stored in `flutter_secure_storage`).

| Method & path | Purpose | Body → Response |
|---------------|---------|-----------------|
| `POST /v1/voice` | Voice round-trip (the MVP flow) | audio → `{ transcript, intents[] }` |
| `POST /v1/ask` | Text Q&A (RAG) | `{ text, lang, ayah_ref? }` → `{ answer, sources[], confidence }` |
| `POST /v1/tafsir` | Per-ayah tafsir | `{ surah, ayah, lang }` → `{ text, sources[] }` |
| `POST /v1/tts` | Text → speech | `{ text, lang, voice? }` → audio stream (or URL) |
| `POST /v1/stt` | Speech → text only | audio → `{ transcript, lang }` |
| `GET  /v1/quran/{surah}` | Quran text + translations | → ayat[] (cacheable, offline-seeded) |
| `GET  /v1/audio/manifest` | Recitation audio manifest | → per-ayah audio URLs |
| `GET  /v1/stories` | Children's story catalog | → pre-generated, reviewed stories |
| `GET  /healthz` | Liveness | → ok |

### 5.1 The MVP voice flow, end to end
```
1. App records audio (Opus), POST /v1/voice  (multipart)
2. Gateway → STT (Whisper) → transcript (+ detected lang)
3. Gateway classifies intent of transcript:
      - recitation check?  → align vs target ayah, return feedback intent
      - a question?        → RAG retrieve → AIProvider.reason() → answer intent
      - a navigation cmd?  → open_ayah / play_recitation intent
4. Gateway validates resulting intents against the allow-list (§4)
5. Returns { transcript, intents[] }  — NEVER raw commands
6. App executes each intent via its typed handler (e.g. "speak" → local/▶ TTS)
```

---

## 6. Data Models

### 6.1 Content (server, seeded into app for offline)
```
Surah     { number, name_ar, name_translit, name_fa, name_en, name_nl, ayah_count, revelation_place }
Ayah      { surah, ayah, text_uthmani, text_simple, juz, page, sajda? }
Word      { surah, ayah, position, text_ar, translit, root, lemma, gloss_{fa,en,nl} }
Translation { surah, ayah, lang, translator, text }
Recitation  { qari_id, name, surah, ayah, audio_url, duration_ms }
TafsirEntry { surah, ayah, source_id, lang, text, refs[] }     // from vetted corpus
TafsirSource{ id, book, author, edition, lang, license, school: "shia" }
Story       { id, title_{fa,en,nl}, age_tier, scenes[], audio_{fa,en,nl}, reviewed_by, status }
```

### 6.2 Personal data (local-first, optional cloud sync)
```
ReadingProgress { surah, ayah, state: read|listened|memorized, updated_at }
Bookmark        { surah, ayah, note?, created_at }
Highlight       { surah, ayah, range, color, note? }
Streak          { current, longest, last_active_date, daily_goal }
KhatmPlan       { start_date, target_date, daily_portion, completed_ayat }
RecitationScore { surah, ayah, accuracy, tajweed_issues[], recorded_at }

// --- Hifz (memorization) — see §13 ---
HifzPlan        { id, scope: quran|juz|surah|range, range_from, range_to,
                  daily_new_target, start_date, projected_end_date, active }
AyahMemo        { surah, ayah, plan_id,
                  state: new|learning|memorized|reviewing|mastered,
                  ease, interval_days, due_date, reps, lapses,
                  last_reviewed_at, last_result, best_accuracy }
HifzSession     { id, date, new_done[], reviews_done[], passed, failed }
HifzStreak      { current, longest, last_active_date, daily_new_goal }
Note            { id, surah?, ayah?, body, tags[], created_at }
QaSession       { id, turns[], created_at }
```
Single user → progress lives in local SQLite as source of truth; optional encrypted
backup to object storage. No multi-user tables needed.

---

## 7. RAG Design (trust backbone)

```
Ingest:  vetted Shia tafsir corpus (§6.2 of REQUIREMENTS)
         → chunk per ayah / per passage, keep source metadata
         → embed (multilingual model covering ar/fa/en/nl)
         → store in pgvector with {surah, ayah, source_id, lang}

Query:   user question (+ optional ayah_ref, lang)
         → embed → top-k retrieve, filtered by ayah/theme
         → pass passages as the ONLY ground truth to AIProvider.reason()
         → model answers strictly from passages, emits Citations
         → if retrieval is weak → confidence:"insufficient" → app shows
           "I don't have a solid basis for this — consult a scholar."
```

Guardrails baked into the reason prompt:
- Never assert tafsir/hadith not present in `retrieved`.
- No fiqh rulings/fatwas → redirect to a qualified marja'/scholar.
- Always attach citations; prefer "insufficient" over guessing.
- Arabic ayah text is passed verbatim from the content store, never regenerated.

---

## 7b. Hifz Engine — Memorization (ayah-by-ayah, daily)

Implements §4.6 of REQUIREMENTS. Fully **local/offline** (lives in SQLite); the only
optional server touch is STT for the "recite-from-memory" check.

### Per-ayah state machine
```
new ──(start learning)──► learning ──(self-recite passes)──► memorized
   ▲                          ▲                                  │
   │                          │                            (enters review queue)
   │                          │                                  ▼
mastered ◄──(N clean reviews)── reviewing ◄──────(review due)────┘
                                   │
                                   └──(repeated lapses)──► learning   // re-learn
```

### Daily session assembly
```
buildToday(date):
  due      = AyahMemo where state in {memorized, reviewing} and due_date <= date
             order by due_date           // oldest-due first
  newPool  = next `daily_new_target` ayat in plan with state = new (in mushaf order)
  return { reviews: due, new: newPool }   // home screen: "3 new + 12 reviews due"
```

### Spaced repetition (SM-2 style, per ayah)
```
review(ayah, quality 0..5):     // quality from self-recite accuracy or manual tap
  if quality < 3:               // lapse
     reps = 0; interval = 1; lapses += 1
     if lapses >= LAPSE_LIMIT: state = learning      // forgiveness / re-learn
  else:
     reps += 1
     interval = reps==1 ? 1 : reps==2 ? 6 : round(interval * ease)
     state = (reps >= MASTERY_REPS) ? mastered : reviewing
  ease = clamp(ease + (0.1 - (5-quality)*(0.08 + (5-quality)*0.02)), 1.3, 2.7)
  due_date = date + interval
```
- **Quality source:** if the user does the STT recite-check, map alignment accuracy →
  quality (0–5). If they just self-grade ("again / hard / good / easy"), map the tap.
- **Connection drill:** an extra review item type that prompts ayah N and expects the
  opening of ayah N+1 — scheduled on the same SM-2 track, keyed on the seam.
- **Catch-up / ahead:** if `due` backlog grows, cap daily reviews (configurable) and
  carry the rest; if the user races ahead, pull tomorrow's `new` forward. `HifzPlan`
  recomputes `projected_end_date` from current velocity.

### Intents touched (allow-list, §4)
Hifz mostly drives local UI, but reuses existing intents — `play_recitation` (loops
for learning), `speak` (TTS hints), `open_ayah` (jump to the ayah). The recite-check
goes through `POST /v1/stt` (transcript only) and is aligned **on-device** against the
verbatim ayah text — no model interpretation of sacred text. No new executable intents.

---

## 8. Security & Privacy (personal but still hardened)

- **No keys in the app.** All provider keys live on the gateway only.
- **Exposure:** gateway reachable only via **Cloudflare Tunnel** (no open home ports);
  CLI/SSH never exposed.
- **Auth:** single Bearer device-token; rotate-able; stored in secure storage.
- **Intent allow-list** (§4) is the hard boundary against RCE.
- **Voice privacy:** recordings transcribed then deleted by default; opt-in to keep.
- **Rate-limit & cost caps** on the gateway; cache tafsir/Q&A responses by
  `(task, ayah_ref, lang, hash(question))`.

---

## 9. Internationalization

- Quran text: Arabic, RTL, KFGQPC font.
- App UI + content: `fa` (RTL), `en` (LTR), `nl` (LTR) via Flutter `intl` / ARB files.
- Per-user language preference drives translation, tafsir, TTS voice, and Q&A
  response language. Mixed-direction layout handled per-widget.

---

## 10. Repo Layout (proposed)

```
quran_imam_shahid/
├── app/                      # Flutter app
│   ├── lib/
│   │   ├── features/         # quran_reader, tafsir, qa, recitation, progress, kids
│   │   ├── core/             # routing, theme, i18n, ai_client (talks to gateway)
│   │   └── data/             # local db (drift), repositories, models
│   └── l10n/                 # fa, en, nl ARB files
├── gateway/                  # FastAPI gateway
│   ├── ai/                   # provider.py, claude_cli.py, openai_provider.py
│   ├── routes/               # voice, ask, tafsir, tts, stt, quran, stories
│   ├── rag/                  # ingest, retrieve, embeddings
│   └── schema/               # intents.py (the allow-list), models.py
├── content/                  # ingestion scripts + source manifests (NOT raw copyrighted text)
├── REQUIREMENTS.md
└── TECHNICAL_DESIGN.md
```

---

## 11. Phase 0 → 1 Concrete Build Order

1. **Gateway skeleton:** FastAPI, `/healthz`, Bearer auth, `intents.py` allow-list,
   `AIProvider` protocol + stub `ClaudeCliProvider`.
2. **Content ingest:** load Surah/Ayah/Translation (ar + fa/en/nl) into Postgres;
   expose `GET /v1/quran/{surah}` + audio manifest.
3. **Flutter skeleton:** routing, i18n (fa/en/nl), Quran reader (Arabic + translation),
   ayah audio with sync, last-read position, local SQLite progress.
4. **Voice round-trip:** `POST /v1/voice` → Whisper → intent classify → validated
   intents → app handlers (`speak` via TTS, `open_ayah`, `play_recitation`).
5. **Cloudflare Tunnel** + token; verify the app talks to the box over HTTPS.

Then Phase 2 (tafsir + RAG Q&A), per the roadmap in REQUIREMENTS §11.

---

## 12. Still Needs Your Input

1. **Tafsir corpus licensing** — which Persian/English/Dutch tafsir editions can we
   legally digitize? (Dutch Shia tafsir is scarce — may need translation-at-ingest,
   which itself must be reviewed.)
2. **Whisper & TTS hosting** — OpenAI-hosted now, or run Whisper locally on the box to
   save cost until the full OpenAI migration?
3. **Marja'/school alignment** for tafsir selection and Q&A tone.
4. Confirm **OpenAI** (not Anthropic) is the intended long-term reasoning provider —
   if so, `OpenAiProvider` is the migration target and the prompts target OpenAI
   structured outputs.

---

*Next deliverable when you're ready: scaffold the `gateway/` skeleton (FastAPI + intent
allow-list + AIProvider stub) and the Flutter app skeleton with the Quran reader.*
