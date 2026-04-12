# Terraform: ECR + ECS Express Mode + Secrets Manager (PR4)

Creates:

- **ECR** repository for the API image
- **IAM**: task execution role (ECR pull, logs, read Anthropic secret) and **Express infrastructure** role (AWS-managed policy for Express)
- **Secrets Manager** secret + version for `ANTHROPIC_API_KEY`
- **ECS cluster**, **CloudWatch** log group, **`aws_ecs_express_gateway_service`** (Express Mode) on **Fargate** with health check `GET /health` and container port **8000**

The Express **service name** is `${project_name}-web` (default **`carbon-agent-web`**) so it does not collide with a stale **INACTIVE** Express service name left in the account after a failed apply.

Express logging requires **`log_stream_prefix`** on the container `aws_logs_configuration` block (AWS API validation). The default VPC **default** security group is attached explicitly so the Terraform provider does not hit a known `security_groups` null/empty drift issue on create.

Requires **Terraform >= 1.5** and **hashicorp/aws >= 6.23** (Express Gateway resource).

## Prerequisites

- AWS credentials with permission to create these resources (often `AdministratorAccess` while iterating; tighten later).
- Default VPC with **at least two subnets** in the chosen region (true for typical accounts).

## Configure

1. Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored) **or** export:

   ```bash
   export TF_VAR_anthropic_api_key="your-key"
   ```

2. Optional: adjust `aws_region`, `project_name`, `ecr_repository_name` in `terraform.tfvars`.

## Apply

```bash
cd infra
terraform init
terraform plan
terraform apply
```

### Bootstrap order (if Express fails on first apply)

Express needs an image in ECR. If the first apply errors because **no image** exists yet:

1. Complete any partial apply so **ECR** and **roles** exist, or run `terraform apply` until ECR is created.
2. From the repo root, build and push (after `aws ecr get-login-password` / `docker login`):

   ```bash
   URL=$(terraform -chdir=infra output -raw ecr_repository_url)
   docker build -t "$URL:latest" .
   docker push "$URL:latest"
   ```

3. Run `terraform apply` again (or let GitHub Actions push on `main` once `ECR_REPOSITORY` is set).

## Outputs → GitHub Actions

After apply, set **repository variables** (Settings → Secrets and variables → Actions → Variables):

| Variable | Source |
|----------|--------|
| `AWS_REGION` | Same as `aws_region` (e.g. `eu-west-2`) |
| `ECR_REPOSITORY` | `terraform output -raw ecr_repository_name` |
| `ECS_CLUSTER` | `terraform output -raw ecs_cluster_name` |
| `ECS_SERVICE` | `terraform output -raw ecs_service_name` |

Keep **`AWS_ROLE_ARN`** as a **secret** for OIDC (already configured).

Public API URL(s): `terraform output api_ingress_paths`

## Rotate the API key

Update the secret value in Secrets Manager (console or CLI), then force a new ECS deployment (e.g. push a new image or re-run the deploy workflow).
