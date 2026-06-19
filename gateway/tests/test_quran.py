from tests.conftest import AUTH


def test_list_surahs(client):
    r = client.get("/v1/quran", headers=AUTH)
    assert r.status_code == 200
    surahs = r.json()["surahs"]
    # Full Quran is loaded from the verified Tanzil source.
    assert len(surahs) == 114
    numbers = {s["number"] for s in surahs}
    assert numbers == set(range(1, 115))
    # Spot-check metadata for Al-Baqara (the longest surah).
    baqara = next(s for s in surahs if s["number"] == 2)
    assert baqara["ayah_count"] == 286
    assert baqara["name_ar"] == "البقرة"
    assert baqara["revelation_place"] == "madinah"


def test_get_surah_with_translations(client):
    r = client.get("/v1/quran/1", headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    assert data["ayah_count"] == 7
    first = data["ayat"][0]
    assert "text_ar" in first
    # All three target languages present.
    assert {"fa", "en", "nl"} <= set(first["translations"].keys())


def test_unknown_surah_404(client):
    # 115 is out of range (Quran has 114 surahs).
    assert client.get("/v1/quran/115", headers=AUTH).status_code == 404
