output "site_url" {
  description = "Open this in a browser. Serves the static site and proxies /api/* to the HTTP API."
  value       = module.site.site_url
}

output "api_health_url" {
  description = "Health check endpoint through CloudFront."
  value       = "${module.site.site_url}/api/health"
}

output "cloudfront_distribution_id" {
  description = "Distribution ID, needed to invalidate the cache after a frontend deploy."
  value       = module.site.distribution_id
}

output "site_bucket_name" {
  description = "S3 bucket backing the static site."
  value       = module.site.bucket_name
}

output "api_endpoint" {
  description = "Direct execute-api endpoint. Debugging only; the public path is through CloudFront."
  value       = module.api.api_endpoint
}

output "lambda_function_name" {
  description = "Name of the API Lambda function."
  value       = module.api.function_name
}

output "lambda_log_group_name" {
  description = "CloudWatch log group for the API function."
  value       = module.api.log_group_name
}

output "dynamodb_table_name" {
  description = "Name of the items table."
  value       = module.api.table_name
}

output "alerts_topic_arn" {
  description = "SNS topic that alarms publish to. Confirm the email subscription before relying on it."
  value       = module.observability.alerts_topic_arn
}

output "dashboard_url" {
  description = "Direct link to the CloudWatch dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.observability.dashboard_name}"
}

output "monthly_budget_usd" {
  description = "Configured monthly budget limit."
  value       = module.cost_guardrails.budget_limit_usd
}
