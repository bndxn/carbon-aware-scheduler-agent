data "aws_caller_identity" "current" {}

locals {
  static_site_bucket = coalesce(
    var.static_site_bucket_name,
    "${var.project_name}-static-${data.aws_caller_identity.current.account_id}"
  )
}

resource "aws_s3_bucket" "static_site" {
  bucket = local.static_site_bucket
}

resource "aws_s3_bucket_ownership_controls" "static_site" {
  bucket = aws_s3_bucket.static_site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "static_site" {
  name                              = "${var.project_name}-static-oac"
  description                       = "OAC for S3 static site (${var.project_name})"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "static_site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} static site"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  web_acl_id          = var.waf_enabled ? aws_wafv2_web_acl.static_site[0].arn : null

  origin {
    domain_name              = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id                = "S3-${local.static_site_bucket}"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_site.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-${local.static_site_bucket}"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = var.cloudfront_cache_policy_id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.static_site.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_wafv2_web_acl" "static_site" {
  count    = var.waf_enabled ? 1 : 0
  provider = aws.us_east_1

  name        = "${var.project_name}-static-web-acl"
  description = "Baseline WAF protections for static CloudFront distribution."
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      dynamic "none" {
        for_each = var.waf_common_rule_set_override_action == "none" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = var.waf_common_rule_set_override_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }
}

# Basic security headers for a public static site.
resource "aws_cloudfront_response_headers_policy" "static_site" {
  name = "${var.project_name}-static-headers"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      override                   = true
    }
  }
}

data "aws_iam_policy_document" "static_site_s3_cloudfront" {
  statement {
    sid    = "AllowCloudFrontRead"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static_site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.static_site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_site" {
  bucket = aws_s3_bucket.static_site.id
  policy = data.aws_iam_policy_document.static_site_s3_cloudfront.json

  depends_on = [
    aws_s3_bucket_public_access_block.static_site,
    aws_cloudfront_distribution.static_site,
  ]
}
