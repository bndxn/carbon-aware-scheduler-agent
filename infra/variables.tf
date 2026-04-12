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

variable "ecr_repository_name" {
  type        = string
  description = "ECR repository name (set GitHub var ECR_REPOSITORY to this value)."
  default     = "carbon-agent-api"
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key stored in Secrets Manager (use TF_VAR_anthropic_api_key or a gitignored terraform.tfvars file)."
  sensitive   = true
}

variable "api_image" {
  type        = string
  description = "Override container image (default: ECR repo :latest). Set after first docker push if initial apply fails."
  default     = null
}

variable "express_cpu" {
  type        = string
  description = "Fargate CPU units (Express accepts power-of-two 256–4096)."
  default     = "512"
}

variable "express_memory" {
  type        = string
  description = "Fargate memory in MiB (512–8192 per AWS Express constraints)."
  default     = "1024"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention for the API container."
  default     = 30
}

variable "secret_recovery_window_days" {
  type        = number
  description = "Secrets Manager recovery window when deleting the secret."
  default     = 7
}
