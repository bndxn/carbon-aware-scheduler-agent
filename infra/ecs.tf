resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project_name}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "main" {
  name = var.project_name
}

resource "aws_ecs_express_gateway_service" "api" {
  cluster                 = aws_ecs_cluster.main.name
  service_name            = local.service_name
  execution_role_arn      = aws_iam_role.task_execution.arn
  infrastructure_role_arn = aws_iam_role.express_infrastructure.arn
  health_check_path       = "/health"
  cpu                     = var.express_cpu
  memory                  = var.express_memory
  wait_for_steady_state   = false

  network_configuration {
    subnets         = local.subnet_ids
    security_groups = [data.aws_security_group.default.id]
  }

  primary_container {
    image          = local.container_image
    container_port = 8000

    aws_logs_configuration {
      log_group         = aws_cloudwatch_log_group.api.name
      log_stream_prefix = "api"
    }

    secret {
      name       = "ANTHROPIC_API_KEY"
      value_from = aws_secretsmanager_secret.anthropic.arn
    }
  }

  depends_on = [
    aws_secretsmanager_secret_version.anthropic,
  ]

  lifecycle {
    ignore_changes = [ingress_paths]
  }
}
