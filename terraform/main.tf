data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# API tier: HTTP API -> Lambda -> DynamoDB
# ---------------------------------------------------------------------------

module "api" {
  source = "../modules/serverless_api"

  name_prefix                 = local.name_prefix
  source_dir                  = local.api_source_dir
  lambda_memory_mb            = var.lambda_memory_mb
  lambda_reserved_concurrency = var.lambda_reserved_concurrency
  log_retention_days          = var.log_retention_days

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Edge tier: S3 origin + CloudFront, with /api/* routed to the HTTP API so the
# browser only ever talks to one origin.
# ---------------------------------------------------------------------------

module "site" {
  source = "../modules/static_site"

  name_prefix            = local.name_prefix
  bucket_suffix          = data.aws_caller_identity.current.account_id
  content_dir            = local.frontend_source_dir
  manage_site_content    = var.manage_site_content
  api_origin_domain_name = module.api.api_origin_domain_name
  price_class            = var.cloudfront_price_class

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Observability: alarms, dashboard, notification channel
# ---------------------------------------------------------------------------

module "observability" {
  source = "../modules/observability"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix     = local.name_prefix
  aws_region      = var.aws_region
  alert_email     = var.alert_email
  function_name   = module.api.function_name
  log_group_name  = module.api.log_group_name
  api_id          = module.api.api_id
  table_name      = module.api.table_name
  distribution_id = module.site.distribution_id

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Cost guardrails: monthly budget and anomaly detection (us-east-1 only)
# ---------------------------------------------------------------------------

module "cost_guardrails" {
  source = "../modules/cost_guardrails"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix              = local.name_prefix
  alert_email              = var.alert_email
  monthly_budget_usd       = var.monthly_budget_usd
  enable_anomaly_detection = var.enable_anomaly_detection

  tags = local.common_tags
}
