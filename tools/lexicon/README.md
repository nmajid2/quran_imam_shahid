# Lexicon pipeline (tap-a-word → root → dictionary entry)

How the word-lexicon feature's data is built, and **how to add al-Tahqiq** when a
clean source is available.

## What ships in the app
`app/assets/lexicon/lexicon.db.gz` — a SQLite DB (gzipped), inflated on first run and
read via sqflite (`app/lib/features/lexicon/lexicon_db.dart`). Two tables:

- `word_root(form TEXT PRIMARY KEY, root TEXT)` — normalized Quran word → Arabic root.
  `form` is produced by the **portable `norm()`** which MUST stay identical to Dart's
  `normalizeArabic()` in `lexicon_db.dart`.
- `entry(book TEXT, root TEXT, content TEXT, PRIMARY KEY(book,root))` — a dictionary
  entry, keyed by **corpus root**. Currently only `book='mufradat'`.

At tap time: word → `norm` → `word_root` → root → `entry` rows for that root.

## Build scripts (run from this dir, needs `m.txt` = quran-morphology.txt)
1. `scrape_mufradat.py` — scrapes Shamela book 23636 → `mufradat_raw.txt`.
2. `build_wordroot.py` — morphology + Tanzil → `word_root.json` (+ coverage report).
3. `build_lexicon.py` — segments Mufradat by `[root]` markers, matches roots to the
   corpus, writes `lexicon.db`. Then: `gzip -9 lexicon.db` → copy to the app asset.

## ➕ Adding al-Tahqiq (or any second dictionary)
The system is ready — al-Tahqiq just needs to become `book='tahqiq'` rows keyed by the
same corpus roots. **Provide the text in any ONE of these formats** (cleanest first):

1. **Best — root-keyed JSON**: `{ "<arabic root>": "<entry text>", ... }`
   e.g. `{ "كتب": "التحقيق: الأصل الواحد ...", "علم": "..." }`
2. **TSV/CSV**: one row per entry, `root <TAB> entry text`.
3. **Plain text** where each entry starts with a clear root header (tell me the marker,
   e.g. a line that is just the root, or `### كتب`), and I'll segment it.

Roots don't need to match the corpus exactly — the importer canonicalizes weak/hollow/
hamza/geminate forms and maps them to corpus roots automatically (same logic that gave
Mufradat ~86% root coverage).

Then run:
```
python3 add_book.py tahqiq "al-Tahqiq" "التحقيق" "Hasan Mostafavi" <your-file>
```
which folds the entries into `lexicon.db.gz`. Finally uncomment the `'tahqiq'`
`LexiconBook(...)` line in `lexicon_db.dart` and rebuild the app. The tap sheet then
shows **both** Mufradat and al-Tahqiq automatically.

> ⚠️ al-Tahqiq is **copyrighted** (Mostafavi, d. 2005). Use a properly licensed copy;
> revisit before any public release.
