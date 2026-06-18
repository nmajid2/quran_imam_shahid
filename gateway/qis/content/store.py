"""In-memory content store.

Loads seed Quran + tafsir JSON at startup. This is the stand-in for the eventual
Postgres-backed content store; the route layer depends only on this interface, so the
storage backend can be swapped later without touching routes.

The tafsir lookup here is a deliberately simple "RAG-lite": exact ayah match. It will
be replaced by real vector retrieval over the vetted corpus (TECHNICAL_DESIGN §7),
but it already gives the gateway grounded, cited passages to reason over.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from qis.schema.intents import Citation, Lang
from qis.schema.models import Passage

SEED_DIR = Path(__file__).parent / "seed"


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


class ContentStore:
    def __init__(self) -> None:
        self._surahs: dict[int, Surah] = {}
        self._tafsir: list[dict] = []

    def load(self, seed_dir: Path = SEED_DIR) -> "ContentStore":
        for path in sorted(seed_dir.glob("quran_*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            ayat = [
                Ayah(
                    surah=data["number"],
                    ayah=a["ayah"],
                    text_ar=a["text_ar"],
                    translations=a.get("translations", {}),
                )
                for a in data["ayat"]
            ]
            self._surahs[data["number"]] = Surah(
                number=data["number"],
                name_ar=data["name_ar"],
                name_translit=data["name_translit"],
                names=data.get("names", {}),
                revelation_place=data.get("revelation_place", ""),
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
