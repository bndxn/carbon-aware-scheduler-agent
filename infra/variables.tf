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

variable "bedrock_model_id" {
  type        = string
  description = "Bedrock invoke identifier used by the snapshot Lambda. Set either a model ID (e.g. eu.anthropic.claude-...) or an inference profile ARN (arn:aws:bedrock:REGION:ACCOUNT:inference-profile/...)."
  default     = "eu.anthropic.claude-haiku-4-5-20251001-v1:0"
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
  description = "EventBridge Scheduler expression. Default: daily at 06:00 local (see snapshot_schedule_timezone)."
  default     = "cron(0 6 * * ? *)"
}

variable "snapshot_schedule_timezone" {
  type        = string
  description = "IANA timezone for evaluating the schedule (default Europe/London). Use \"\" for UTC."
  default     = "Europe/London"
}

variable "snapshot_prompt" {
  type        = string
  description = "Prompt used by the scheduled Lambda job to generate snapshot content."
  default     = <<-EOT
    Find the best day and approximate time window in the next few days to start a washing machine in Great Britain. Optimise for (1) lower grid carbon intensity during the wash and (2) clothes drying afterward: I can dry indoors or outside but prefer line drying outside, which needs dry weather and ideally mild or warm conditions. If I did not name a place, use London, UK as the default for weather_wind_forecast. Reply in Markdown with one primary recommendation, one backup, and short reasoning.
  EOT
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

variable "waf_enabled" {
  type        = bool
  description = "Enable baseline WAF protections for CloudFront."
  default     = true
}

variable "waf_common_rule_set_override_action" {
  type        = string
  description = "Rule group override action for AWSManagedRulesCommonRuleSet: none (enforce) or count (monitor-only)."
  default     = "none"

  validation {
    condition     = contains(["none", "count"], var.waf_common_rule_set_override_action)
    error_message = "waf_common_rule_set_override_action must be one of: none, count."
  }
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

variable "alarms_enabled" {
  type        = bool
  description = "Enable CloudWatch alarms and SNS notifications for snapshot reliability."
  default     = true
}

variable "alarm_email_endpoints" {
  type        = list(string)
  description = "Email endpoints subscribed to alarm SNS topic. Recipients must confirm subscriptions."
  default     = []
}

variable "alarm_duration_p95_threshold_ms" {
  type        = number
  description = "Alarm threshold for p95 Lambda duration in milliseconds."
  default     = 20000
}

variable "alarm_min_invocations_period_seconds" {
  type        = number
  description = "CloudWatch period (seconds) for missing-run alarm; should cover at least one schedule interval (86400 for daily)."
  default     = 86400
}

variable "alarm_cloudfront_5xx_rate_threshold" {
  type        = number
  description = "Threshold for CloudFront 5xx error rate alarm (percentage)."
  default     = 1
}

variable "alarm_cloudfront_5xx_enabled" {
  type        = bool
  description = "Enable CloudFront 5xx error rate alarm."
  default     = true
}
