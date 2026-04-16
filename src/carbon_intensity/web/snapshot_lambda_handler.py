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
        (
            "Find the best day and approximate time window in the next few days to "
            "start a washing machine in Great Britain. Optimise for (1) lower grid "
            "carbon intensity during the wash and (2) clothes drying afterward: I can "
            "dry indoors or outside but prefer line drying outside, which needs dry "
            "weather and ideally mild or warm conditions. If I did not name a place, "
            "use London, UK as the default for weather_wind_forecast. Reply in "
            "Markdown with one primary recommendation, one backup, and short "
            "reasoning."
        ),
    )

    result = run_agent(prompt)

    payload = {
        "generated_at": datetime.now(UTC).isoformat(),
        "prompt": prompt,
        "reply": result.reply,
        "working": result.working,
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
