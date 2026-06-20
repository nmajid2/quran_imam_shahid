# Project Handover — Quran Imam Shahid

> **Read this first.** This file is the single entry point for a new AI/dev session to
> understand the project's purpose, what exists, what's running, and what to do next.
> Last updated: 2026-06-19.

---

## 1. What this project is

A **cross-platform (Android, iOS, Web) personal Quran companion** focused on *deep
learning*: read the Quran daily, hear correct recitation, understand each ayah through
**authentic Shia tafsir**, ask questions interactively, track reading + **memorization
(hifz)**, and a future **children's** story section.

**Owner:** Majid (single user — personal scope, not public yet).
**Languages:** Arabic (sacred text) + translations/UI/narration in **Persian (fa),
English (en), Dutch (nl)**.

### Architecture in one picture
```
Flutter app (Android/iOS/Web)  ──HTTPS+Bearer──►  Gateway (FastAPI, on Ubuntu box)
  • offline Quran + progress                        • auth, intent allow-list, caching
  • talks ONLY to the gateway                        • owns ALL secrets/API keys
                                                      • AIProvider seam: Claude CLI now,
                                                        OpenAI later (drop-in)
                                                      • OpenAI Whisper STT + TTS
                                                      • RAG-lite tafsir (→ vector later)
```
**Two hard rules** (see §8 of REQUIREMENTS): (1) the Arabic text is byte-accurate from a
verified source, never AI-generated; (2) the app never executes model-returned commands —
only a fixed **intent allow-list**.

---

## 2. Where the docs are (read in this order)

| Doc | Purpose |
|-----|---------|
| **HANDOVER.md** (this file) | Current status + how to run. Start here. |
| [REQUIREMENTS.md](REQUIREMENTS.md) | Product vision, features, personas, risks, content sources, open questions. |
| [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) | Architecture: AIProvider seam, intent schema, API contract, data models, RAG, Hifz engine. |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | **Authoritative phased plan** (Phase 0–7) with tasks + exit criteria. |

There is also persistent memory at
`~/.claude/projects/-home-zenrock-github-quran-imam-shahid/memory/` — notably
`run-app-on-android.md` (how to run on the phone + the adb-reverse gotcha).

---

## 3. Current status (what's DONE vs NOT)

### ✅ Done and verified
- **Gateway (FastAPI)** fully scaffolded and tested — **26/26 tests pass**.
  - Bearer auth, `/healthz`, CORS, config via `.env`.
  - **Intent allow-list** (`schema/intents.py`) — the security boundary.
  - **AIProvider seam** (`ai/provider.py`): `ClaudeCliProvider` (now) + `OpenAiProvider`
    (migration target, implemented). Selected by `AI_PROVIDER` env.
  - **Routes:** `/v1/quran`, `/v1/quran/{n}`, `/v1/voice`, `/v1/stt`, `/v1/tts`,
    `/v1/ask`, `/v1/tafsir`.
  - **OpenAI integration LIVE & verified**: Whisper STT + TTS round-trip works
    (`OPENAI_API_KEY` loaded from project-root `.env`).
- **Full Quran content loaded from verified Tanzil sources** — all **114 surahs / 6236
  ayat**, with fa/en/nl translations aligned. Files in
  `gateway/qis/content/quran_data/` (kept verbatim with license footers). Surah titles
  use the **original (transliterated) names**, not translated meanings.
- **Flutter app** builds and runs **in debug on the physical phone** (Samsung Galaxy
  S23 Ultra, serial `R3CW50DLQFK`). It fetches the surah list from the gateway and
  renders it (Arabic + translation + language switcher). Has a reader page + tafsir sheet.

- **Recitation audio — gateway side DONE.** Verified reciter manifest
  (`content/reciters.json`, 24 Qaris incl. Abdul Basit; **Parhizgar default**, Shia-first)
  loaded by `ReciterCatalog` (`content/reciters.py`) and served via `/v1/reciters`,
  `/v1/audio/{reciter}/{surah}/{ayah}`, `/v1/audio/{reciter}/{surah}`. Source = EveryAyah
  per-ayah MP3s (`{folder}/{SSS}{AAA}.mp3`). All folders curl-verified 200. **32/32 tests**.

