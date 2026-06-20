"""Shia tafsir store — per-ayah commentary from multiple verified sources.

Reads the bundled tafsir SQLite databases (see `tafsir_data/SOURCES.md`) and serves
passage-level commentary for an ayah. The user can pick which tafsir to read, the same
way they pick a reciter.

Only the **Persian** (authentic, human-authored) editions are exposed — the English/Urdu
columns in the upstream data are AI-produced and deliberately NOT served (project hard
rule #1: content must be authentic, never AI-generated).

The `.db` files are git-ignored; they are extracted from the committed `.tar.xz` archives
on first load. Each DB shares the schema:
    ayah_mapping(surah_number, ayah_number, content_id)  -- all 6236 ayat
    content(content_id, <persian_column>, ...)           -- Markdown passages
"""

from __future__ import annotations

import sqlite3
import tarfile
from dataclasses import dataclass
from pathlib import Path

CONTENT_DIR = Path(__file__).parent
TAFSIR_DIR = CONTENT_DIR / "tafsir_data"

ATTRIBUTION = "Tafsir data © Furqan Apps (furqan.app), CC BY-ND 4.0."


@dataclass(frozen=True)
class TafsirResult:
    content: str  # Markdown
    ayah_start: int
    ayah_end: int


@dataclass(frozen=True)
class TafsirEdition:
    id: str
    name: str  # transliterated (original) name — never a translated meaning
    name_fa: str
    author: str
    archive: str  # .tar.xz in TAFSIR_DIR
    db_basename: str  # the .db file inside the archive
    column: str  # the Persian content column
    lang: str = "fa"

    def to_payload(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "name_fa": self.name_fa,
            "author": self.author,
            "lang": self.lang,
        }


# Persian, authentic Shia tafsirs (order = display order in the picker).
EDITIONS: list[TafsirEdition] = [
    TafsirEdition(
        id="almizan",
        name="Al-Mizan",
        name_fa="المیزان",
        author="Allamah Tabatabai",
        archive="tafsir_almizan_fa.db.tar.xz",
        db_basename="tafsir_almizan_fa.db",
        column="content",
    ),
    TafsirEdition(
        id="nemooneh",
        name="Nemooneh",
        name_fa="نمونه",
        author="Makarem Shirazi",
        archive="tafsir_nemouneh_fa_en_ur.tar.xz",
        db_basename="tafsir_namouneh.db",
        column="content",
    ),
    TafsirEdition(
        id="noor",
        name="Noor",
        name_fa="نور",
        author="Mohsen Qaraati",
        archive="tafsir-noor.tar.xz",
        db_basename="tafsir-noor.db",
        column="content_fa",
    ),
]


def _ensure_extracted(edition: TafsirEdition, base: Path) -> Path:
    """Return the path to the edition's .db, extracting it from the archive if needed."""
    existing = next(base.rglob(edition.db_basename), None)
    if existing is not None:
        return existing
    archive_path = base / edition.archive
    with tarfile.open(archive_path, "r:xz") as tar:
        tar.extractall(base)  # noqa: S202 — trusted, version-pinned local archives
    found = next(base.rglob(edition.db_basename), None)
    if found is None:
        raise FileNotFoundError(
            f"{edition.db_basename} not found in {edition.archive} after extraction"
        )
    return found


class TafsirStore:
    def __init__(self) -> None:
        self._editions: dict[str, TafsirEdition] = {}
        self._paths: dict[str, Path] = {}

    def load(self, base: Path = TAFSIR_DIR) -> "TafsirStore":
        for edition in EDITIONS:
            self._paths[edition.id] = _ensure_extracted(edition, base)
            self._editions[edition.id] = edition
        return self

    def list_editions(self) -> list[TafsirEdition]:
        return [e for e in EDITIONS if e.id in self._editions]

    def get_edition(self, tafsir_id: str) -> TafsirEdition | None:
        return self._editions.get(tafsir_id)

    def retrieve(self, tafsir_id: str, surah: int, ayah: int) -> "TafsirResult | None":
        """Commentary for an ayah from one tafsir, with the ayah-range it covers.

        These tafsirs are passage-based: one content block can span several ayat
        (heavily so for al-Mizan). The returned `ayah_start..ayah_end` is the full
        range the block covers within this surah, so the UI can show it honestly.
        """
        edition = self._editions.get(tafsir_id)
        if edition is None:
            return None
        # Read-only, short-lived connection (sync route runs in a worker thread).
        uri = f"file:{self._paths[tafsir_id]}?mode=ro"
        con = sqlite3.connect(uri, uri=True)
        try:
            row = con.execute(
                "SELECT content_id FROM ayah_mapping "
                "WHERE surah_number=? AND ayah_number=?",
                (surah, ayah),
            ).fetchone()
            if row is None:
                return None
            content_id = row[0]
            # Column comes from our fixed catalog, never user input.
            text = con.execute(
                f"SELECT {edition.column} FROM content WHERE content_id=?",
                (content_id,),
            ).fetchone()
            if not text or not text[0]:
                return None
            rng = con.execute(
                "SELECT MIN(ayah_number), MAX(ayah_number) FROM ayah_mapping "
                "WHERE surah_number=? AND content_id=?",
                (surah, content_id),
            ).fetchone()
            return TafsirResult(
                content=text[0],
                ayah_start=rng[0] or ayah,
                ayah_end=rng[1] or ayah,
            )
        finally:
            con.close()

    def retrieve_surah(self, tafsir_id: str, surah: int) -> dict | None:
        """All distinct commentary blocks for a surah + an ayah→block index.

        Deduplicated so a passage-based tafsir (e.g. al-Mizan, where one block can
        cover 10+ ayat) is sent once, not repeated per ayah. Powers offline download.
        """
        edition = self._editions.get(tafsir_id)
        if edition is None:
            return None
        uri = f"file:{self._paths[tafsir_id]}?mode=ro"
        con = sqlite3.connect(uri, uri=True)
        try:
            rows = con.execute(
                "SELECT ayah_number, content_id FROM ayah_mapping "
                "WHERE surah_number=? ORDER BY ayah_number",
                (surah,),
            ).fetchall()
            if not rows:
                return None
            blocks: list[dict] = []
            index_of: dict[int, int] = {}  # content_id -> block index
            ayah_to_block: dict[int, int] = {}
            for ayah_number, content_id in rows:
                if content_id not in index_of:
                    text = con.execute(
                        f"SELECT {edition.column} FROM content WHERE content_id=?",
                        (content_id,),
                    ).fetchone()
                    rng = con.execute(
                        "SELECT MIN(ayah_number), MAX(ayah_number) FROM ayah_mapping "
                        "WHERE surah_number=? AND content_id=?",
                        (surah, content_id),
                    ).fetchone()
                    index_of[content_id] = len(blocks)
                    blocks.append(
                        {
                            "ayah_start": rng[0],
                            "ayah_end": rng[1],
                            "content": (text[0] if text and text[0] else ""),
                        }
                    )
                ayah_to_block[ayah_number] = index_of[content_id]
            return {"blocks": blocks, "ayah_to_block": ayah_to_block}
        finally:
            con.close()


_store: TafsirStore | None = None


def get_tafsir_store() -> TafsirStore:
    """Singleton accessor used as a FastAPI dependency."""
    global _store
    if _store is None:
        _store = TafsirStore().load()
    return _store
