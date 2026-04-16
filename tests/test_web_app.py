from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from carbon_intensity.web.app import app

client = TestClient(app)


def test_health() -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


@patch("carbon_intensity.web.app.run_agent", return_value="mocked reply")
def test_chat(mock_run: object) -> None:
    r = client.post("/api/chat", json={"message": "What is the carbon intensity?"})
    assert r.status_code == 200
    assert r.json() == {"reply": "mocked reply"}


def test_chat_validation() -> None:
    r = client.post("/api/chat", json={"message": ""})
    assert r.status_code == 422


@patch(
    "carbon_intensity.web.app.run_agent",
    side_effect=OSError("Bedrock invocation failed"),
)
def test_chat_propagates_oserror(mock_run: object) -> None:
    with pytest.raises(OSError):
        client.post("/api/chat", json={"message": "hello"})
