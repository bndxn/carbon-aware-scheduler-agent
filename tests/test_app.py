from unittest.mock import MagicMock, patch

import pytest

from carbon_intensity.api_client import call_carbon_intensity_api


def test_call_rejects_traversal() -> None:
    with pytest.raises(ValueError, match="Invalid path"):
        call_carbon_intensity_api("/intensity/../secrets")


@patch("carbon_intensity.api_client._session")
def test_call_parses_json_dict(mock_session_fn: MagicMock) -> None:
    mock_sess = MagicMock()
    mock_session_fn.return_value = mock_sess
    mock_resp = MagicMock()
    mock_resp.ok = True
    mock_resp.json.return_value = {"data": []}
    mock_sess.get.return_value = mock_resp
    out = call_carbon_intensity_api("/intensity")
    assert out == {"data": []}
    mock_sess.get.assert_called_once()
    call_kw = mock_sess.get.call_args
    assert call_kw[0][0] == "https://api.carbonintensity.org.uk/intensity"


@patch("carbon_intensity.api_client._session")
def test_http_error_raises(mock_session_fn: MagicMock) -> None:
    mock_sess = MagicMock()
    mock_session_fn.return_value = mock_sess
    mock_resp = MagicMock()
    mock_resp.ok = False
    mock_resp.status_code = 500
    mock_resp.text = "error"
    mock_sess.get.return_value = mock_resp
    with pytest.raises(RuntimeError, match="HTTP 500"):
        call_carbon_intensity_api("/intensity")
