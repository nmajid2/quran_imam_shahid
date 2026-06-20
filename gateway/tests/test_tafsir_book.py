from tests.conftest import AUTH


def test_list_tafsirs(client):
    r = client.get("/v1/tafsirs", headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    ids = {t["id"] for t in data["tafsirs"]}
    # The three authentic Persian Shia tafsirs.
    assert {"almizan", "nemooneh", "noor"} <= ids
    assert "Furqan" in data["attribution"]
    almizan = next(t for t in data["tafsirs"] if t["id"] == "almizan")
    assert almizan["lang"] == "fa"
    assert almizan["author"] == "Allamah Tabatabai"


def test_tafsirs_require_auth(client):
    assert client.get("/v1/tafsirs").status_code == 401


def test_get_tafsir_content(client):
    # Ayat al-Kursi (2:255) — every edition has substantial commentary here.
    for tid in ("almizan", "nemooneh", "noor"):
        r = client.get(f"/v1/tafsir/{tid}/2/255", headers=AUTH)
        assert r.status_code == 200, tid
        data = r.json()
        assert data["format"] == "markdown"
        assert len(data["content"]) > 200, tid
        # The block reports the ayah-range it covers (passage-based tafsir).
        assert data["ayah_start"] <= 255 <= data["ayah_end"]


def test_surah_tafsir_bulk_dedup(client):
    # Al-Fatiha: deduped blocks + a full ayah→block index for offline caching.
    r = client.get("/v1/tafsir/almizan/1", headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    # Every ayah (1..7) is indexed to a block.
    assert {str(a) for a in range(1, 8)} <= set(data["ayah_to_block"].keys())
    # Deduped: al-Mizan groups ayat, so far fewer blocks than 7 ayat.
    assert len(data["blocks"]) < 7
    # Block index points to a real block with content + range.
    b = data["blocks"][data["ayah_to_block"]["1"]]
    assert b["content"] and b["ayah_start"] <= 1 <= b["ayah_end"]


def test_tafsir_unknown_edition(client):
    assert client.get("/v1/tafsir/nope/1/1", headers=AUTH).status_code == 404


def test_tafsir_unknown_ayah(client):
    # Al-Fatiha has 7 ayat.
    assert client.get("/v1/tafsir/almizan/1/99", headers=AUTH).status_code == 404
