# Quran Imam Shahid — Product Requirements & Architecture

> A cross-platform (Android, iOS, Web) personal Quran companion focused on **deep
> learning**: correct recitation, authentic Shia tafsir, interactive Q&A, progress
> tracking, and an AI-narrated children's section.

**Status:** Draft v0.1 · **Owner:** Majid · **Last updated:** 2026-06-18

---

## 1. Vision & Guiding Principles

The app should help a person of any age **read the Quran daily, hear correct
pronunciation, and genuinely understand each ayah** through authentic Shia
references — not just translate words, but teach meaning, context, and reflection.

Guiding principles:

1. **Authenticity over fluency.** For religious content, a confident-but-wrong
   answer is worse than "I'm not sure." Every tafsir/answer must be traceable to a
   named, verified source.
2. **Respect the text.** The Arabic Quran text is sacred and must be byte-accurate,
   never AI-generated, never paraphrased.
3. **Calm, distraction-free, ad-free.** This is a spiritual tool, not a content feed.
4. **Works offline.** Core reading + audio must function with no connection.
5. **Privacy-first.** Voice recordings and personal progress are private by default.
6. **Age-appropriate.** Adult depth and child-safe simplicity are different modes.

---

## 2. Restating Your Goals (as I understood them)

| # | Your goal | Notes / clarifications |
|---|-----------|------------------------|
| 1 | Cross-platform: Android, iOS, Web | One codebase recommended (Flutter). |
| 2 | Personal app; connect to **your Claude CLI** on your machine + use **OpenAI API** for speech↔text | "video to text" → I read this as **voice/speech-to-text**. Confirm. |
| 3 | Daily reading, correct pronunciation, **Shia tafsir** & deep meaning per ayah | Core differentiator. Needs vetted Shia sources. |
| 4 | Interactive Q&A about meaning of any part | RAG over tafsir corpus, not free-form LLM. |
| 5 | Track how much Quran has been read | Per-ayah progress, streaks, stats. |
| 6 | Children's section: narrated Quran stories, AI images + short animations | Separate, heavily-guarded content pipeline. |
| 7 | MVP flow: app records audio → sends to Claude CLI on Ubuntu box over internet → CLI runs request → returns result → app runs TTS or **executes a command embedded in the response** | ⚠️ Security & reliability concerns — see §5 and §9. |

---

## 3. Personas

- **The Daily Reader (adult).** Wants a daily portion, correct recitation, and a
  short tafsir reflection. Cares about streaks and not losing their place.
- **The Learner / Student.** Wants deep tafsir, cross-references, Q&A, and the
  ability to compare translations and commentaries.
- **The Parent.** Sets up the child profile, picks stories, reviews what the child
  sees, controls screen time.
- **The Child (4–10).** Listens to stories, sees gentle illustrations, taps to hear
  short ayat, earns friendly rewards.
- **The Reverter / Non-Arabic speaker.** Needs transliteration, word-by-word
  meaning, and patient pronunciation coaching.

---

## 4. Feature Requirements

### 4.1 Quran Reading (core)
- Full Uthmani Arabic text (KFGQPC / Tanzil verified source).
- Surah list, juz'/para navigation, page (mushaf) view and verse-list view.
- Multiple translations (Persian, English, …) selectable and stackable.
- Word-by-word translation + transliteration toggle.
- **Tajweed color-coding** of the Arabic text.
- Bookmarks, last-read position, notes/highlights per ayah.
- Adjustable Arabic font size, line spacing, themes (light/dark/sepia, night mode).
- Search (Arabic + translation), jump to surah:ayah.

### 4.2 Recitation & Pronunciation
- Verified audio recitations from multiple Qaris, ayah-synced highlighting.
- Per-ayah, per-word, and range repeat (memorization "loop" mode) with
  configurable repeat count and speed.
- **Pronunciation coaching:** user records reciting an ayah → speech-to-text +
  alignment → highlights mismatched words and tajweed issues, gives feedback.
