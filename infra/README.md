# Terraform: scheduled snapshot Lambda + static site on S3 / CloudFront

Creates:

- **Lambda** function for scheduled snapshot generation, triggered by **EventBridge Scheduler** (default **daily at 06:00 `Europe/London`**), writing `snapshot.json` to the static S3 bucket
- **IAM** execution role for Lambda (CloudWatch logs + Bedrock invoke + write snapshot to S3)
- **Bedrock model invocation** (Claude via Bedrock) using IAM auth (no external API key)
- **S3** bucket (private) + **CloudFront** distribution with **origin access control (OAC)** and response security headers
- **CloudWatch alarms + SNS topic** for snapshot reliability and optional CloudFront 5xx monitoring
- **Optional GitHub Actions deploy role** (OIDC): set `github_repository` to `owner/repo` to create an IAM role with snapshot Lambda update, S3 sync, and CloudFront invalidation (use `terraform output -raw github_actions_deploy_role_arn` as **`AWS_ROLE_ARN`**)

Requires **Terraform >= 1.5** and **hashicorp/aws >= 6.23**.

## Prerequisites

- AWS credentials with permission to create these resources (often `AdministratorAccess` while iterating; tighten later).
- **GitHub OIDC provider** in IAM (once per account): provider URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`. If `terraform plan` errors on the `aws_iam_openid_connect_provider` data source, add that provider in **IAM -> Identity providers** first.

## Configure

1. Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored) and set any overrides you want (e.g. `bedrock_model_id`), or just use defaults.

2. Optional: adjust `aws_region`, `project_name`, and Lambda sizing variables in `terraform.tfvars`.

3. Optional (deploy from GitHub): set `github_repository = "your-org/carbon-aware-scheduler-agent"` (and `github_deploy_branch` if not `main`). Apply, then set GitHub secret **`AWS_ROLE_ARN`** to `terraform output -raw github_actions_deploy_role_arn`.

4. Create an initial placeholder Lambda package before first apply:

   ```bash
   mkdir -p artifacts build/placeholder
   printf 'def handler(event, context):\n    return {"statusCode": 200, "body": "ok"}\n' > build/placeholder/lambda_function.py
   (cd build/placeholder && zip -q ../lambda.zip lambda_function.py)
   mv build/lambda.zip artifacts/lambda.zip
   ```

## Apply

```bash
cd infra
terraform init
terraform plan
terraform apply
```

## Local profile reminder

When running Terraform locally for this stack, use the expected AWS profile:

```bash
cd infra
set -a && source ../.env && export AWS_PROFILE=carbon-local-dev && set +a
terraform plan -input=false
terraform apply
```

This avoids account mismatches and ensures Terraform uses the local `carbon-local-dev` credentials.

## Outputs -> GitHub Actions

After apply, set **repository variables** (Settings -> Secrets and variables -> Actions -> Variables):

| Variable | Source |
|----------|--------|
| `AWS_REGION` | Same as `aws_region` (e.g. `eu-west-2`) |
| `SNAPSHOT_LAMBDA_FUNCTION_NAME` | `terraform output -raw snapshot_lambda_function_name` |
| `S3_BUCKET` | `terraform output -raw static_site_bucket_name` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `terraform output -raw cloudfront_distribution_id` |

If you use **`github_repository`** in Terraform, set **`AWS_ROLE_ARN`** to **`github_actions_deploy_role_arn`** from outputs. If you created the deploy role manually instead, keep that ARN in **`AWS_ROLE_ARN`**.

Static site URL: `terraform output -raw static_site_url`
Snapshot Lambda: `terraform output -raw snapshot_lambda_function_name`
Snapshot key: `terraform output -raw snapshot_s3_key`
Alarm SNS topic: `terraform output -raw alarm_topic_arn`

## IAM least-privilege matrix

| Principal | Required permissions | Scoped resource(s) |
|-----------|----------------------|--------------------|
| GitHub deploy role | `lambda:UpdateFunctionCode`, `lambda:UpdateFunctionConfiguration`, `lambda:GetFunctionConfiguration` | `aws_lambda_function.snapshot.arn` |
| GitHub deploy role | `s3:ListBucket` | `aws_s3_bucket.static_site.arn` |
| GitHub deploy role | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` | `${aws_s3_bucket.static_site.arn}/*` |
| GitHub deploy role | `cloudfront:CreateInvalidation` | `aws_cloudfront_distribution.static_site.arn` |
| Snapshot Lambda execution role | `bedrock:InvokeModel` | model ID → `arn:aws:bedrock:REGION::foundation-model/<id>` **or** inference profile ARN |
| Snapshot Lambda execution role | `s3:PutObject` | `${aws_s3_bucket.static_site.arn}/${var.snapshot_s3_key}` |

The managed **GitHub deploy role** (when enabled) only targets the snapshot Lambda and static site resources used by `.github/workflows/deploy.yml`.

### Optional variables

- `static_site_bucket_name` - override the default `{project_name}-static-{account_id}` S3 bucket name (must be globally unique).
- `cloudfront_price_class` - default `PriceClass_100` (US/Europe).
- `cloudfront_cache_policy_id` - default is AWS managed **CachingOptimized** (avoids `cloudfront:ListCachePolicies` during plan).
- `lambda_memory_size` / `lambda_timeout_seconds` - tune Lambda cost/performance.
- `lambda_package_path` - zip used for first create (deploy workflow updates function code after that).
- `snapshot_schedule_enabled` - enable/disable scheduled snapshot Lambda.
- `snapshot_schedule_expression` - EventBridge **Scheduler** expression (default `cron(0 6 * * ? *)` = daily 06:00 in `snapshot_schedule_timezone`).
- `snapshot_schedule_timezone` - IANA zone for the schedule (default `Europe/London`; set empty string for UTC).
- `snapshot_s3_key` - S3 object key written by the snapshot Lambda (default `snapshot.json`).
- `snapshot_prompt` - agent prompt used for each scheduled snapshot generation.
- `alarms_enabled` - enable/disable CloudWatch alarms and SNS topic.
- `alarm_email_endpoints` - list of email addresses subscribed to alarms (requires confirmation).
- `alarm_duration_p95_threshold_ms` - threshold for p95 snapshot Lambda duration alarm.
- `alarm_min_invocations_period_seconds` - window to detect missing scheduled runs.
- `alarm_cloudfront_5xx_enabled` - enable/disable CloudFront 5xx alarm.
- `alarm_cloudfront_5xx_rate_threshold` - threshold for CloudFront 5xx error rate alarm.
- `github_repository` - e.g. `org/repo`; empty skips the OIDC deploy role.
- `github_deploy_branch` - branch name for OIDC `sub` (default `main`).

## Bedrock access

Ensure the Lambda execution role is allowed to invoke the configured Bedrock model and that the model is available in your chosen region.
