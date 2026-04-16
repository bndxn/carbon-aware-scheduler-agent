from __future__ import annotations

import json
import os
from collections.abc import Sequence
from typing import TYPE_CHECKING, Any

import boto3
import requests

from carbon_intensity.api_client import (
    call_carbon_intensity_api,
    format_api_result_for_model,
)
from carbon_intensity.open_meteo import (
    format_open_meteo_for_model,
    weather_wind_forecast_for_model,
)
from carbon_intensity.prompts import SYSTEM_PROMPT

DEFAULT_MODEL_ID = "anthropic.claude-3-5-sonnet-20241022-v2:0"
MAX_TOOL_ROUNDS = 16

TOOLS: list[dict[str, object]] = [
    {
        "name": "carbon_intensity_get",
        "description": (
            "GET JSON from the GB Carbon Intensity API. "
            "`path` is the path only (starts with /), e.g. `/intensity` or "
            "`/regional/postcode/SW1A`. Use `/generation` or regional blocks "
            "for `generationmix` when explaining why intensity is high/low."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": (
                        "API path starting with / (api.carbonintensity.org.uk)"
                    ),
                },
                "query_params": {
                    "type": "object",
                    "additionalProperties": {"type": "string"},
                    "description": "Optional query parameters (all string values).",
                },
            },
            "required": ["path"],
        },
    },
    {
        "name": "weather_wind_forecast",
        "description": (
            "Hourly weather and wind forecast from Open-Meteo (free) for a GB "
            "location. Pass `place_query` (e.g. London, Edinburgh, SW1A UK) or "
            "`latitude`+`longitude`. Complements Carbon Intensity data: correlates "
            "surface / 120 m wind with likely wind generation — not grid MW."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "place_query": {
                    "type": "string",
                    "description": (
                        "GB place or outward postcode, e.g. Cardiff or SW1A UK."
                    ),
                },
                "latitude": {"type": "number"},
                "longitude": {"type": "number"},
                "forecast_days": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 7,
                    "description": "Forecast horizon in days (default 3).",
                },
            },
            "required": [],
        },
    },
]


if TYPE_CHECKING:
    from mypy_boto3_bedrock_runtime import BedrockRuntimeClient
else:  # pragma: no cover
    BedrockRuntimeClient = Any


def _bedrock_runtime_client() -> BedrockRuntimeClient:
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    if region:
        return boto3.client("bedrock-runtime", region_name=region)
    return boto3.client("bedrock-runtime")


def _invoke_bedrock_messages(
    *,
    model_id: str,
    system: str,
    messages: list[dict[str, object]],
    tools: list[dict[str, object]],
    max_tokens: int,
) -> dict[str, object]:
    client = _bedrock_runtime_client()
    payload: dict[str, object] = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": max_tokens,
        "system": system,
        "messages": messages,
        "tools": tools,
    }

    resp = client.invoke_model(
        modelId=model_id,
        body=json.dumps(payload).encode("utf-8"),
        contentType="application/json",
        accept="application/json",
    )

    body = resp.get("body")
    raw_bytes = body.read() if hasattr(body, "read") else body
    if isinstance(raw_bytes, str):
        raw_text = raw_bytes
    elif isinstance(raw_bytes, bytes):
        raw_text = raw_bytes.decode("utf-8")
    else:
        raise RuntimeError("Unexpected Bedrock response body type.")
    out = json.loads(raw_text)
    if not isinstance(out, dict):
        raise RuntimeError("Unexpected Bedrock response JSON.")
    return out


def _text_from_assistant(content: object) -> str:
    parts: list[str] = []
    if isinstance(content, str):
        return content
    if isinstance(content, Sequence) and not isinstance(content, (str, bytes)):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(str(block.get("text", "")))
                continue
            text = getattr(block, "text", None)
            if isinstance(text, str):
                parts.append(text)
    return "".join(parts).strip()


def _run_tool(name: str, raw_input: dict[str, object]) -> str:
    if name == "carbon_intensity_get":
        path = raw_input.get("path", "")
        q = raw_input.get("query_params")
        if not isinstance(path, str) or not path.strip():
            return json.dumps({"error": "Missing or invalid `path`."})
        qp: dict[str, str] | None = None
        if isinstance(q, dict):
            qp = {str(k): str(v) for k, v in q.items()}
        try:
            data = call_carbon_intensity_api(path.strip(), query_params=qp)
            return format_api_result_for_model(data)
        except (ValueError, RuntimeError) as e:
            return json.dumps({"error": str(e)})
        except requests.RequestException as e:
            return json.dumps({"error": str(e)})

    if name == "weather_wind_forecast":
        pq = raw_input.get("place_query")
        lat_raw = raw_input.get("latitude")
        lon_raw = raw_input.get("longitude")
        fd_raw = raw_input.get("forecast_days", 3)
        place_query = str(pq).strip() if isinstance(pq, str) else None
        latitude = float(lat_raw) if isinstance(lat_raw, int | float) else None
        longitude = float(lon_raw) if isinstance(lon_raw, int | float) else None
        if isinstance(fd_raw, bool):
            forecast_days = 3
        elif isinstance(fd_raw, int):
            forecast_days = fd_raw
        elif isinstance(fd_raw, float):
            forecast_days = int(fd_raw)
        elif isinstance(fd_raw, str):
            try:
                forecast_days = int(fd_raw.strip())
            except ValueError:
                forecast_days = 3
        else:
            forecast_days = 3
        forecast_days = max(1, min(7, forecast_days))
        try:
            data = weather_wind_forecast_for_model(
                place_query=place_query,
                latitude=latitude,
                longitude=longitude,
                forecast_days=forecast_days,
            )
            return format_open_meteo_for_model(data)
        except (ValueError, RuntimeError, TypeError) as e:
            return json.dumps({"error": str(e)})
        except requests.RequestException as e:
            return json.dumps({"error": str(e)})

    return json.dumps({"error": f"Unknown tool: {name}"})


def run_agent(user_message: str, *, model: str | None = None) -> str:
    use_model = model or os.environ.get("BEDROCK_MODEL_ID", DEFAULT_MODEL_ID)

    messages: list[dict[str, object]] = [{"role": "user", "content": user_message}]
    rounds = 0

    while rounds < MAX_TOOL_ROUNDS:
        rounds += 1
        response = _invoke_bedrock_messages(
            model_id=use_model,
            max_tokens=8192,
            system=SYSTEM_PROMPT,
            messages=messages,
            tools=TOOLS,
        )

        stop_reason = response.get("stop_reason")
        content = response.get("content", [])

        if stop_reason == "end_turn":
            return _text_from_assistant(content) or "(No text reply.)"

        if stop_reason != "tool_use":
            return _text_from_assistant(content) or str(stop_reason)

        tool_result_blocks: list[dict[str, object]] = []
        if isinstance(content, Sequence) and not isinstance(content, (str, bytes)):
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_use":
                    continue
                name = block.get("name", "")
                tool_id = block.get("id", "")
                raw_input = block.get("input", {})
                if not isinstance(raw_input, dict):
                    raw_input = {}
                coerced = {str(k): v for k, v in raw_input.items()}
                out = _run_tool(str(name), coerced)
                tool_result_blocks.append(
                    {"type": "tool_result", "tool_use_id": str(tool_id), "content": out}
                )

        messages.append({"role": "assistant", "content": content})
        messages.append({"role": "user", "content": tool_result_blocks})

    return "Stopped: too many tool rounds (possible loop)."
