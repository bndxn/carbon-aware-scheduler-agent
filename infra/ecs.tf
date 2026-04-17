resource "aws_cloudwatch_log_group" "snapshot" {
  name              = "/aws/lambda/${local.snapshot_lambda_function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "snapshot" {
  function_name = local.snapshot_lambda_function_name
  role          = aws_iam_role.lambda_execution.arn
  runtime       = "python3.14"
  handler       = "carbon_intensity.web.snapshot_lambda_handler.handler"
  filename      = "${path.module}/${var.lambda_package_path}"

  source_code_hash = filebase64sha256("${path.module}/${var.lambda_package_path}")
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout_seconds

  environment {
    variables = {
      BEDROCK_MODEL_ID = var.bedrock_model_id
      SNAPSHOT_BUCKET  = aws_s3_bucket.static_site.id
      SNAPSHOT_KEY     = var.snapshot_s3_key
      SNAPSHOT_PROMPT  = var.snapshot_prompt
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.snapshot,
  ]
}

# EventBridge Scheduler (not CloudWatch Events rules) supports IANA time zones for cron().
resource "aws_scheduler_schedule" "snapshot" {
  count       = var.snapshot_schedule_enabled ? 1 : 0
  name        = "${var.project_name}-snapshot-schedule"
  description = "Invokes snapshot Lambda on a fixed schedule."

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.snapshot_schedule_expression
  schedule_expression_timezone = (
    var.snapshot_schedule_timezone != "" ? var.snapshot_schedule_timezone : null
  )

  target {
    arn      = aws_lambda_function.snapshot.arn
    role_arn = aws_iam_role.snapshot_scheduler[0].arn
  }
}

resource "aws_lambda_permission" "allow_scheduler_snapshot" {
  count         = var.snapshot_schedule_enabled ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.snapshot[0].arn
}
