from __future__ import annotations

import json
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

BASE_URL = "https://api.carbonintensity.org.uk"

_SESSION: requests.Session | None = None


def _session() -> requests.Session:
    """Shared session: keep-alive, retries on flaky connections and 5xx."""
    global _SESSION
    if _SESSION is not None:
        return _SESSION

    retries = Retry(
        total=5,
        connect=5,
        read=5,
        backoff_factor=1.0,
        status_forcelist=(429, 502, 503, 504),
        allowed_methods=frozenset({"GET"}),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retries)
    s = requests.Session()
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    s.headers.update(
        {
            "Accept": "application/json",
            "User-Agent": "carbon-aware-scheduler-agent/0.1 (+https://github.com/carbon-intensity)",
        }
    )
    _SESSION = s
    return s


def call_carbon_intensity_api(
    path: str,
    *,
    query_params: dict[str, str] | None = None,
    timeout_s: tuple[float, float] | float = (20.0, 120.0),
) -> dict[str, Any]:
    """GET JSON for a path on the GB Carbon Intensity API (path only, fixed host)."""
    p = path if path.startswith("/") else f"/{path}"
    if "\n" in p or "\r" in p or ".." in p:
        msg = "Invalid path"
        raise ValueError(msg)
    url = f"{BASE_URL}{p}"
    resp = _session().get(url, params=query_params or {}, timeout=timeout_s)
    if not resp.ok:
        detail = resp.text[:2000]
        msg = f"HTTP {resp.status_code}: {detail}"
        raise RuntimeError(msg)
    data: Any = resp.json()
    if isinstance(data, dict):
        return data
    return {"data": data}


def format_api_result_for_model(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2)[:120_000]
