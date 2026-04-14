from __future__ import annotations

from mangum import Mangum

from carbon_intensity.web.app import app

# Lambda entrypoint for API Gateway HTTP API proxy events.
handler = Mangum(app)
