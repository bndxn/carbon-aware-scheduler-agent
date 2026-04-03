from __future__ import annotations

import json
import os
from collections.abc import Sequence

import anthropic
import requests
from anthropic.types import MessageParam, ToolParam, ToolResultBlockParam

from carbon_intensity.api_client import (
    call_carbon_intensity_api,
    format_api_result_for_model,
)
from carbon_intensity.prompts import SYSTEM_PROMPT

DEFAULT_MODEL = "claude-sonnet-4-6"
MAX_TOOL_ROUNDS = 12

TOOLS: list[ToolParam] = [
    {
        "name": "carbon_intensity_get",
        "description": (
            "GET JSON from the GB Carbon Intensity API. "
            "`path` is the path only (starts with /), e.g. `/intensity` or "
            "`/regional/postcode/SW1`. Optional query string parameters as strings."
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
    }
]


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


def run_agent(user_message: str, *, model: str | None = None) -> str:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        msg = "Set ANTHROPIC_API_KEY in your environment (e.g. in .env)."
        raise OSError(msg)

    client = anthropic.Anthropic(api_key=api_key)
    use_model = model or os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)

    messages: list[MessageParam] = [{"role": "user", "content": user_message}]
    rounds = 0

    while rounds < MAX_TOOL_ROUNDS:
        rounds += 1
        response = client.messages.create(
            model=use_model,
            max_tokens=8192,
            system=SYSTEM_PROMPT,
            messages=messages,
            tools=TOOLS,
        )

        if response.stop_reason == "end_turn":
            return _text_from_assistant(response.content) or "(No text reply.)"

        if response.stop_reason != "tool_use":
            return _text_from_assistant(response.content) or str(response.stop_reason)

        tool_result_blocks: list[ToolResultBlockParam] = []
        for block in response.content:
            btype = getattr(block, "type", None)
            if btype != "tool_use":
                continue
            name = getattr(block, "name", "")
            tool_id = getattr(block, "id", "")
            raw_input = getattr(block, "input", {})
            if not isinstance(raw_input, dict):
                raw_input = {}
            if name != "carbon_intensity_get":
                err = json.dumps({"error": f"Unknown tool: {name}"})
                tool_result_blocks.append(
                    {"type": "tool_result", "tool_use_id": tool_id, "content": err}
                )
                continue
            path = raw_input.get("path", "")
            q = raw_input.get("query_params")
            if not isinstance(path, str) or not path.strip():
                err = json.dumps({"error": "Missing or invalid `path`."})
                tool_result_blocks.append(
                    {"type": "tool_result", "tool_use_id": tool_id, "content": err}
                )
                continue
            qp: dict[str, str] | None = None
            if isinstance(q, dict):
                qp = {str(k): str(v) for k, v in q.items()}
            try:
                data = call_carbon_intensity_api(path.strip(), query_params=qp)
                out = format_api_result_for_model(data)
            except (ValueError, RuntimeError) as e:
                out = json.dumps({"error": str(e)})
            except requests.RequestException as e:
                out = json.dumps({"error": str(e)})
            tool_result_blocks.append(
                {"type": "tool_result", "tool_use_id": tool_id, "content": out}
            )

        messages.append({"role": "assistant", "content": response.content})
        messages.append({"role": "user", "content": tool_result_blocks})

    return "Stopped: too many tool rounds (possible loop)."
