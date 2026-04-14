# Incremental AWS demo build (reference)

Snapshot of the incremental build plan for the employer-facing static site, Lambda API, IaC, and GitHub deploy pipeline. Saved under `planning/` for long-term reference.

---

# Incremental build: employer demo on AWS (static site + API via Lambda)

## Context from this repo

- The product today is a **Python CLI** ([`app.py`](../app.py)) calling [`run_agent`](../src/carbon_intensity/agent.py); there is **no HTTP layer**, **no Dockerfile**, and **no AWS** code yet.
- CI already runs on **`main` and PRs** via [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) (uv, pre-commit, pytest).

**Architecture choices (updated):**

- **Employer-facing UI**: a **static page** (plain HTML/CSS, optionally a small set of assets)—**no chat UI** and no JavaScript-heavy SPA requirement.
- **API hosting**: **AWS Lambda + Function URL** for a low-ops, low-baseline-cost HTTP API.
- **Scheduled refresh**: **EventBridge -> Lambda** every 6 hours writes `snapshot.json` to the static S3 bucket so page views do not drive model/API cost.

### Static pages, crawlers, and “refresh every 6 hours”

- **Reloading the static page does not reinvoke your API** by default. S3+CloudFront serves **HTML/CSS/assets**; each reload is just another `GET` for those objects. **No Anthropic call** happens unless you add **client-side JavaScript** that calls the API on `load`—avoid that on the public marketing page.
- **Bots crawling the site** hit CloudFront/S3 the same way: static files only, **not** your container, unless they discover and hammer a **separate public API URL** you linked (e.g. `/api/chat`). If you expose an interactive chat API on the internet, protect it (auth, WAF, rate limits, or keep it off the public internet) rather than relying on “no one will find it.”
- **Updating demo content on a schedule (e.g. every 6 hours)** should be **decoupled from page views**: run a **scheduled job** (EventBridge `rate(6 hours)`) that invokes a **short-lived Lambda** which calls your existing carbon/API logic (or a single `run_agent` run) and **writes output to S3** next to the static site (for example `snapshot.json`). The static `index.html` can reference `./snapshot.json` with **no JS polling**; browsers and bots only see new text after the next scheduled upload + cache behavior you define.

---

## Phase A — Application: API and static site (no AWS yet)

**1. Add a small HTTP API (FastAPI or similar)**

- New module (e.g. `src/carbon_intensity/web/` or top-level `api/`) exposing:
  - `GET /health` (or `/healthz`) for load balancer checks
  - `POST /api/chat` (or similar) with JSON body `{ "message": "..." }` returning `{ "reply": "..." }` by calling existing `run_agent` (for API clients, scripts, or future use—not required to be called from the static page)
- Read `ANTHROPIC_API_KEY` (and optional `ANTHROPIC_MODEL`) from the environment only; do not bake secrets into images.
- **CORS**: still useful if you later add a form or tools hitting the API; if the static page is purely informational, CORS can stay permissive for your CloudFront origin or be tightened later.

**2. Add automated tests for the API**

- Use Starlette/FastAPI `TestClient` in [`tests/`](../tests/) for `/health` and a mocked `run_agent` (or dependency override) so CI stays deterministic and fast.

**3. Add a static demo page**

- New directory (e.g. `site/` or `public/`) with **`index.html`** plus optional CSS/images: project summary, what the agent does, links to this repo. **Do not** add scripts that call the LLM API on every page load; if you show “live” numbers, load them from a **precomputed** `snapshot.json` (or static HTML) produced by the **scheduled** pipeline below—not from the ECS API on each visit.
- **No chat UI**—no embedded chat widget, no Vite/React requirement. If you prefer zero Node in the repo, ship hand-authored HTML/CSS only.

**4. Deploy artifacts**

- Static: upload the folder as-is to S3 (no `npm run build` unless you voluntarily add a static site generator later).
- API: Lambda zip package deployed to **Lambda Function URL**.

---

## Phase B — Container for the API

**5. Dockerfile for the API**

- Install with **uv** (respecting [`uv.lock`](../uv.lock)), copy `src/` + [`pyproject.toml`](../pyproject.toml), run **uvicorn** on `0.0.0.0:8000`.
- Add `.dockerignore` to keep images small.

**6. Local smoke: `docker run`**

- Verify `/health` and the agent endpoint with a dev key (not committed).

---

