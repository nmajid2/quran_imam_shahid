"""In-memory content store.

Loads the full Quran (all 114 surahs) from verified Tanzil source files at startup:

  qis/content/quran_data/
    ar.simple.txt     Arabic text (Tanzil "simple" script)   — the sacred text
    fa.makarem.txt    Persian — Naser Makarem Shirazi (Shia)
    en.qarai.txt      English — Ali Quli Qarai (Shia)
    nl.siregar.txt    Dutch   — Sofjan S. Siregar
    quran-data.xml    Surah metadata (names, ayah counts, Meccan/Medinan)

The translation text files are `surah|ayah|text` per line (Tanzil "txt-2" format) with a
trailing license/comment block (`#` lines), kept verbatim so the text stays byte-accurate
from its verified source. The Arabic text is NEVER generated — only parsed from this file.

This is the stand-in for the eventual Postgres-backed store; routes depend only on this
interface, so the backend can be swapped without touching them.

Tafsir lookup remains a deliberately simple "RAG-lite" (exact ayah match over a small
seed) until real vector retrieval lands (TECHNICAL_DESIGN §7).
"""

from __future__ import annotations

import json
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from qis.schema.intents import Citation, Lang
from qis.schema.models import Passage

CONTENT_DIR = Path(__file__).parent
QURAN_DIR = CONTENT_DIR / "quran_data"
SEED_DIR = CONTENT_DIR / "seed"  # tafsir seed only

# Translation files keyed by app language code.
TRANSLATION_FILES: dict[str, str] = {
    "fa": "fa.makarem.txt",
    "en": "en.qarai.txt",
    "nl": "nl.siregar.txt",
}
ARABIC_FILE = "ar.simple.txt"
METADATA_FILE = "quran-data.xml"

_REVELATION = {"Meccan": "makkah", "Medinan": "madinah"}


@dataclass(frozen=True)
class Ayah:
    surah: int
    ayah: int
    text_ar: str
    translations: dict[str, str]


@dataclass(frozen=True)
class Surah:
    number: int
    name_ar: str
    name_translit: str
    names: dict[str, str]
    revelation_place: str
    ayat: list[Ayah]


def _parse_tanzil_text(path: Path) -> dict[tuple[int, int], str]:
    """Parse a Tanzil `surah|ayah|text` file, ignoring `#` comments and blank lines."""
    out: dict[tuple[int, int], str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) != 3:
            continue
        s, a, text = parts
        out[(int(s), int(a))] = text
    return out


@dataclass(frozen=True)
class _SurahMeta:
    number: int
    ayas: int
    name_ar: str
    tname: str
    revelation_place: str


def _parse_metadata(path: Path) -> list[_SurahMeta]:
    root = ET.fromstring(path.read_text(encoding="utf-8"))
    metas: list[_SurahMeta] = []
    for sura in root.iter("sura"):
        metas.append(
            _SurahMeta(
                number=int(sura.attrib["index"]),
                ayas=int(sura.attrib["ayas"]),
                name_ar=sura.attrib["name"],
                tname=sura.attrib["tname"],
                revelation_place=_REVELATION.get(sura.attrib.get("type", ""), ""),
            )
        )
    return sorted(metas, key=lambda m: m.number)


class ContentStore:
    def __init__(self) -> None:
        self._surahs: dict[int, Surah] = {}
        self._tafsir: list[dict] = []

    def load(self, quran_dir: Path = QURAN_DIR, seed_dir: Path = SEED_DIR) -> "ContentStore":
        metas = _parse_metadata(quran_dir / METADATA_FILE)
        arabic = _parse_tanzil_text(quran_dir / ARABIC_FILE)
        translations = {
            lang: _parse_tanzil_text(quran_dir / fname)
            for lang, fname in TRANSLATION_FILES.items()
        }

        for m in metas:
            ayat: list[Ayah] = []
            for a in range(1, m.ayas + 1):
                key = (m.number, a)
                ayat.append(
                    Ayah(
                        surah=m.number,
                        ayah=a,
                        text_ar=arabic.get(key, ""),
                        translations={
                            lang: tbl.get(key, "") for lang, tbl in translations.items()
                        },
                    )
                )
            # Keep the surah's ORIGINAL name (transliterated) in every language —
            # never the translated meaning. The Arabic original is in name_ar.
            names = {"en": m.tname, "fa": m.tname, "nl": m.tname}
            self._surahs[m.number] = Surah(
                number=m.number,
                name_ar=m.name_ar,
                name_translit=m.tname,
                names=names,
                revelation_place=m.revelation_place,
                ayat=ayat,
            )

        tafsir_path = seed_dir / "tafsir_seed.json"
        if tafsir_path.exists():
            self._tafsir = json.loads(tafsir_path.read_text(encoding="utf-8"))
        return self

    # ---- Quran ----

    def get_surah(self, number: int) -> Surah | None:
        return self._surahs.get(number)

    def list_surahs(self) -> list[Surah]:
        return [self._surahs[n] for n in sorted(self._surahs)]

    def get_ayah(self, surah: int, ayah: int) -> Ayah | None:
        s = self._surahs.get(surah)
        if not s:
            return None
        return next((a for a in s.ayat if a.ayah == ayah), None)

    # ---- Tafsir retrieval (RAG-lite; replace with vector search later) ----

    def retrieve(self, surah: int, ayah: int, lang: Lang) -> list[Passage]:
        """Return vetted passages for an ayah, preferring the requested language."""
        matches = [t for t in self._tafsir if t["surah"] == surah and t["ayah"] == ayah]
        preferred = [t for t in matches if t.get("lang") == lang] or matches
        return [
            Passage(text=t["text"], citation=Citation.model_validate(t["citation"]))
            for t in preferred
        ]


_store: ContentStore | None = None


def get_store() -> ContentStore:
    """Singleton accessor used as a FastAPI dependency."""
    global _store
    if _store is None:
        _store = ContentStore().load()
    return _store
