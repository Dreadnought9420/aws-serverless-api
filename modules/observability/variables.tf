variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"serverless-portfolio-dev\"."
  type        = string
}

variable "alert_email" {
  description = "Address subscribed to the alarm topic. AWS sends a confirmation mail that must be accepted before alarms are delivered."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

# The AWS-managed `alias/aws/sns` key cannot be used here: CloudWatch cannot
# publish to a topic encrypted with an AWS-managed key. Encrypting the topic
# therefore needs a customer-managed key (about USD 1/month) whose policy grants
# kms:GenerateDataKey to cloudwatch.amazonaws.com. See docs/security.md.
variable "sns_kms_key_id" {
  description = "Customer-managed KMS key ARN or alias for the alarm topic. Leave null to store messages unencrypted."
  type        = string
  default     = null
}

variable "aws_region" {
  description = "Region the workload runs in. Used to build the dashboard widgets."
  type        = string
}

variable "function_name" {
  description = "Lambda function to alarm on."
  type        = string
}

variable "log_group_name" {
  description = "Lambda log group name, used by the dashboard log widget."
  type        = string
}

variable "api_id" {
  description = "HTTP API identifier to alarm on."
  type        = string
}

variable "table_name" {
  description = "DynamoDB table to alarm on."
  type        = string
}

variable "distribution_id" {
  description = "CloudFront distribution to alarm on."
  type        = string
}

variable "lambda_error_threshold" {
  description = "Number of function errors in one evaluation period that raises an alarm."
  type        = number
  default     = 1
}

variable "lambda_duration_threshold_ms" {
  description = "p95 function duration in milliseconds that raises an alarm."
  type        = number
  default     = 3000
}

variable "api_5xx_threshold" {
  description = "Number of API 5xx responses in one evaluation period that raises an alarm."
  type        = number
  default     = 1
}

variable "cloudfront_5xx_rate_threshold" {
  description = "Percentage of CloudFront requests returning 5xx that raises an alarm."
  type        = number
  default     = 5
}

variable "alarm_period_seconds" {
  description = "Evaluation period for the alarms."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Additional tags merged onto every taggable resource in this module."
  type        = map(string)
  default     = {}
}