- Text-to-speech for translations/tafsir in multiple languages.

### 4.3 Tafsir & Deep Meaning (Shia references)
- Per-ayah tafsir drawn from a **curated, named corpus** (see §6).
- Show source attribution on every passage (book, author, volume/section).
- Asbab al-nuzul (occasions of revelation) where available.
- Cross-references (related ayat, themes, hadith from Shia collections).
- Thematic study paths (e.g. Tawhid, Imamate, Akhlaq, stories of prophets).

### 4.4 Interactive Q&A
- Ask in natural language about an ayah, word, theme, or ruling.
- **Retrieval-Augmented Generation (RAG):** answers grounded in the tafsir corpus;
  every answer cites sources and can say "not enough basis to answer."
- Scope guardrails: deflect fiqh/legal rulings to "consult a qualified marja'/scholar"
  rather than issuing fatwas.
- Conversation memory within a study session; save Q&A to notes.

### 4.5 Progress Tracking & Habit
- Per-ayah read/listened/memorized state.
- Daily streak, daily goal (ayat/pages/time), reminders/notifications.
- Stats: % of Quran read, juz' completion, time spent, recitation accuracy trend.
- Khatm (completion) planner: finish the Quran in N days, daily portion scheduling.
- Optional gentle gamification (badges, milestones) — never gimmicky.

### 4.6 Hifz — Memorization Tracker (ayah-by-ayah, daily)
A dedicated mode for memorizing the Quran, distinct from reading progress. The
mental model: **you commit to a small daily portion (e.g. N ayat/day), memorize
ayah by ayah, and the app drives daily learning + spaced review so memorized ayat
actually stick.**

- **Hifz plan:** pick a scope (whole Quran, a juz', a surah, a custom range) and a
  daily pace (e.g. 3 ayat/day). App computes the schedule and projected finish date,
  and adapts if you fall behind or get ahead.
- **Per-ayah memorization state machine:** each ayah moves through
  `new → learning → memorized → reviewing → mastered`. State is tracked **per ayah**,
  not per page.
- **Daily session** has two parts:
  1. **New ayat** — today's portion to memorize (with audio loop, hide/reveal,
     word-by-word peek, and a self-recite check via STT alignment).
  2. **Due reviews** — previously-memorized ayat scheduled for retention review by a
     **spaced-repetition** algorithm (SM-2 / Leitner style). Getting one right pushes
     its next review further out; struggling pulls it back in.
- **Memorization aids:** progressive word-hiding, first-letter hints, blank-out drills,
  "recite from memory → STT checks against the real ayah → highlights misses," and
  configurable per-ayah/per-range repeat with adjustable speed.
- **Connection memorization:** drill the seam between consecutive ayat (the most
  common forgetting point) — prompt with ayah N, expect the start of ayah N+1.
- **Daily hifz streak & goal** separate from the reading streak; "today: 3 new + 12
  reviews due" surfaced on the home screen with a reminder notification.
- **Stats:** ayat memorized, % of target memorized, retention/accuracy trend over
  time, weakest ayat (most-failed), juz'/surah memorization heat-map.
- **Forgiveness & re-learning:** ayat that fail review repeatedly drop back to
  `learning` automatically so you re-strengthen them instead of silently losing them.
- Works **offline**; syncs when reconnected. Optional: tie review difficulty to the
  recitation-accuracy score from §4.2.

### 4.7 Children's Section
- Separate, parent-gated mode with simplified UI.
- AI-narrated Quran/prophet stories in pleasant, age-appropriate language.
- AI-generated illustrations + short animations per story.
- **Content must be pre-generated and human-reviewed**, not live-generated for kids.
- Aniconism-aware art guidelines (see §8): no depiction of the Prophets, Imams,
  or Allah; symbolic/landscape/scene-based illustration only.
- Short, tappable ayat with audio; simple comprehension prompts; reward stickers.
- Screen-time limits and a parent dashboard.

