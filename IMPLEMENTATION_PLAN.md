# Quran Imam Shahid — Implementation Plan

> Concrete, phased build plan. Companion to [REQUIREMENTS.md](REQUIREMENTS.md) and
> [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md). Each phase lists **tasks**,
> **deliverable**, and an **exit criterion** (how you know it's done).

**Status:** Draft v0.1 · **Owner:** Majid · **Last updated:** 2026-06-18

### How to read this
- Phases are sequential but the **app** and **gateway** tracks within a phase can be
  built in parallel.
- "Personal, single-user" scope assumed → no multi-tenant/app-store work.
- Provider is `claude_cli` now; `openai` is a drop-in later (see Phase 7).

---

## Phase 0 — Foundations & Decisions  *(unblock everything)*

**Tasks**
- [ ] Confirm open questions: tafsir corpus + **licensing**, Whisper/TTS hosting
      (OpenAI vs local), marja'/school alignment, OpenAI as long-term provider.
- [ ] Lock the **Quran text source** (Tanzil Uthmani) + checksum process.
- [ ] Lock translation sources for **ar / fa / en / nl** (+ licenses).
- [ ] Provision the Ubuntu box: gateway runtime, Postgres, **Cloudflare Tunnel**.
- [ ] Create repo structure per [TECHNICAL_DESIGN.md §10](TECHNICAL_DESIGN.md).
- [ ] Mint the single **device token**; decide secret storage on the box.

**Deliverable:** decisions doc filled in; empty-but-wired repo + reachable box.
**Exit criterion:** `GET /healthz` returns ok over the Cloudflare Tunnel with auth.

---

## Phase 1 — Core Reader (MVP)  *(the thing you use daily)*

**Gateway**
- [ ] FastAPI skeleton: Bearer auth, rate-limit, error envelope.
- [ ] `intents.py` allow-list + Pydantic validation (the security boundary).
- [ ] `AIProvider` protocol + stub `ClaudeCliProvider`.
- [ ] Content ingest: Surah/Ayah/Translation (ar + fa/en/nl) into Postgres.
- [ ] `GET /v1/quran/{surah}`, `GET /v1/audio/manifest`.

**App (Flutter)**
- [ ] Project skeleton: routing, theme, **i18n (fa/en/nl)**, RTL handling.
- [ ] `ai_client` that talks only to the gateway.
- [ ] Local DB (Drift/SQLite) seeded with Quran text for **offline**.
- [ ] Quran reader: surah list, ayah view, Arabic (KFGQPC) + selectable translation.
- [ ] Ayah audio playback with **ayah-synced highlight**; last-read position.
- [ ] Bookmarks + basic `ReadingProgress` (read/listened).

**Deliverable:** installable app that reads the Quran offline with audio + translation.
**Exit criterion:** open app offline → read & hear any ayah; reopen → resumes position.

---

## Phase 2 — Voice Round-Trip  *(your original MVP flow, done safely)*

**Tasks**
- [ ] `POST /v1/stt` (Whisper) and `POST /v1/tts` (fa/en/nl).
- [ ] `POST /v1/voice`: STT → intent classification → **validated intents** out.
- [ ] App: record (Opus), call `/v1/voice`, execute intents via **typed handlers**
      (`speak`→TTS, `open_ayah`, `play_recitation`). No command execution.
- [ ] Voice-privacy: delete recordings after transcription by default.

**Deliverable:** speak to the app → it navigates / answers / speaks back.
**Exit criterion:** a spoken "open ayat al-kursi" opens 2:255; an unknown/invalid
intent is dropped and logged, never executed.

---

## Phase 3 — Tafsir & Interactive Q&A  *(the differentiator)*

**Tasks**
- [ ] Ingest **vetted Shia tafsir corpus**; chunk + store with source metadata.
- [ ] Build the **RAG index** (pgvector, multilingual embeddings ar/fa/en/nl).
- [ ] `POST /v1/tafsir` (per-ayah, cited) and `POST /v1/ask` (RAG Q&A, cited).
- [ ] Guardrails: answer only from retrieved passages; `confidence:insufficient`
      path; **no fatwas** → redirect to scholar.
- [ ] App: per-ayah tafsir panel with **visible citations**; Q&A chat with session
      memory; save Q&A to notes; highlights/notes per ayah.

**Deliverable:** tap any ayah → cited Shia tafsir; ask questions and get grounded,
sourced answers.
**Exit criterion:** every answer shows sources; an out-of-corpus question returns
"insufficient basis" instead of guessing.

---

## Phase 4 — Habit, Progress & Recitation Coaching

**Tasks**
- [ ] Streaks, daily goal, reminders/notifications (FCM/APNs).
- [ ] Stats: % read, juz' completion, time spent; **Khatm planner**.
- [ ] Recitation coaching: record ayah → STT **alignment** vs verbatim text →
      highlight mismatches + tajweed issues → `RecitationScore`.

**Deliverable:** daily-habit loop + pronunciation feedback.
**Exit criterion:** miss a day → streak resets; recite an ayah → per-word accuracy shown.

---

## Phase 5 — Hifz: Memorization Tracker  *(ayah-by-ayah, daily)*

Implements [REQUIREMENTS §4.6](REQUIREMENTS.md) + [TECHNICAL_DESIGN §7b](TECHNICAL_DESIGN.md).
All local/offline; reuses Phase 2 STT for the recite-check.

**Tasks**
- [ ] Data models: `HifzPlan`, `AyahMemo`, `HifzSession`, `HifzStreak`.
- [ ] **Plan setup**: scope (quran/juz/surah/range) + `daily_new_target` → schedule
      + projected end date.
- [ ] Per-ayah **state machine** `new→learning→memorized→reviewing→mastered`.
- [ ] **SM-2 spaced-repetition** scheduler; daily session = *new ayat + due reviews*.
- [ ] Memorization UI: audio loop, progressive word-hide, first-letter hints,
      blank-out drills, recite-from-memory → STT → highlight misses.
- [ ] **Connection drills** (ayah N → start of N+1).
- [ ] Quality input: from recite accuracy **or** manual self-grade (again/hard/good/easy).
- [ ] **Forgiveness**: repeated lapses auto-demote ayah to `learning`.
- [ ] Separate **hifz streak/goal**; home shows "N new + M reviews due".
- [ ] Stats: ayat memorized, % of target, retention trend, weakest ayat, heat-map.

**Deliverable:** a working daily memorization loop that schedules new ayat and reviews.
**Exit criterion:** set "3 ayat/day" → each day shows the right new portion + due
reviews; passing reviews lengthens intervals, failing ones shorten/demote them; all
works **offline**.

---

## Phase 6 — Children's Section

**Tasks**
- [ ] Parent-gated mode + simplified UI + screen-time limits + parent dashboard.
- [ ] **Pre-generated, human-reviewed** stories (fa/en/nl) with illustrations/
      short animations; **aniconism rules** enforced in art + review checklist.
- [ ] Story catalog API (`GET /v1/stories`), narration audio, offline story packs.
- [ ] Simple comprehension quizzes + reward stickers.

**Deliverable:** safe, reviewed kids' story library with narration + pictures.
**Exit criterion:** a child can pick a reviewed story offline; no story depicts
Prophets/Imams/Allah; parent controls screen time.

---

## Phase 7 — Provider Migration & Scale (CLI → OpenAI)

**Tasks**
- [ ] Implement `OpenAiProvider` (structured outputs/function calling) behind the
      same `AIProvider` interface — **no app changes**.
- [ ] Flip `AI_PROVIDER=openai`; run A/B parity checks vs `claude_cli`.
- [ ] Move Whisper/TTS fully to OpenAI if previously local.
- [ ] Cost controls: response caching, pre-compute popular tafsir, model tiering.
- [ ] Accessibility pass; more languages/Qaris/tafasir; performance tuning.

**Deliverable:** fully OpenAI-backed reasoning with the personal box as gateway only.
**Exit criterion:** toggling provider changes nothing user-visible except (ideally)
cost/latency; cache hit-rate measurably reduces API spend.

---

## Cross-Phase / Always-On

- [ ] **Sacred-text integrity**: checksum Arabic ayah text; never LLM-generated.
- [ ] **Scholarly review loop** before any tafsir/Q&A/kids content ships.
- [ ] Backups/export of personal notes, progress, and hifz data.
- [ ] Privacy: keys only on gateway; voice deleted after transcribe; opt-in analytics.

---

## Milestone Summary

| Phase | Theme | You can… |
|-------|-------|----------|
| 0 | Foundations | reach the box securely |
| 1 | Core reader (MVP) | read + hear Quran offline |
| 2 | Voice round-trip | talk to the app safely |
| 3 | Tafsir & Q&A | learn cited Shia meaning |
| 4 | Habit & recitation | build daily streak + fix pronunciation |
| 5 | **Hifz tracker** | **memorize ayah-by-ayah daily with reviews** |
| 6 | Children | give kids safe narrated stories |
| 7 | OpenAI migration | swap backend, control cost |

*Suggested order if you want value fastest: 0 → 1 → 3 → 5, then 2, 4, 6, 7.*
