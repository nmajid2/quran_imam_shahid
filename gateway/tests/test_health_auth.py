from tests.conftest import AUTH


def test_healthz_is_public(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_protected_route_requires_token(client):
    assert client.get("/v1/quran").status_code == 401


def test_protected_route_rejects_wrong_token(client):
    r = client.get("/v1/quran", headers={"Authorization": "Bearer wrong"})
    assert r.status_code == 401


def test_protected_route_accepts_valid_token(client):
    assert client.get("/v1/quran", headers=AUTH).status_code == 200
