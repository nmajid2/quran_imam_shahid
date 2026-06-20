"""Reciter catalog — the list of Qaris the app can play/download audio for.

Loads `qis/content/reciters.json` (a verified manifest of EveryAyah folders) at startup
and resolves per-ayah audio URLs. Mirrors the ContentStore pattern: routes depend only on
this interface, so the audio backend (EveryAyah now → self-hosted/proxied later) can be
swapped without touching them.

Audio source = EveryAyah: one MP3 per ayah, addressed as
    {base_url}/{folder}/{surah:03d}{ayah:03d}.mp3
e.g. surah 2, ayah 286 → https://everyayah.com/data/Parhizgar_48kbps/002286.mp3

The audio is NEVER generated — only referenced from the verified manifest, the same
posture as the sacred text.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

CONTENT_DIR = Path(__file__).parent
RECITERS_FILE = CONTENT_DIR / "reciters.json"


@dataclass(frozen=True)
class Reciter:
    id: str
    display_name: str
    folder: str
    bitrate_kbps: int
    style: str
    tradition: str
    display_name_fa: str | None = None

    def to_payload(self) -> dict:
        payload = {
            "id": self.id,
            "display_name": self.display_name,
            "folder": self.folder,
            "bitrate_kbps": self.bitrate_kbps,
            "style": self.style,
            "tradition": self.tradition,
        }
        if self.display_name_fa:
            payload["display_name_fa"] = self.display_name_fa
        return payload


class ReciterCatalog:
    def __init__(self) -> None:
        self._reciters: dict[str, Reciter] = {}
        self._order: list[str] = []
        self._base_url: str = ""
        self._default_id: str = ""

    def load(self, path: Path = RECITERS_FILE) -> "ReciterCatalog":
        data = json.loads(path.read_text(encoding="utf-8"))
        self._base_url = data["source"]["base_url"].rstrip("/")
        self._default_id = data["default_reciter"]
        for r in data["reciters"]:
            reciter = Reciter(
                id=r["id"],
                display_name=r["display_name"],
                folder=r["folder"],
                bitrate_kbps=r["bitrate_kbps"],
                style=r["style"],
                tradition=r["tradition"],
                display_name_fa=r.get("display_name_fa"),
            )
            self._reciters[reciter.id] = reciter
            self._order.append(reciter.id)
        if self._default_id not in self._reciters:
            raise ValueError(f"default_reciter '{self._default_id}' not in reciters list")
        return self

    @property
    def default_id(self) -> str:
        return self._default_id

    def list_reciters(self) -> list[Reciter]:
        return [self._reciters[i] for i in self._order]

    def get(self, reciter_id: str) -> Reciter | None:
        return self._reciters.get(reciter_id)

    def audio_url(self, reciter_id: str, surah: int, ayah: int) -> str | None:
        """Resolve the per-ayah MP3 URL, or None if the reciter is unknown."""
        reciter = self._reciters.get(reciter_id)
        if not reciter:
            return None
        return f"{self._base_url}/{reciter.folder}/{surah:03d}{ayah:03d}.mp3"


_catalog: ReciterCatalog | None = None


def get_catalog() -> ReciterCatalog:
    """Singleton accessor used as a FastAPI dependency."""
    global _catalog
    if _catalog is None:
        _catalog = ReciterCatalog().load()
    return _catalog
