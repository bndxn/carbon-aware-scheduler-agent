from typing import cast
from unittest.mock import patch

from carbon_intensity.agent import AgentRunResult, run_agent


def test_run_agent_records_working_chain() -> None:
    bedrock_turns = [
        {
            "stop_reason": "tool_use",
            "content": [
                {
                    "type": "tool_use",
                    "id": "toolu_01",
                    "name": "carbon_intensity_get",
                    "input": {"path": "/intensity"},
                }
            ],
        },
        {
            "stop_reason": "end_turn",
            "content": [{"type": "text", "text": "Final answer."}],
        },
    ]

    def fake_bedrock(**kwargs: object) -> dict[str, object]:
        return cast(dict[str, object], bedrock_turns.pop(0))

    with (
        patch(
            "carbon_intensity.agent._invoke_bedrock_messages", side_effect=fake_bedrock
        ),
        patch("carbon_intensity.agent._run_tool", return_value='{"ok": true}'),
    ):
        out = run_agent("What is intensity?", model="test-model")

    assert isinstance(out, AgentRunResult)
    assert out.reply == "Final answer."
    types = [step["type"] for step in out.working]
    assert types[0] == "system_prompt"
    assert types[1] == "user_prompt"
    assert types[2] == "meta"
    assert "bedrock_assistant" in types
    assert "tool_results" in types
    tool_step = next(s for s in out.working if s["type"] == "tool_results")
    assert tool_step["calls"][0]["name"] == "carbon_intensity_get"
    assert tool_step["calls"][0]["result"] == '{"ok": true}'
    assert tool_step["calls"][0]["result_truncated"] is False
