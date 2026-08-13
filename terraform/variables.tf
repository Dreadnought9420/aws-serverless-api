variable "aws_region" {
  description = "Region the workload is deployed to."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short project slug. Combined with the environment to prefix every resource name."
  type        = string
  default     = "serverless-portfolio"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be 3-31 chars, lowercase alphanumeric or hyphen, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment. Part of every resource name, so changing it creates a parallel stack."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "owner" {
  description = "Value of the Owner tag applied to every resource."
  type        = string
  default     = "platform"
}

variable "repository_url" {
  description = "Repository this stack is deployed from. Recorded as a tag so any resource can be traced back to its source."
  type        = string
  default     = "https://github.com/Dreadnought9420/aws-serverless-api"
}

variable "alert_email" {
  description = "Address subscribed to alarm, budget and cost anomaly notifications. Confirm the SNS subscription email after the first apply."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly account spend limit in USD that the budget alerts against."
  type        = number
  default     = 10
}

variable "lambda_memory_mb" {
  description = "Memory allocated to the API function."
  type        = number
  default     = 256
}

variable "lambda_reserved_concurrency" {
  description = "Concurrency ceiling for the API function. This is the main brake on a runaway bill; -1 removes it."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for function and API access logs."
  type        = number
  default     = 14
}

variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_100 covers North America and Europe and is the cheapest."
  type        = string
  default     = "PriceClass_100"
}

variable "manage_site_content" {
  description = "Let Terraform upload the contents of src/frontend. Set to false once a separate frontend pipeline owns deploys."
  type        = bool
  default     = true
}

variable "enable_anomaly_detection" {
  description = "Create the Cost Explorer anomaly monitor and subscription."
  type        = bool
  default     = true
}
