output "snapshot_lambda_function_name" {
  description = "Set GitHub repository variable SNAPSHOT_LAMBDA_FUNCTION_NAME to this value."
  value       = aws_lambda_function.snapshot.function_name
}

output "static_site_bucket_name" {
  description = "Set GitHub repository variable S3_BUCKET to this value (deploy workflow syncs site/ here)."
  value       = aws_s3_bucket.static_site.id
}

output "cloudfront_distribution_id" {
  description = "Set GitHub repository variable CLOUDFRONT_DISTRIBUTION_ID to this value."
  value       = aws_cloudfront_distribution.static_site.id
}

output "static_site_url" {
  description = "HTTPS URL for the static site (CloudFront)."
  value       = "https://${aws_cloudfront_distribution.static_site.domain_name}"
}

output "snapshot_schedule_expression" {
  description = "EventBridge Scheduler expression for snapshot refreshes."
  value       = var.snapshot_schedule_expression
}

output "snapshot_s3_key" {
  description = "S3 key written by the scheduled snapshot job."
  value       = var.snapshot_s3_key
}

output "github_actions_deploy_role_arn" {
  description = "When github_repository is set: set GitHub secret AWS_ROLE_ARN to this ARN."
  value       = local.github_actions_enabled ? aws_iam_role.github_actions_deploy[0].arn : null
}

output "alarm_topic_arn" {
  description = "SNS topic ARN used by CloudWatch alarms (null when alarms are disabled)."
  value       = var.alarms_enabled ? aws_sns_topic.alerts[0].arn : null
}
