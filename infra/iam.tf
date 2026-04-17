data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

locals {
  # Bedrock supports invoking either a foundation model ID (mapped to a foundation-model ARN)
  # or an inference profile ARN (account-scoped). We allow whichever form `bedrock_model_id`
  # is set to, without granting broad Bedrock permissions.
  #
  # Examples:
  # - Model ID: eu.anthropic.claude-... -> arn:aws:bedrock:REGION::foundation-model/<id>
  # - Inference profile ARN: arn:aws:bedrock:REGION:ACCOUNT:inference-profile/<name>
  bedrock_invoke_resource = startswith(var.bedrock_model_id, "arn:") ? var.bedrock_model_id : "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"

  # When invoking via an inference profile ARN, Bedrock may evaluate authorization
  # against the underlying foundation model ARN (which can be in a different region).
  # To avoid brittle per-model/per-region mapping, allow InvokeModel on any
  # foundation model ARN in addition to the specific inference profile ARN.
  bedrock_invoke_resources = startswith(var.bedrock_model_id, "arn:") ? [var.bedrock_model_id, "arn:aws:bedrock:*::foundation-model/*"] : ["arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"]
}

resource "aws_iam_role" "lambda_execution" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_bedrock_invoke" {
  name = "invoke-bedrock-model"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
        ]
        Resource = local.bedrock_invoke_resources
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_snapshot_s3" {
  name = "write-static-snapshot"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.static_site.arn}/${var.snapshot_s3_key}"
      },
    ]
  })
}

resource "aws_iam_role" "snapshot_scheduler" {
  count              = var.snapshot_schedule_enabled ? 1 : 0
  name               = "${var.project_name}-snapshot-scheduler"
  assume_role_policy = data.aws_iam_policy_document.snapshot_scheduler_assume.json
}

data "aws_iam_policy_document" "snapshot_scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "snapshot_scheduler_invoke_lambda" {
  count = var.snapshot_schedule_enabled ? 1 : 0
  name  = "invoke-snapshot-lambda"
  role  = aws_iam_role.snapshot_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.snapshot.arn
      },
    ]
  })
}
