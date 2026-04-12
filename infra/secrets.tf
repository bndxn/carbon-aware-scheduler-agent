resource "aws_secretsmanager_secret" "anthropic" {
  name                    = "${var.project_name}/anthropic-api-key"
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "anthropic" {
  secret_id     = aws_secretsmanager_secret.anthropic.id
  secret_string = var.anthropic_api_key
}
