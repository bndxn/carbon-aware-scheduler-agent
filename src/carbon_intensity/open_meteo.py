from __future__ import annotations

import json
from typing import Any, cast

from carbon_intensity.retry_session import retry_session

_GEO_BASE = "https://geocoding-api.open-meteo.com/v1"
_FORECAST_BASE = "https://api.open-meteo.com/v1"
_SESSION = retry_session(
    user_agent=(
        "carbon-aware-scheduler-agent/0.1 "
        "(weather via Open-Meteo; https://open-meteo.com/)"
    )
)

_TIMEOUT: tuple[float, float] = (15.0, 60.0)

_HOURLY_VARS = (
    "temperature_2m",
    "cloud_cover",
    "wind_speed_10m",
    "wind_speed_120m",
    "wind_direction_10m",
)


def geocode_gb(place_query: str) -> dict[str, Any] | None:
    """Resolve a name to coordinates, restricted to GB."""
    q = place_query.strip()
    if not q or "\n" in q:
        return None
    geo_params: dict[str, str | int] = {
        "name": q,
        "count": 5,
        "country": "GB",
        "format": "json",
    }
    resp = _SESSION.get(
        f"{_GEO_BASE}/search",
        params=geo_params,
        timeout=_TIMEOUT,
    )
    if not resp.ok:
        detail = resp.text[:1000]
        msg = f"Geocoding HTTP {resp.status_code}: {detail}"
        raise RuntimeError(msg)
    payload: dict[str, Any] = resp.json()
    results = payload.get("results")
    if not isinstance(results, list) or not results:
        return None
    first = results[0]
    if not isinstance(first, dict):
        return None
    return first


def fetch_forecast_hourly(
    latitude: float,
    longitude: float,
    *,
    forecast_days: int,
    timezone: str = "Europe/London",
) -> dict[str, Any]:
    days = max(1, min(7, forecast_days))
    fc_params: dict[str, str | int | float] = {
        "latitude": latitude,
        "longitude": longitude,
        "hourly": ",".join(_HOURLY_VARS),
        "forecast_days": days,
        "timezone": timezone,
        "wind_speed_unit": "ms",
    }
    resp = _SESSION.get(
        f"{_FORECAST_BASE}/forecast",
        params=fc_params,
        timeout=_TIMEOUT,
    )
    if not resp.ok:
        detail = resp.text[:1000]
        msg = f"Forecast HTTP {resp.status_code}: {detail}"
        raise RuntimeError(msg)
    return cast(dict[str, Any], resp.json())


def subsample_hourly(data: dict[str, Any], max_rows: int = 56) -> dict[str, Any]:
    """Keep payloads small for the model (≈2–3 day hourly → ~56 points)."""
    hourly = data.get("hourly")
    if not isinstance(hourly, dict):
        return data
    times = hourly.get("time")
    if not isinstance(times, list):
        return data
    n = len(times)
    if n <= max_rows:
        return data
    step = max(1, n // max_rows)
    idx = list(range(0, n, step))[:max_rows]
    new_h: dict[str, Any] = {
        k: [cast(list[Any], hourly[k])[i] for i in idx]
        for k in hourly
        if isinstance(hourly[k], list) and len(cast(list[Any], hourly[k])) == n
    }
    out = {k: v for k, v in data.items() if k != "hourly"}
    out["hourly"] = new_h
    out["hourly_subsampled"] = True
    out["hourly_subsample_note"] = (
        f"Hourly series downsampled ({n} → {len(idx)} steps) for context limits."
    )
    return out


def weather_wind_forecast_for_model(
    *,
    place_query: str | None,
    latitude: float | None,
    longitude: float | None,
    forecast_days: int = 3,
) -> dict[str, Any]:
    meta: dict[str, Any] = {
        "source": "Open-Meteo (CC BY 4.0)",
        "note": (
            "Point forecast near a location, not National Grid wind generation MW. "
            "Use with Carbon Intensity `generationmix` (especially `wind` %)."
        ),
    }
    if place_query and place_query.strip():
        geo = geocode_gb(place_query.strip())
        if geo is None:
            return {
                **meta,
                "error": f"No GB geocoding match for: {place_query!r}",
            }
        lat = float(geo["latitude"])
        lon = float(geo["longitude"])
        meta["geocoding"] = {
            "name": geo.get("name"),
            "admin1": geo.get("admin1"),
            "latitude": lat,
            "longitude": lon,
        }
    elif latitude is not None and longitude is not None:
        lat, lon = float(latitude), float(longitude)
        meta["geocoding"] = {"latitude": lat, "longitude": lon}
    else:
        return {
            **meta,
            "error": "Provide `place_query` (GB) or both `latitude` and `longitude`.",
        }

    fc = fetch_forecast_hourly(lat, lon, forecast_days=forecast_days)
    trimmed = subsample_hourly(fc)
    return {**meta, "forecast": trimmed}


def format_open_meteo_for_model(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2)[:120_000]
