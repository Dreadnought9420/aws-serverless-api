output "api_id" {
  description = "HTTP API identifier."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Default execute-api endpoint. Debugging only; production traffic goes through CloudFront."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_origin_domain_name" {
  description = "Hostname of the API endpoint, suitable for use as a CloudFront custom origin."
  value       = replace(aws_apigatewayv2_api.this.api_endpoint, "https://", "")
}

output "function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.api.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function."
  value       = aws_lambda_function.api.arn
}

output "log_group_name" {
  description = "CloudWatch log group receiving function logs."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "api_access_log_group_name" {
  description = "CloudWatch log group receiving API Gateway access logs."
  value       = aws_cloudwatch_log_group.api_access.name
}

output "table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.items.name
}

output "table_arn" {
  description = "ARN of the DynamoDB table."
  value       = aws_dynamodb_table.items.arn
}