- **Word lexicon (tap a word) — Mufradat DONE, embedded.** Tap any Arabic word in the
  reader → bottom sheet shows its **root** + **Mufradat** (Raghib al-Isfahani) entry,
  fully offline. Pipeline (in `tools/lexicon/`): Quranic morphology
  ([mustafa0x/quran-morphology]) → word→root map (portable `norm()`, ~74% token coverage;
  rest are rootless particles); Mufradat scraped from Shamela book 23636 (881 pages,
  segmented by `[root]` markers → 1,425 entries) → `app/assets/lexicon/lexicon.db.gz`
  (1.2 MB). App: `features/lexicon/lexicon_db.dart` (sqflite, gunzip on first run; the
  Dart `normalizeArabic` MUST stay identical to the Python `norm`), `lexicon_sheet.dart`,
  tappable words in `surah_reader_page.dart`.
  **al-Tahqiq (Mostafavi):** user will provide/license it; drops in as a 2nd `entry.book`
  ('tahqiq') keyed by the same corpus roots — add it to `lexiconBooks` and rebuild the DB.

### 🚧 Not done yet / stubs
- **Book tafsir — gateway side DONE.** 3 authentic **Persian** Shia tafsirs ingested:
  **al-Mizan** (Tabatabai), **Nemooneh** (Makarem), **Noor** (Qaraati). Source =
  [app-furqan/quran-app-data] SQLite DBs (per-ayah, Markdown), extracted at startup from
  committed `.tar.xz` (DBs git-ignored). Served via `/v1/tafsirs` + `/v1/tafsir/{id}/{s}/{a}`.
  **English/Urdu deliberately excluded** (upstream marks them AI-produced → violates hard
  rule #1). License CC BY-ND 4.0 (attribution required). See `content/tafsir_data/SOURCES.md`.
  **37/37 tests.** ⏳ Still to wire in the app (tafsir-source picker + Markdown render).
- **AI tafsir + vector RAG still placeholder** — the `POST /v1/tafsir` AI path still uses
  `content/seed/tafsir_seed.json` + exact-ayah-match `ContentStore.retrieve()`. The new
  book tafsir above could feed real RAG later.
- **Book tafsir — app side WIRED** (analyzer-clean, span-fix verified on device). The
  reader's tafsir sheet shows a **source picker** (al-Mizan / Nemooneh / Noor), renders
  Persian Markdown via `flutter_markdown_plus` (RTL), and **strips the `<span>` ayah
  anchors + ```arabic/```farsi info-strings** at render time (`_cleanMarkdown`).
  These tafsirs are **passage-based**: the gateway returns `ayah_start/ayah_end` and the
  sheet shows a banner "covers ayat X–Y together" (al-Mizan ≈10 ayat/block, Noor ≈1.6).
  **Offline = EMBEDDED IN APK** (user choice): the 3 tafsir `.tar.xz` archives are
  bundled as Flutter assets (`app/assets/tafsir/`, ~28 MB). On first use of an edition,
  `features/tafsir/tafsir_db.dart` extracts its `.db` (xz→tar in a background isolate
  via `compute`) to app docs and queries it with **sqflite** — **no gateway needed for
  tafsir**. License-clean (original DBs unmodified; CC BY-ND attribution shown). First
  open of each edition has a one-time extraction delay (al-Mizan/Noor ~40 MB, Nemooneh
  ~85 MB on device). Deps added: `sqflite`, `archive`. The old gateway-download/cache
  approach was removed from the app (gateway `/v1/tafsir*` endpoints kept but unused by app).
- **Reasoning still defaults to Claude CLI** (`AI_PROVIDER=claude_cli`); OpenAI powers
  STT/TTS only. The CLI provider falls back to a grounded summary if no CLI present.
- **UI REDESIGN DONE & verified on device.** Multi-theme system (`core/theme.dart`
  `AppPreset` + 5 presets: Sahar/Aurora/Emerald/Amber/Plum) with light/dark/auto,
  persisted (`core/theme_controller.dart`, secure storage, loaded before first frame),
  animated theme switching. Theme picker (`features/settings/theme_picker_sheet.dart`).
  **Futuristic visual language:** `widgets/app_background.dart` = animated **aurora**
  (drifting radial glows, CustomPaint in a RepaintBoundary — isolated, GPU-cheap, no blur);
  `widgets/glass.dart` = real frosted **BackdropFilter** glass used ONLY on fixed surfaces
  (app bars, player bar) — never per list item; `widgets/app_card.dart` = gradient-border
  glass card with accent glow when selected (blur-free for scroll perf). Gradient (ShaderMask)
  title, glowing number badges, glowing active controls.
  **Home = solar-system hero** (`widgets/galaxy_background.dart`): a FIXED world (a glowing
  sun with 5 planets on tilted elliptical orbits + faint orbit rings, in a parallax
  starfield) viewed by a CAMERA that the list scroll moves. Idle = camera still, only
  planets orbit (Ticker time) + stars twinkle in place (no drift); scrolling pans the camera
  through space (`_scroll` ValueNotifier from the CustomScrollView controller, cam = scroll
  ·0.32), sliding star systems in/out — systems repeat every 1.5 screens so one is always
  found as you travel. Tinted by the active preset, isolated in a RepaintBoundary (cheap
  fills, no blur). Home renders in the preset's DARK theme regardless of mode (space
  scene) with **translucent** glass cards (`AppCard(translucent: true)`). Reader uses the
  aurora background + glass ayah cards + current-ayah glow + frosted glowing player bar. Motion = `flutter_animate` run-once entrances + fade-through page
  transitions. Light-first default; **dark mode is the most futuristic.**

