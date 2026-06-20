from tests.conftest import AUTH


def test_list_reciters(client):
    r = client.get("/v1/reciters", headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    # Default reciter is the Shia/Iranian Parhizgar (explicit user preference).
    assert data["default"] == "parhizgar"
    reciters = data["reciters"]
    ids = {x["id"] for x in reciters}
    assert "parhizgar" in ids
    # Abdul Basit must be present (both styles).
    assert {"abdul_basit_murattal", "abdul_basit_mujawwad"} <= ids
    # Parhizgar carries a Persian display name.
    parhizgar = next(x for x in reciters if x["id"] == "parhizgar")
    assert parhizgar["tradition"] == "shia"
    assert "display_name_fa" in parhizgar


def test_reciters_require_auth(client):
    assert client.get("/v1/reciters").status_code == 401


def test_ayah_audio_url(client):
    r = client.get("/v1/audio/parhizgar/2/286", headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    # Zero-padded EveryAyah scheme: surah 002, ayah 286.
    assert data["url"] == "https://everyayah.com/data/Parhizgar_48kbps/002286.mp3"


def test_ayah_audio_unknown_reciter(client):
    assert client.get("/v1/audio/nobody/1/1", headers=AUTH).status_code == 404


def test_ayah_audio_out_of_range(client):
    # Al-Fatiha has 7 ayat; ayah 8 does not exist.
    assert client.get("/v1/audio/parhizgar/1/8", headers=AUTH).status_code == 404


def test_surah_audio_list(client):
    r = client.get("/v1/audio/abdul_basit_murattal/1", headers=AUTH)
    assert r.status_code == 200
    data = r.json()
    assert data["ayah_count"] == 7
    assert len(data["urls"]) == 7
    assert data["urls"][0]["url"].endswith("/Abdul_Basit_Murattal_64kbps/001001.mp3")
    assert data["urls"][6]["url"].endswith("/Abdul_Basit_Murattal_64kbps/001007.mp3")
