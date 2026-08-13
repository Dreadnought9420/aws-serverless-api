variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"serverless-portfolio-dev\"."
  type        = string
}

variable "alert_email" {
  description = "Address that receives budget and cost anomaly notifications."
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

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}

variable "actual_threshold_percent" {
  description = "Percentage of the budget that, once actually spent, triggers the first notification."
  type        = number
  default     = 80

  validation {
    condition     = var.actual_threshold_percent > 0 && var.actual_threshold_percent <= 100
    error_message = "actual_threshold_percent must be between 1 and 100."
  }
}

variable "forecast_threshold_percent" {
  description = "Percentage of the budget that, once forecast to be reached, triggers the second notification."
  type        = number
  default     = 100

  validation {
    condition     = var.forecast_threshold_percent > 0
    error_message = "forecast_threshold_percent must be greater than zero."
  }
}

variable "enable_anomaly_detection" {
  description = "Create a Cost Explorer anomaly monitor and subscription. The service itself is free."
  type        = bool
  default     = true
}

variable "anomaly_threshold_usd" {
  description = "Absolute dollar impact an anomaly must reach before a notification is sent."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Additional tags merged onto every taggable resource in this module."
  type        = map(string)
  default     = {}
}