- **Recitation audio — app side WIRED** (analyzer-clean; not yet run on the phone).
  Bottom **PlayerBar** in the reader: play/pause, prev/next ayah, reciter picker
  (grouped Shia/Classic/Sunni, Parhizgar default), and **per-surah on-demand download**
  for offline play (streams from EveryAyah until downloaded, then plays local files).
  Per-ayah play icon + current-ayah highlight. Uses `just_audio` + `path_provider`.
  ⏳ Still to do: run/verify on device; pronunciation coaching (separate feature).
- **Hifz (memorization) tracker** — designed (TECHNICAL_DESIGN §7b, IMPLEMENTATION_PLAN
  Phase 5) but **not implemented**.
- **Children's section** — not started.
- **No real auth/DB persistence** — content store is in-memory; progress is local-only.
- **iOS / Web targets** — only `android/` platform folder was generated so far.
- **Nothing deployed** — gateway runs locally; no Cloudflare Tunnel yet.

### Phase status (per IMPLEMENTATION_PLAN)
Phase 0 ✅ · Phase 1 (core reader) ~80% ✅ · Phase 2 (voice round-trip) backend ✅, app
wiring partial · Phase 3+ (tafsir/RAG, hifz, kids, migration) ⛔ not started.

---

## 4. How to run it (verified recipe)

**Prereqs already installed on this machine:** Python 3.11, Flutter 3.44.2 at `~/flutter`,
Android SDK at `~/Android/Sdk` (platform 36), adb, Java 21. Gateway venv at
`gateway/.venv`.

```bash
# 1) Gateway (token default is dev-token-change-me; root .env holds OPENAI_API_KEY)
cd gateway && . .venv/bin/activate && \
  DEVICE_TOKEN=dev-token-change-me python -m uvicorn qis.main:app --port 8077

# 2) Forward the phone to the gateway (phone's localhost → this machine)
adb -s R3CW50DLQFK reverse tcp:8077 tcp:8077

# 3) Build + run the app in debug on the phone
cd app && ~/flutter/bin/flutter run --debug -d R3CW50DLQFK \
  --dart-define=GATEWAY_URL=http://localhost:8077 \
  --dart-define=DEVICE_TOKEN=dev-token-change-me

# Tests
cd gateway && . .venv/bin/activate && python -m pytest -q
```

**⚠️ Gotcha:** when `flutter run` exits it **removes the `adb reverse`** forward, so a
still-installed app can't reach the gateway. Re-run step 2 (and confirm with
`adb -s R3CW50DLQFK reverse --list`). Verify connectivity by watching the gateway log for
`GET /v1/quran 200` from the device.

---

## 5. Code map