### 4.8 Cross-cutting
- Accounts & sync (your data across phone/tablet/web).
- Full localization (UI in Persian/English/Arabic at minimum; RTL support).
- Offline-first with sync-on-reconnect.
- Accessibility: large text, screen-reader labels, high contrast, dyslexia-friendly font.

---

## 5. The MVP Flow — Analysis & Recommendation

Your proposed MVP: **app → audio → Claude CLI on your Ubuntu box → CLI runs request →
response → app runs TTS or executes an embedded command.**

This is a clever way to bootstrap using tools you already have, and it's fine for a
**personal prototype**. Two things need attention:

### 5.1 ⚠️ "Execute the command embedded in the response"
Having the app blindly run commands returned by the model is a **remote-code-execution
risk** and is fragile. Instead:

- Define a **fixed action schema** (an allow-list of intents the app understands), e.g.
  ```json
  { "action": "speak", "lang": "fa", "text": "..." }
  { "action": "open_ayah", "surah": 2, "ayah": 255 }
  { "action": "play_recitation", "surah": 36, "from": 1, "to": 5 }
  { "action": "answer", "text": "...", "sources": [ ... ] }
  ```
- The model returns **structured intents**, never shell/arbitrary commands. The app
  maps each intent to a safe, pre-built handler. No `eval`, no shell execution.

### 5.2 ⚠️ Personal machine as backend
A laptop/desktop running the CLI behind your home internet is a single point of
failure (offline when machine sleeps, dynamic IP, no TLS, no auth). For a personal
MVP it's acceptable, but harden it:

- Put a thin **HTTP API gateway** in front of the CLI (don't expose the CLI/SSH to
  the internet). Add an auth token, HTTPS (Caddy/Cloudflare Tunnel), and rate limits.
- Treat it as a **swappable backend**: the app talks to an abstract "AI backend"
  interface so you can later move from "Claude CLI on my box" → "hosted Claude API /
  Agent SDK" without touching the app.

### 5.3 Recommended MVP architecture (still personal, much safer)
```
Flutter app  ──HTTPS+token──►  Gateway (FastAPI/Node) on Ubuntu box
   │                               │
   │                               ├─► Claude (CLI or Anthropic API) — reasoning/tafsir/Q&A
   │                               ├─► OpenAI Whisper — speech → text
   │                               └─► OpenAI / ElevenLabs TTS — text → speech
   │
   └─ local cache: Quran text, audio, offline tafsir
```
The gateway owns secrets (API keys never ship in the app), enforces the action
schema, and is the only thing exposed — via a Cloudflare Tunnel so you don't open
home-network ports.

---

## 6. Content Sources (the heart of the app)

### 6.1 Quran text & audio (use verified, licensed sources — never AI-generate)
- **Arabic text:** Tanzil.net (Uthmani), KFGQPC HAFS font/data.
- **Translations:** Tanzil / Quran.com API (check per-translation licenses).
- **Audio recitations:** EveryAyah, Quran.com audio CDN (ayah-segmented).
- **Word-by-word & morphology:** Quranic Arabic Corpus (corpus.quran.com).

### 6.2 Shia tafsir & references (to be confirmed/licensed)
Candidate primary sources (verify licensing & get digitized, attributed text):
- **Tafsir al-Mizan** — Allamah Sayyid Muhammad Husayn Tabataba'i.
- **Tafsir Nemooneh** — Ayatollah Makarim Shirazi (and team).
- **Majma' al-Bayan** — Shaykh al-Tabarsi.
- **Tafsir al-Qummi**, **Tafsir al-Ayyashi**, **Tafsir al-Safi** (al-Fayd al-Kashani).
- **Nur al-Thaqalayn** (al-Huwayzi).
- Hadith context: **al-Kafi**, **Bihar al-Anwar**, **Nahj al-Balagha** (for reflections).

> **Action item:** You must decide the canonical source set and confirm copyright /
> usage rights for each. Some are public-domain Arabic; modern Persian/English
> translations and Nemooneh are likely copyrighted — get permission or use
> openly-licensed editions.

