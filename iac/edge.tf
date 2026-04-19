module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.3"

  domain_name               = var.domain_name
  zone_id                   = var.route53_zone_id
  validation_method         = "DNS"
  subject_alternative_names = ["*.${var.domain_name}"]
  wait_for_validation       = true
  tags                      = local.common_tags
}

resource "aws_wafv2_web_acl" "cloudfront" {
  name        = "${local.prefix}-waf"
  description = "WAF for ${local.prefix} CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      AWSManagedRulesCommonRuleSet          = { priority = 1, metric = "common-rules" }
      AWSManagedRulesKnownBadInputsRuleSet  = { priority = 2, metric = "bad-inputs" }
      AWSManagedRulesSQLiRuleSet            = { priority = 3, metric = "sqli" }
      AWSManagedRulesAmazonIpReputationList = { priority = 4, metric = "ip-reputation" }
    }
    content {
      name     = rule.key
      priority = rule.value.priority
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.prefix}-${rule.value.metric}"
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "RateLimitRule"
    priority = 5
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 500
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

## WAF logging to CloudWatch
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.prefix}"
  retention_in_days = 90
  tags              = local.common_tags
}

resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${local.prefix}-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "static" {
  name        = "${local.prefix}-static"
  default_ttl = 3600
  min_ttl     = 0
  max_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_cache_policy" "dynamic" {
  name        = "${local.prefix}-dynamic"
  default_ttl = 0
  min_ttl     = 0
  max_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config { cookie_behavior = "all" }
    headers_config {
      header_behavior = "whitelist"
      headers { items = ["Authorization", "Origin", "Accept", "Content-Type"] }
    }
    query_strings_config { query_string_behavior = "all" }
  }
}

## Signed asset traffic 
resource "aws_cloudfront_cache_policy" "signed_assets" {
  name        = "${local.prefix}-signed-assets"
  default_ttl = 3600
  min_ttl     = 0
  max_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "all" }
  }
}

resource "aws_cloudfront_origin_request_policy" "api" {
  name = "${local.prefix}-api-request"

  cookies_config { cookie_behavior = "all" }
  query_strings_config { query_string_behavior = "all" }
  headers_config {
    header_behavior = "allViewerAndWhitelistCloudFront"
    headers { items = ["CloudFront-Viewer-Country"] }
  }
}

resource "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "${local.prefix}-all-viewer"

  cookies_config { cookie_behavior = "all" }
  query_strings_config { query_string_behavior = "all" }
  headers_config { header_behavior = "allViewer" }
}

resource "aws_cloudfront_public_key" "main" {
  count       = var.enable_signed_urls && var.cloudfront_public_key_pem != "" ? 1 : 0
  name        = "${local.prefix}-signing-key"
  encoded_key = var.cloudfront_public_key_pem
  comment     = "Public key for CloudFront signed URLs"
}

resource "aws_cloudfront_key_group" "main" {
  count   = var.enable_signed_urls && var.cloudfront_public_key_pem != "" ? 1 : 0
  name    = "${local.prefix}-key-group"
  comment = "Key group for signed URLs"
  items   = [aws_cloudfront_public_key.main[0].id]
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  price_class         = "PriceClass_100"
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn
  wait_for_deployment = false

  origin {
    domain_name              = module.s3.bucket_regional_domain_names["frontend"]
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    domain_name = replace(aws_apigatewayv2_api.main.api_endpoint, "https://", "")
    origin_id   = "api-gateway"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name = module.ecs.nlb_dns_name
    origin_id   = "nlb-sse"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name              = module.s3.bucket_regional_domain_names["telemetry"]
    origin_id                = "s3-telemetry"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    domain_name              = module.s3.bucket_regional_domain_names["dashcam"]
    origin_id                = "s3-dashcam"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = aws_cloudfront_cache_policy.static.id
  }

  ordered_cache_behavior {
    path_pattern             = "/api/telemetry/stream"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "nlb-sse"
    viewer_protocol_policy   = "https-only"
    cache_policy_id          = aws_cloudfront_cache_policy.dynamic.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer.id
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "api-gateway"
    viewer_protocol_policy   = "https-only"
    cache_policy_id          = aws_cloudfront_cache_policy.dynamic.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  ordered_cache_behavior {
    path_pattern             = "/auth/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "api-gateway"
    viewer_protocol_policy   = "https-only"
    cache_policy_id          = aws_cloudfront_cache_policy.dynamic.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer.id
  }

  ordered_cache_behavior {
    path_pattern             = "/oem/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "api-gateway"
    viewer_protocol_policy   = "https-only"
    cache_policy_id          = aws_cloudfront_cache_policy.dynamic.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  ordered_cache_behavior {
    path_pattern           = "/trips/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-telemetry"
    viewer_protocol_policy = "https-only"
    trusted_key_groups     = var.enable_signed_urls && var.cloudfront_public_key_pem != "" ? [aws_cloudfront_key_group.main[0].id] : null
    cache_policy_id        = aws_cloudfront_cache_policy.signed_assets.id
  }

  ordered_cache_behavior {
    path_pattern           = "/dashcam/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-dashcam"
    viewer_protocol_policy = "https-only"
    trusted_key_groups     = var.enable_signed_urls && var.cloudfront_public_key_pem != "" ? [aws_cloudfront_key_group.main[0].id] : null
    cache_policy_id        = aws_cloudfront_cache_policy.signed_assets.id
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "MX"]
    }
  }

  viewer_certificate {
    acm_certificate_arn      = module.acm.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = local.common_tags
}

locals {
  cf_oac_buckets = ["frontend", "telemetry", "dashcam"]
}

resource "aws_s3_bucket_policy" "cf_oac" {
  for_each = toset(local.cf_oac_buckets)
  bucket   = module.s3.bucket_ids[each.key]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${module.s3.bucket_arns[each.key]}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.main.arn }
      }
    }]
  })
}

resource "aws_route53_record" "cloudfront_a" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_aaaa" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "sse_nlb" {
  zone_id = var.route53_zone_id
  name    = "sse.${var.domain_name}"
  type    = "A"
  alias {
    name                   = module.ecs.nlb_dns_name
    zone_id                = module.ecs.nlb_zone_id
    evaluate_target_health = true
  }
}

# Route 53 health checks 
resource "aws_route53_health_check" "api_health" {
  fqdn              = var.domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/api/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.common_tags, { Name = "${local.prefix}-api-health" })
}

resource "aws_cloudwatch_metric_alarm" "api_health_check" {
  alarm_name          = "${local.prefix}-regional-health-check-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 10
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 30
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "API health check failed for 5 minutes - evaluate cross-region failover"
  dimensions          = { HealthCheckId = aws_route53_health_check.api_health.id }
  alarm_actions       = [module.sqs_sns.sns_topic_arns["security_alerts"]]
  treat_missing_data  = "breaching"
  tags                = merge(local.common_tags, { Severity = "Critical" })
}
