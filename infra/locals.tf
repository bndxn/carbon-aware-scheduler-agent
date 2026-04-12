locals {
  # Distinct from any stale INACTIVE Express service name left in the account.
  service_name = "${var.project_name}-web"

  container_image = coalesce(
    var.api_image,
    "${aws_ecr_repository.api.repository_url}:latest"
  )
}
