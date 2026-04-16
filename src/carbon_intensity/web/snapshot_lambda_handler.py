from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from typing import Any

import boto3

from carbon_intensity.agent import run_agent


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del event, context

    bucket = os.environ["SNAPSHOT_BUCKET"]
    key = os.environ.get("SNAPSHOT_KEY", "snapshot.json")
    prompt = os.environ.get(
        "SNAPSHOT_PROMPT",
        "Give a concise update on current and near-term GB grid carbon intensity "
        "and practical low-carbon timing advice.",
    )

    reply = run_agent(prompt)

    payload = {
        "generated_at": datetime.now(UTC).isoformat(),
        "prompt": prompt,
        "reply": reply,
    }

    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload, ensure_ascii=True).encode("utf-8"),
        ContentType="application/json",
        CacheControl="max-age=60",
    )

    return {"status": "ok", "bucket": bucket, "key": key}