## Phase C — IaC foundation (pick one tool and stay consistent)

**7. Create an `infra/` tree** (Terraform example): `versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, optional `modules/` for `ecs_express_api`, `static_site`, `github_oidc`.

- **ECS Express Mode** is supported via AWS APIs and IaC (e.g. CloudFormation/CDK/Terraform resources for Express services—align module names with the provider resources available for your chosen tool version). See [Express Mode service resources](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html).

**8. Remote state (recommended)**

- S3 backend for Terraform state + DynamoDB table for locking (bootstrap documented in-repo only if you add a short note you asked for).

---

## Phase D — AWS: API (Lambda + Secrets Manager)

**9. Lambda API function**

- IaC defines Lambda runtime/handler/memory/timeout and publishes a public Function URL for `/health` + `/api/chat`.

**10. Lambda IAM execution role**

- Role includes CloudWatch logs + read access to the Anthropic secret.

**11. Secrets**

- Store `ANTHROPIC_API_KEY` in **Secrets Manager**; expose ARN to Lambda env and resolve secret value at runtime.

**12. Outputs**

- Export API Function URL and Lambda names for CI/CD variables.

---

## Phase E — AWS: Static site (S3 + CloudFront)

**13. Private S3 bucket for static assets**

- Bucket policy allowing **CloudFront OAC** only.

**14. CloudFront distribution**

- Origin = S3; **default root object** `index.html`. Skip SPA-style error routing unless you add client-side routes later.

**15. Cache invalidation**

- On deploy, invalidate `/*` or specific paths. For **scheduled snapshot** updates, invalidate only `snapshot.json` (or similar) to limit churn and cost.

---

## Phase E2 — Scheduled refresh (implemented in PR5)

**15b. EventBridge schedule**

- Rule targeting the **snapshot Lambda**: run the data/agent job once and write output to the same static bucket (`snapshot.json`).

**15c. IAM**

- Snapshot Lambda execution role allows `s3:PutObject` on the site bucket prefix.

**15d. Cost and crawler safety**

- Crawler traffic stays on **CloudFront + S3**; **LLM/API work** scales with **schedule** (e.g. 4×/day), not with page views.

---

## Phase F — Continuous deployment from GitHub (`main`)

**16. GitHub OIDC → AWS IAM role**

- Trust policy scoped to this repo and branch `main`.
- Permissions: Lambda code/config update, S3 sync, `cloudfront:CreateInvalidation`.

**17. New workflow: deploy on `main` only**

- **Trigger**: `on: push: branches: [main]`.
- **Jobs** (`needs:`): quality gate → build Lambda package → update API/snapshot Lambda code → **sync static folder to S3** → **invalidate CloudFront**.
- No `VITE_*` variables unless you add a build step; for plain static files, sync is enough.

**18. Keep PR CI unchanged**

- [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) remains for PRs; deploy workflow is **main-only**.

---

## Phase G — Hardening (optional)

**19. HTTPS and custom domain**

- ACM + Route 53 for CloudFront and/or the Express URL, per AWS guidance.

**20. Abuse controls**

- WAF, rate limits, optional protection on `/api/chat`.

**21. Observability**

- CloudWatch alarms on 5xx and task health (Express integrates with monitoring per AWS docs).

---

## IAM roles and permissions (what needs what)

Use **least privilege** in production: replace `Resource: "*"` with your ARNs (account id, region, cluster name, secret name, bucket name, distribution id).

### 1. GitHub Actions — OIDC deploy role (human: `repo:org/name:ref:refs/heads/main`)

**Trust policy**: `sts:AssumeRoleWithWebIdentity` for `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`, condition on `sub` = allowed repo ref(s).

**Typical permissions** (combine what your workflow actually does):

| Area | Actions (representative) | Notes |
|------|-------------------------|--------|
| **ECR — push image** | `ecr:GetAuthorizationToken` (often on `*`); on the **repository ARN**: `ecr:BatchCheckLayerAvailability`, `ecr:CompleteLayerUpload`, `ecr:InitiateLayerUpload`, `ecr:PutImage`, `ecr:UploadLayerPart`, `ecr:BatchGetImage` | GetAuthorizationToken is account-wide in practice. |
| **ECS — new deployment** | `ecs:DescribeServices`, `ecs:UpdateService`, optionally `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition` if the workflow registers tasks | Scope to cluster ARN + service ARN if possible. Express Mode still uses standard ECS APIs for deploy. |
| **S3 — static site** | `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on the **site bucket** prefix | For `aws s3 sync`. |
| **CloudFront** | `cloudfront:CreateInvalidation` on the **distribution ID** | Invalidation is per-distribution. |
| **IaC (Terraform in CI)** | Broad: often `iam:*`, `ecs:*`, `elasticloadbalancing:*`, `ec2:Describe*`, `ec2:CreateSecurityGroup`, … on scoped resources, or a **Terraform deploy role** with policies generated by IAM Policy Simulator / `terraform plan` review | If Terraform runs in GitHub, this role needs whatever your modules create (VPC pieces, ALB, ECS, ECR, S3, CloudFront, IAM roles for tasks). Alternatively run `terraform apply` from a trusted machine with a different role and keep GitHub image-only + `UpdateService`. |

**Why the policy picker shows nothing for `GetAuthorizationToken`:** The **Attach policies** search matches **policy names** (e.g. `AmazonEC2ContainerRegistryPowerUser`), not **IAM action** strings like `ecr:GetAuthorizationToken`. Those actions appear **inside** a policy’s JSON.

**What to attach or search for (GitHub deploy role):**

| Need | What to do in IAM |
|------|-------------------|
| **ECR** — `docker push` / `GetAuthorizationToken` and layer uploads | Attach AWS managed **`AmazonEC2ContainerRegistryPowerUser`** (search **ECR** or **ContainerRegistry**). It includes `ecr:GetAuthorizationToken` and push-related actions. |
| **ECS** — redeploy (`UpdateService`, describe) | No small managed “deploy-only” policy. Prefer an **inline policy** with `ecs:DescribeServices`, `ecs:UpdateService` (and task-definition APIs if your workflow needs them) scoped to your **cluster and service ARNs**. Sandbox only: **`AmazonECS_FullAccess`** is broad but easy. |
| **S3** — `aws s3 sync` | **Inline policy**: `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on your **bucket** ARN and `arn:aws:s3:::name/*`. |
| **CloudFront** — invalidation | **Inline policy**: `cloudfront:CreateInvalidation` on `arn:aws:cloudfront::ACCOUNT:distribution/DIST_ID`. |

**Confirm a managed policy contains an action:** IAM → **Policies** → search by **policy name** → open → **JSON** → search for `GetAuthorizationToken`.

**Least privilege:** Role → **Add permissions** → **Create inline policy** → **JSON** — paste `Statement`s using the **Action** names from the permission table above and **Resource** ARNs.

**Avoid** putting long-lived AWS keys in GitHub; OIDC only.

### 2. Lambda execution role

- Role used by both API and snapshot Lambda.
- Needs CloudWatch logs permissions + `secretsmanager:GetSecretValue` for the Anthropic secret.
- Snapshot handler additionally needs `s3:PutObject` to write `snapshot.json`.

### 3. EventBridge -> Lambda schedule (Phase E2)

- EventBridge schedule targets the snapshot Lambda directly.
- Add `aws_lambda_permission` allowing `events.amazonaws.com` to invoke the function from the schedule rule ARN.

### 6. Terraform / bootstrap (one-time or CI)

- **S3 + DynamoDB** for remote state: role used for `terraform init/apply` needs `s3:*` on the state bucket and `dynamodb:GetItem`, `PutItem`, `DeleteItem` on the lock table.
- **Creating IAM roles** inside Terraform: the deploy principal needs `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole` for roles Terraform creates (narrow `PassRole` to paths or role name prefixes).

### Quick mental model

- **GitHub OIDC role** = “CI can update Lambda code, sync S3, invalidate CloudFront, and optionally apply IaC.”
- **Lambda execution role** = “Lambda writes logs, reads Secrets Manager, and (for snapshot) writes to S3.”
- **EventBridge rule + Lambda permission** = “Scheduler can invoke snapshot Lambda on cadence.”

### How to create these in IAM (console-oriented)

**A. One-time: GitHub as an identity provider (OIDC)**

1. IAM → **Identity providers** → **Add provider** → **OpenID Connect**.
2. **Provider URL**: `https://token.actions.githubusercontent.com`
3. **Audience**: `sts.amazonaws.com` (AWS documents this for GitHub Actions).
4. Save. You only need this **once per account** (not per repo).

**B. IAM role for GitHub Actions (deploy role)**

**Preferred: start from Custom trust policy** (so you can pin `repo:…` and branch in one JSON blob):

1. IAM → **Roles** → **Create role**.
2. On **Step 1 — Select trusted entity**, look for **Custom trust policy** as a **trusted entity type** alongside options like *AWS account*, *AWS service*, *Web identity*, etc. Choose **Custom trust policy**, then paste the JSON block below into the editor.
3. If you **do not** see **Custom trust policy** on that first screen (UI varies by account/console version): use **Web identity** → provider `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`, pick repo/org in the form **only to get past the wizard**, **finish creating the role**, then open the new role → **Trust relationships** tab → **Edit trust policy** and **replace** the JSON with the block below (this is the usual workaround).

**Custom trust policy JSON** (replace `ACCOUNT_ID`, `OWNER` = GitHub **username** or org, `REPO`; optional `sub` pattern restricts who can assume the role):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

4. **Attach policies**: start from **none**, then add **customer managed** or **inline** policies that match the table in §1 above (ECR, ECS, S3, CloudFront). For a first pass in a sandbox, some teams attach broader policies then **tighten ARNs** using Access Advisor / CloudTrail.
5. Name the role (e.g. `github-deploy-carbon-demo`) and copy the **role ARN** into GitHub Actions: `aws-actions/configure-aws-credentials` with `role-to-assume: <ARN>`.

**C. ECS task execution role**

1. IAM → **Roles** → **Create role** → trusted entity **AWS service** → **Elastic Container Service** → **Elastic Container Service Task**.
2. Attach **`AmazonECSTaskExecutionRolePolicy`**.
3. Add **inline policy** for `secretsmanager:GetSecretValue` (and KMS decrypt if needed) on your secret ARN.
4. Use this role ARN in the task definition as **Task execution role**.

**D. ECS task role (application)**

1. IAM → **Roles** → **Create role** → **Elastic Container Service** → **Elastic Container Service Task**.
2. Start with **no managed policies** if the app only calls the internet; attach **inline** `s3:PutObject` etc. for the snapshot worker if needed.
3. Reference this as **Task role** in the task definition.

**E. ECS Express infrastructure role**

- Create per **current AWS documentation** for Express Mode (trust + permissions are feature-specific). Often done inside **IaC** or the ECS console wizard when you create the Express service so you do not hand-author unknown actions.

**F. EventBridge → ECS (scheduled task) role**

- EventBridge will prompt for or create a role that can **run** your task; ensure that role has **`iam:PassRole`** for the execution and task role ARNs and **`ecs:RunTask`** on your task definition. The EventBridge console can create a starter role you then refine.

**G. Terraform in CI**

- Either grant the **same GitHub OIDC role** broad enough rights to create resources (hard to least-privilege upfront), or use a **separate** admin/bootstrap role on your laptop for `terraform apply` and keep GitHub to **image + deploy only** with a smaller policy.

---

## Dependency sketch

```mermaid
flowchart LR
  subgraph github [GitHub]
    mainPush[push_to_main]
    ci[ci_checks]
    deploy[deploy_workflow]
  end
  subgraph aws [AWS]
    ecr[ECR]
    ecsExpress[ECS_Express_Mode]
    alb[ALB_managed]
    s3[S3]
    cf[CloudFront]
    sm[Secrets_Manager]
  end
  users[Employers_browser]
  mainPush --> ci
  mainPush --> deploy
  deploy --> ecr
  deploy --> ecsExpress
  ecr --> ecsExpress
  ecsExpress --> alb
  sm --> ecsExpress
  deploy --> s3
  deploy --> cf
  s3 --> cf
  users --> cf
  cf --> users
  users --> alb
  alb --> ecsExpress
```

---

## Suggested PR sequence

| Step | Deliverable |
|------|-------------|
| PR1 | FastAPI + tests + env notes |
| PR2 | Static `site/` (HTML/CSS) + short dev notes |
| PR3 | Dockerfile + `.dockerignore` |
| PR4 | IaC foundation + static S3/CloudFront + initial AWS wiring |
| PR5 | **Lambda API + scheduled snapshot Lambda + EventBridge + deploy workflow updates** |
| PR6 | polish: custom domain, WAF, alarms, stricter IAM |
| PR7+ | UX/content refresh and observability improvements |

This order supports **local demo** after PR2–3, **API on AWS** after PR5, and **crawler-safe scheduled refresh** by default with EventBridge -> Lambda.
