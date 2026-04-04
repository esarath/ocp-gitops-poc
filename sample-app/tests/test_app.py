import pytest
from app import app

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

def test_index(client):
    resp = client.get("/")
    data = resp.get_json()
    assert resp.status_code == 200
    assert data["app"] == "sample-app"
    assert "version" in data
    assert "environment" in data

def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "healthy"

def test_ready(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"
