# carbon-aware-scheduler-agent

Python agent that answers questions about **Great Britain grid carbon intensity** and related timing (including a **washing-machine / drying** scenario). It calls the official **Carbon Intensity API**, **Open-Meteo** for local weather, and **AWS Bedrock** (Claude) to plan tool use and explain results.

**Carbon Intensity API reference:** [carbon-intensity.github.io — API definitions](https://carbon-intensity.github.io/api-definitions/#carbon-intensity-api-v2-0-0)

## What’s in this repo

| Area | Purpose |
|------|---------|
| `src/carbon_intensity/` | Agent (`run_agent`), Bedrock tool loop, API client, Open-Meteo helper, prompts |
| `app.py` | CLI: ask a question; prints the model’s **reply** |
| `site/` | Static site: loads `snapshot.json`, renders Markdown reply, optional **“See my working”** trace |
| `infra/` | Terraform: snapshot Lambda, S3 + CloudFront (optional WAF), EventBridge **Scheduler**, alarms/SNS, optional GitHub OIDC deploy role |
| `.github/workflows/` | **CI** (pre-commit + pytest), **Deploy** (Lambda zip + `site/` sync + CloudFront invalidation) |

Scheduled runs write **`snapshot.json`** (prompt, reply, `working` trace, timestamp) next to the static objects so the page stays cheap to serve.

## Requirements

- **Python 3.14+**
- **[uv](https://docs.astral.sh/uv/)** (recommended)
- For local Bedrock use: AWS credentials and `BEDROCK_MODEL_ID` (or inference profile ARN) in the right account/region

## Local development

```bash
uv sync --all-groups
uv run pytest
uv run pre-commit run --all-files
```

**CLI** (loads `.env` if present):

```bash
uv run python app.py "What is current national GB carbon intensity?"
```

**HTTP API** (optional): `uvicorn carbon_intensity.web.app:app --reload` — `POST /api/chat` with `{"message":"..."}` returns `reply` and `working`.

Agent return type is **`AgentRunResult`**: `reply` (string) and `working` (list of trace steps for auditing/UI).

## AWS layout

Provisioning, variables, alarms, WAF, and GitHub deploy wiring are documented in **`infra/README.md`**.

Typical flow:

1. `terraform apply` in `infra/` (see `terraform.tfvars.example`).
2. Configure GitHub **Actions** secret `AWS_ROLE_ARN` and repo **variables** from `terraform output` (`SNAPSHOT_LAMBDA_FUNCTION_NAME`, `S3_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, etc.).
3. Push to **`main`**: deploy workflow updates Lambda code and syncs `site/` to S3.

CloudFront uses an ACM certificate in **`us-east-1`** only if you add a custom domain (see open work in issues); the default distribution hostname works without that.

## License / data

- **Carbon Intensity API** — national/regional GB data; see their terms.
- **Open-Meteo** — weather; attribution per [Open-Meteo](https://open-meteo.com/).
