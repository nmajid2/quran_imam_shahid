from tests.conftest import AUTH


def test_list_surahs(client):
    r = client.get("/v1/quran", headers=AUTH)
    assert r.status_code == 200
    numbers = {s["number"] for s in r.json()["surahs"]}
    assert {1, 112} <= numbers


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
    assert client.get("/v1/quran/77", headers=AUTH).status_code == 404