### 6.3 Why a curated corpus + RAG (not raw LLM answers)
The LLM should **retrieve and explain from these texts**, with citations — not
generate doctrine from its training data. This is the single most important design
decision for trustworthiness. Build a vector index over the vetted corpus; the model
answers only from retrieved passages and cites them.

---

## 7. Recommended Technical Stack

| Layer | Recommendation | Why |
|-------|----------------|-----|
| App framework | **Flutter** (Dart) | True single codebase for Android, iOS, **and** Web; great RTL/Arabic text rendering. |
| Local storage | SQLite (Drift) / Isar; flutter_secure_storage for tokens | Offline-first Quran + progress. |
| State mgmt | Riverpod or Bloc | Testable, scalable. |
| Backend gateway | FastAPI (Python) or Node (NestJS) | Owns API keys, action schema, RAG orchestration. |
| AI reasoning | Anthropic Claude (API or your CLI via gateway) + **Agent SDK** | Tafsir explanation, Q&A. |
| Speech-to-text | OpenAI **Whisper** | Recitation capture & pronunciation alignment. |
| Text-to-speech | OpenAI TTS / **ElevenLabs** (multilingual) | Natural narration in several languages. |
| Children's images | Image-gen model (DALL·E / SDXL) — **pre-generated + reviewed** | Safety & cost control. |
| RAG / search | pgvector or a managed vector DB | Grounded tafsir retrieval. |
| Auth & sync | Supabase / Firebase (Auth + sync DB) | Fast to ship; cross-device. |
| Notifications | FCM / APNs | Daily reminders, streaks. |

> Alternative if you want web-first speed: React + React Native (Expo). Flutter is
> still my top pick for Arabic/RTL fidelity and one codebase across all three targets.

---

## 8. Religious Accuracy, Safety & Sensitivity (must-haves)

These are not optional for a Quran app:

1. **Sacred text integrity.** Arabic ayah text is loaded from a verified source and
   never produced or altered by an LLM. Add a checksum/verification step.
2. **No fabricated tafsir or hadith.** All interpretive content is retrieved from the
   vetted corpus with visible citations; the AI must be able to say "I don't have a
   basis for that."
3. **No fatwas.** Legal/fiqh questions are deflected to qualified scholars/maraji'.
   Show a standing disclaimer that the app is educational, not a religious authority.
4. **Aniconism in children's art.** Do **not** depict Allah, Prophets, or the Imams.
   Use symbolic, environmental, and scene-based illustration. Bake this into the
   image-generation prompts and the human review checklist.
5. **Scholarly review loop.** Have a knowledgeable reviewer sign off on the tafsir
   corpus, the Q&A guardrails, and all children's content before release.
6. **Handle of the Mushaf with respect** (UI conventions, no ads over ayat, etc.).
7. **Source transparency.** Every answer/story links to its origin; users can audit.

---

## 9. Additional Things to Add (my recommendations beyond your list)

**Learning depth**
- Word-by-word morphology & root explorer (see every place a root appears).
- Tajweed lessons + live tajweed feedback during recitation.
- Memorization (hifz) mode: progressive hide, spaced repetition, self-test.
- Thematic/"journey" study paths and a Quranic dictionary.
- Reflection journal (tadabbur): prompt the user to write a takeaway per session.

