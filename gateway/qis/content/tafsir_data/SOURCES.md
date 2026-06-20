# Shia Tafsir Data — Sources, Licensing & Provenance

These are **verified Shia tafsir** databases, used to power per-ayah commentary in the app.

## Source
Downloaded from **[app-furqan/quran-app-data](https://github.com/app-furqan/quran-app-data)**
(the data repository for the *Quran — Furqan* app by Furqan Apps).

The archives are kept **verbatim** (unmodified `.tar.xz`) to respect the license (see below).
Each contains a single SQLite `.db` with the schema:

- `ayah_mapping(id, surah_number, ayah_number, content_id)` — all 6236 ayat → a content block
- `content(content_id, content[, content_en, content_ur | content_fa, content_en, content_ur])`
  — passage-level commentary in Markdown (one block can map to many ayat)
- `muqadimah(...)` — the author's introduction

The extracted `.db` files are git-ignored (`*.db`); the gateway extracts them from these
archives at startup.

## Editions ingested (Persian only — authentic, human-authored)

| File | Tafsir | Author | Persian column |
|------|--------|--------|----------------|
| `tafsir_almizan_fa.db.tar.xz` | **al-Mizan** (الميزان) | Allamah Muhammad Husayn Tabatabai | `content.content` |
| `tafsir-noor.tar.xz` | **Noor** (نور) | Mohsen Qaraati | `content.content_fa` |
| `tafsir_nemouneh_fa_en_ur.tar.xz` | **Nemooneh** (نمونه) | Naser Makarem Shirazi *(pairs with the app's fa.makarem translation)* | `content.content` |

## ⚠️ Authenticity note (project hard rule #1: content must be authentic, never AI-generated)
The Persian editions above are **original/established human works** and are safe to use.

The **English and Urdu** columns/editions in this repository are marked by the upstream
README as **"produced using AI"** — they are therefore **NOT used**. The archives still
contain those columns (we keep the files unmodified for licensing), but the gateway reads
**only the Persian** content. For an English tafsir later, source the **human** al-Mizan
translation (Saeed Akhtar Rizvi / Tawheed Institute) from al-islam.org / almizan.org /
Internet Archive — do not use the AI English here.

Dutch (nl): no Shia tafsir exists upstream → translate-at-ingest + review later.

## License
Upstream is **CC BY-ND 4.0** (Attribution — NoDerivatives), © 2025 Furqan Apps.
- ✅ We may redistribute the data (even commercially) **with attribution to Furqan Apps**.
- ⚠️ **NoDerivatives**: the content must be displayed **unmodified**. Do not redistribute a
  transformed/repackaged version of the text. (Querying & displaying it as-is is fine.)
- Attribution to show in-app: *"Tafsir data © Furqan Apps (furqan.app), CC BY-ND 4.0."*

Revisit licensing before any public release (consistent with REQUIREMENTS §12 open questions).
