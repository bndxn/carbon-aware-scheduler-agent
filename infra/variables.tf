variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "eu-west-2"
}

variable "project_name" {
  type        = string
  description = "Short name used for resource prefixes (letters, numbers, hyphens)."
  default     = "carbon-agent"
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key stored in Secrets Manager (use TF_VAR_anthropic_api_key or a gitignored terraform.tfvars file)."
  sensitive   = true
}

variable "lambda_memory_size" {
  type        = number
  description = "Lambda memory (MB) for the scheduled snapshot function."
  default     = 512
}

variable "lambda_timeout_seconds" {
  type        = number
  description = "Lambda timeout in seconds for the scheduled snapshot function."
  default     = 30
}

variable "lambda_package_path" {
  type        = string
  description = "Path to Lambda zip package used for initial function creation."
  default     = "artifacts/lambda.zip"
}

variable "snapshot_schedule_enabled" {
  type        = bool
  description = "Whether to run a scheduled Lambda snapshot job."
  default     = true
}

variable "snapshot_schedule_expression" {
  type        = string
  description = "EventBridge schedule expression for snapshot updates (e.g. rate(6 hours))."
  default     = "rate(6 hours)"
}

variable "snapshot_prompt" {
  type        = string
  description = "Prompt used by the scheduled Lambda job to generate snapshot content."
  default     = "Give a concise update on current and near-term GB grid carbon intensity and practical low-carbon timing advice."
}

variable "snapshot_s3_key" {
  type        = string
  description = "S3 object key for the generated snapshot output."
  default     = "snapshot.json"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention for Lambda logs."
  default     = 30
}

variable "secret_recovery_window_days" {
  type        = number
  description = "Secrets Manager recovery window when deleting the secret."
  default     = 7
}

variable "static_site_bucket_name" {
  type        = string
  description = "S3 bucket name for static site (default: {project_name}-static-{account_id}). Must be globally unique if set."
  default     = null
}

variable "cloudfront_price_class" {
  type        = string
  description = "CloudFront price class (e.g. PriceClass_100, PriceClass_200, PriceClass_All)."
  default     = "PriceClass_100"
}

variable "cloudfront_cache_policy_id" {
  type        = string
  description = "AWS managed cache policy ID (default: Managed-CachingOptimized; avoids cloudfront:ListCachePolicies)."
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

variable "github_repository" {
  type        = string
  description = "GitHub repo as owner/name for OIDC trust (e.g. myorg/carbon-aware-scheduler-agent). Leave empty to skip creating the GitHub Actions deploy IAM role."
  default     = ""
}

variable "github_deploy_branch" {
  type        = string
  description = "Branch allowed to assume the deploy role (token sub repo:...:ref:refs/heads/<this>)."
  default     = "main"
}
