# GitHub Actions OIDC deploy role: Lambda deploys, S3 sync, CloudFront invalidation.
# Requires IAM OIDC provider for https://token.actions.githubusercontent.com (once per account).

locals {
  github_actions_enabled = trimspace(var.github_repository) != ""
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.github_actions_enabled ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_oidc_assume" {
  count = local.github_actions_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_deploy_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  count              = local.github_actions_enabled ? 1 : 0
  name               = "${var.project_name}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume[0].json
}

data "aws_iam_policy_document" "github_actions_deploy" {
  count = local.github_actions_enabled ? 1 : 0

  statement {
    sid    = "LambdaUpdate"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:GetFunctionConfiguration",
    ]
    resources = [aws_lambda_function.snapshot.arn]
  }

  statement {
    sid    = "StaticSiteS3"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.static_site.arn]
  }

  statement {
    sid    = "StaticSiteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.static_site.arn}/*"]
  }

  statement {
    sid       = "CloudFrontInvalidate"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.static_site.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  count  = local.github_actions_enabled ? 1 : 0
  name   = "deploy-lambdas-s3-cloudfront"
  role   = aws_iam_role.github_actions_deploy[0].id
  policy = data.aws_iam_policy_document.github_actions_deploy[0].json
}