```
gateway/                         FastAPI gateway (Python)
  qis/
    main.py                      app factory + lifespan (builds provider + speech engine)
    config.py                    Settings; loads root .env then gateway/.env
    auth.py                      Bearer token dependency
    schema/
      intents.py                 ★ intent allow-list (security boundary) + Citation/Lang
      models.py                  ReasonRequest/Result, Passage, request/response models
    ai/
      provider.py                AIProvider protocol + build_provider() (the seam)
      claude_cli.py              ClaudeCliProvider (now)
      openai_provider.py         OpenAiProvider (migration target; implemented)
    content/
      store.py                   ★ ContentStore — parses Tanzil files → 114 surahs
      reciters.py                ReciterCatalog — loads reciters.json, resolves audio URLs
      reciters.json              ★ verified manifest of 24 reciters (EveryAyah folders)
      tafsir.py                  TafsirStore — extracts + reads 3 Persian Shia tafsir DBs
      tafsir_data/               ★ tafsir .tar.xz archives + SOURCES.md (DBs git-ignored)
      quran_data/                ★ verified Tanzil sources (ar/fa/en/nl + metadata xml)
      seed/tafsir_seed.json      placeholder tafsir (RAG-lite)
    voice/
      speech.py                  OpenAI Whisper STT + TTS engine (None if no key)
      classify.py                transcript → navigation intent / question heuristic
    routes/                      health, quran, audio (reciters/audio), tafsir_book (tafsirs/tafsir), voice, reason (ask/tafsir)
  tests/                         26 pytest tests (conftest forces OPENAI_API_KEY="" )

app/                             Flutter app (Dart)
  lib/
    main.dart                    entry; ProviderScope; routes to SurahListPage
    core/
      config.dart                GATEWAY_URL + DEVICE_TOKEN from --dart-define
      api_client.dart            HTTP client to the gateway
      intents.dart               Dart mirror of the intent types
      providers.dart             Riverpod providers (surah list, current lang, etc.)
      theme.dart                 teal theme
    data/models/surah.dart       Surah/Ayah models
    features/
      surah_list/surah_list_page.dart   home: list of 114 surahs
      reader/surah_reader_page.dart     per-surah reader
      reader/tafsir_sheet.dart          tafsir bottom sheet
      audio/audio_controller.dart       ★ just_audio player + state/providers (single ayah + continuous surah)
      audio/download_manager.dart       per-surah offline download to app docs dir
      audio/player_bar.dart             bottom playback bar + reciter picker
  android/                       generated platform project (pkg com.imamshahid.quran_imam_shahid)
```

---

## 6. Key decisions & facts (so you don't re-litigate them)

- **Provider seam:** CLI now → **OpenAI** later (user wants full OpenAI eventually). All
  reasoning goes through `AIProvider`; swapping is an env flag, no app changes.
- **Content source = Tanzil.** Editions chosen for Shia alignment: Arabic "simple"
  script, **fa.makarem** (Makarem Shirazi), **en.qarai** (Ali Quli Qarai), **nl.siregar**.
  License: Arabic free w/ attribution; translations **non-commercial** + attribution
  (fine for personal scope; revisit if going public).
- **Surah names:** original/transliterated in all languages — do NOT translate meanings
  (explicit user preference).
- **Secrets:** `OPENAI_API_KEY` lives in the **project-root `.env`** (gitignored,
  untracked — verified). It was shared in-session, so **rotating it is recommended**.
  Device token default is `dev-token-change-me` (no DEVICE_TOKEN in `.env`).
- **Arabic script:** user downloaded "simple" (not Uthmani). Swappable later by replacing
  one file (`quran_data/ar.simple.txt`).

---

## 7. Suggested next steps (pick per IMPLEMENTATION_PLAN)

1. **Commit the work** — most of this session is uncommitted (see §9). Do this first.
2. **Wire the reader fully** to show per-ayah translations + the tafsir sheet against the
   now-complete content (Phase 1 finish).
3. **Real tafsir + RAG** (Phase 3): ingest a vetted Shia tafsir corpus, replace
   `ContentStore.retrieve()` with vector search, keep citations + "insufficient" path.
4. **Recitation audio** (Qari playback, ayah-synced) — needs an audio source (EveryAyah /
   Quran.com CDN).
5. **Hifz tracker** (Phase 5) — implement the designed SM-2 engine + UI.
6. **iOS/Web targets** (`flutter create --platforms=ios,web .`) when ready.
7. **Deploy gateway** behind a Cloudflare Tunnel (don't expose home ports).

**Open questions still blocking content depth** (REQUIREMENTS §12): canonical tafsir
source set + who reviews it; marja' alignment; tafsir licensing (esp. Dutch is scarce →
likely translate-at-ingest + review); Whisper/TTS local vs hosted; child age range.

---

## 8. Live/runtime state at handover time

- Gateway: intended to run on `127.0.0.1:8077` (restart it; it's not a daemon).
- App: installed on phone `R3CW50DLQFK` in debug; re-`adb reverse` after any flutter run.
- OpenAI: key present in root `.env`; STT/TTS verified working live.

---

## 9. Git state ⚠️

Latest commit is `5aa5e52 "initial implementation is done"`. **The Tanzil integration and
much of this session is UNCOMMITTED.** `git status` shows modified `store.py` /
`test_quran.py`, deleted placeholder seed JSON, and untracked `app/android/`, `.gitignore`,
`gateway/qis/content/quran_data/`, root `quran-simple.txt`. Recommend committing on a
branch before further work. The root `.env` is correctly gitignored — keep it that way.
