locals {
  alarms_enabled_with_schedule = var.alarms_enabled && var.snapshot_schedule_enabled
}

resource "aws_sns_topic" "alerts" {
  count = var.alarms_enabled ? 1 : 0
  name  = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.alarms_enabled ? toset(var.alarm_email_endpoints) : toset([])

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "snapshot_lambda_errors" {
  count               = var.alarms_enabled ? 1 : 0
  alarm_name          = "${var.project_name}-snapshot-lambda-errors"
  alarm_description   = "Snapshot Lambda reported one or more errors."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.snapshot.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "snapshot_lambda_throttles" {
  count               = var.alarms_enabled ? 1 : 0
  alarm_name          = "${var.project_name}-snapshot-lambda-throttles"
  alarm_description   = "Snapshot Lambda was throttled."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.snapshot.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "snapshot_lambda_duration_p95" {
  count               = var.alarms_enabled ? 1 : 0
  alarm_name          = "${var.project_name}-snapshot-lambda-duration-p95"
  alarm_description   = "Snapshot Lambda p95 duration exceeded threshold."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = var.alarm_duration_p95_threshold_ms
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.snapshot.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "snapshot_schedule_failed_invocations" {
  count               = local.alarms_enabled_with_schedule ? 1 : 0
  alarm_name          = "${var.project_name}-snapshot-schedule-failed-invocations"
  alarm_description   = "EventBridge schedule failed to invoke snapshot Lambda."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = 300
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    RuleName = aws_cloudwatch_event_rule.snapshot_schedule[0].name
  }
}

resource "aws_cloudwatch_metric_alarm" "snapshot_lambda_missing_runs" {
  count               = local.alarms_enabled_with_schedule ? 1 : 0
  alarm_name          = "${var.project_name}-snapshot-missing-runs"
  alarm_description   = "Snapshot Lambda was not invoked during expected schedule window."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = 1
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = var.alarm_min_invocations_period_seconds
  statistic           = "Sum"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.snapshot.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_rate" {
  count               = var.alarms_enabled && var.alarm_cloudfront_5xx_enabled ? 1 : 0
  alarm_name          = "${var.project_name}-cloudfront-5xx-rate"
  alarm_description   = "CloudFront 5xx error rate exceeded threshold."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = var.alarm_cloudfront_5xx_rate_threshold
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.static_site.id
    Region         = "Global"
  }
}
