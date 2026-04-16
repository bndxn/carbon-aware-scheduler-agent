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

resource "aws_cloudwatch_event_rule" "snapshot_schedule" {
  count               = var.snapshot_schedule_enabled ? 1 : 0
  name                = "${var.project_name}-snapshot-schedule"
  schedule_expression = var.snapshot_schedule_expression
  description         = "Runs Lambda snapshot job on a fixed schedule."
}

resource "aws_cloudwatch_event_target" "snapshot_lambda" {
  count = var.snapshot_schedule_enabled ? 1 : 0
  rule  = aws_cloudwatch_event_rule.snapshot_schedule[0].name
  arn   = aws_lambda_function.snapshot.arn
}

resource "aws_lambda_permission" "allow_eventbridge_snapshot" {
  count         = var.snapshot_schedule_enabled ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeSnapshotSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.snapshot_schedule[0].arn
}
