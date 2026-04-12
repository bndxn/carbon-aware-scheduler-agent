output "ecr_repository_name" {
  description = "Set GitHub repository variable ECR_REPOSITORY to this value."
  value       = aws_ecr_repository.api.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecs_cluster_name" {
  description = "Set GitHub repository variable ECS_CLUSTER to this value."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Set GitHub repository variable ECS_SERVICE to this value."
  value       = aws_ecs_express_gateway_service.api.service_name
}

output "express_service_arn" {
  value = aws_ecs_express_gateway_service.api.service_arn
}

output "api_ingress_paths" {
  description = "Public URL(s) and paths for the Express service (ALB)."
  value       = aws_ecs_express_gateway_service.api.ingress_paths
}

output "anthropic_secret_arn" {
  description = "Secrets Manager ARN for the API key (sensitive)."
  value       = aws_secretsmanager_secret.anthropic.arn
  sensitive   = true
}