**Engagement & habit**
- "Verse of the day" + daily reflection notification.
- Khatm planner and Ramadan mode (juz'-a-day schedule).
- Streaks, gentle milestones, shareable progress (privacy-respecting).

**Personalization & assist**
- AI study buddy that adapts depth to age/level.
- Multi-language everything (Persian/English/Arabic + more), full RTL.
- Audio-first / eyes-free mode for commuting or visually-impaired users.

**Children**
- Story library with reading-level tiers (4–6, 7–10).
- Interactive quizzes ("what did Prophet Yunus learn?"), reward stickers, parent
  dashboard, screen-time limits, offline downloaded story packs.

**Platform & ops**
- Offline packs (download surah audio + tafsir for travel).
- Cost controls: cache AI responses, pre-compute popular tafsir, rate-limit.
- Analytics that are privacy-preserving (local-first, opt-in).
- Backup/export of personal notes & progress.

**Trust & privacy**
- On-device processing where possible; voice recordings deleted after transcription
  unless the user opts to keep them.
- Clear data policy; no third-party ad tracking, ever.

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| AI hallucinates tafsir/hadith | High (doctrinal harm, loss of trust) | RAG over vetted corpus + citations + "I don't know"; scholarly review. |
| Executing embedded commands from model | High (RCE/security) | Fixed action allow-list, structured intents, no eval/shell. |
| Personal box as backend goes offline | Medium | Cloudflare Tunnel + plan migration to hosted API; cache aggressively. |
| API key leakage in client | High | Keys only on gateway, never in the app. |
| Copyright on translations/tafsir | Medium/Legal | Confirm licenses; prefer public-domain / permissioned editions. |
| Inappropriate or doctrinally-wrong kids content | High | Pre-generate + human review; aniconism rules; no live generation for kids. |
| Voice privacy concerns | Medium | Delete-after-transcribe default; on-device where possible; clear policy. |
| AI cost blowup | Medium | Caching, pre-computation, rate limits, model tiering (cheap model for simple asks). |

---

## 11. Roadmap (phased)

> **Single source of truth:** the detailed, authoritative phase plan — with per-phase
> tasks, deliverables, and exit criteria — lives in
> [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md). The table below is just the summary;
> when they disagree, the implementation plan wins.

| Phase | Theme | Outcome |
|-------|-------|---------|
| 0 | Foundations & decisions | Secure, reachable gateway on the Ubuntu box. |
| 1 | Core reader (MVP) | Read + hear Quran offline (Arabic + fa/en/nl translation). |
| 2 | Voice round-trip | Talk to the app safely via validated intents. |
| 3 | Tafsir & Q&A | Cited Shia tafsir + grounded RAG answers. |
| 4 | Habit & recitation | Streaks, khatm planner, pronunciation feedback. |
| 5 | **Hifz tracker** | **Memorize ayah-by-ayah daily with spaced reviews.** |
| 6 | Children's section | Safe, reviewed narrated stories with pictures. |
| 7 | OpenAI migration & scale | Swap CLI→OpenAI behind the same interface; cost control. |

*Suggested value-first order: 0 → 1 → 3 → 5, then 2, 4, 6, 7.*

---

## 12. Open Questions

### Resolved (2026-06-18)
- ✅ **Languages:** Persian (fa) + English (en) + **Dutch (nl)** for UI/translation/
  tafsir/narration; Arabic for the Quran text itself.
- ✅ **Scope:** Personal, single-user (lighter auth, no app-store/licensing pressure).
- ✅ **AI backend:** Claude CLI on the Ubuntu box behind a gateway **now**, migrating
  **fully to OpenAI** later (provider-agnostic interface — see TECHNICAL_DESIGN §3).
- ✅ **"Video to text"** read as **speech/recitation → text** (Whisper).

### Still open
1. **Canonical Shia source set** for tafsir/Q&A, and who reviews/approves it?
2. **Marja' / school preference** to align tafsir selection and tone?
3. **Tafsir licensing** — which fa/en/**nl** editions can we legally digitize?
   (Dutch Shia tafsir is scarce → likely translate-at-ingest + human review.)
4. **Whisper & TTS hosting** — OpenAI-hosted now, or run locally on the box until the
   full OpenAI migration?
5. **Target child age range** and how strict the parental controls must be?
6. **Budget posture** for AI/API usage (affects caching/model-tiering strategy).

---

*This document is a living spec. Once §12 is answered, I can turn Phase 0–1 into a
concrete technical design (data models, gateway API contract, action schema, and a
Flutter project skeleton).*
