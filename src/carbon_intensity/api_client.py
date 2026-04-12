from __future__ import annotations

import json
from typing import Any

import requests

from carbon_intensity.retry_session import retry_session

BASE_URL = "https://api.carbonintensity.org.uk"

_SESSION: requests.Session | None = None


def _session() -> requests.Session:
    """Shared session: keep-alive, retries on flaky connections and 5xx."""
    global _SESSION
    if _SESSION is not None:
        return _SESSION
    _SESSION = retry_session(
        user_agent=(
            "carbon-aware-scheduler-agent/0.1 (+https://github.com/carbon-intensity)"
        )
    )
    return _SESSION


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
