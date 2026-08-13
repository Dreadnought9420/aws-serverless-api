variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"serverless-portfolio-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-41 chars, lowercase alphanumeric or hyphen, starting with a letter."
  }
}

variable "source_dir" {
  description = "Directory containing the Lambda handler. Zipped at plan time; no build step required."
  type        = string
}

variable "lambda_runtime" {
  description = "Managed Lambda runtime identifier."
  type        = string
  default     = "python3.13"
}

variable "lambda_architecture" {
  description = "Instruction set for the function. arm64 (Graviton2) is ~20 percent cheaper per GB-second."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.lambda_architecture)
    error_message = "lambda_architecture must be arm64 or x86_64."
  }
}

variable "lambda_memory_mb" {
  description = "Memory allocated to the function. CPU scales linearly with this value."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 10240
    error_message = "lambda_memory_mb must be between 128 and 10240."
  }
}

variable "lambda_timeout_seconds" {
  description = "Function timeout. Keep below the API Gateway 30s integration limit."
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_timeout_seconds > 0 && var.lambda_timeout_seconds <= 29
    error_message = "lambda_timeout_seconds must be between 1 and 29 to stay inside the API Gateway integration timeout."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Maximum concurrent executions. Acts as a cost blast-radius limit; -1 disables the reservation."
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_reserved_concurrency == -1 || var.lambda_reserved_concurrency >= 0
    error_message = "lambda_reserved_concurrency must be -1 (unreserved) or a non-negative integer."
  }
}

variable "log_level" {
  description = "Log level passed to the handler."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "log_level must be one of DEBUG, INFO, WARNING, ERROR."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the function and the API access log."
  type        = number
  default     = 14

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be a retention period CloudWatch Logs accepts."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable DynamoDB point-in-time recovery. Roughly doubles storage cost; negligible at portfolio scale."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Block accidental deletion of the DynamoDB table. Leave false while iterating so `terraform destroy` works."
  type        = bool
  default     = false
}

variable "item_ttl_days" {
  description = "How long items survive before DynamoDB TTL removes them. Keeps the demo table from growing forever."
  type        = number
  default     = 30

  validation {
    condition     = var.item_ttl_days >= 1
    error_message = "item_ttl_days must be at least 1."
  }
}

variable "throttling_burst_limit" {
  description = "API Gateway per-stage burst limit."
  type        = number
  default     = 20
}

variable "throttling_rate_limit" {
  description = "API Gateway per-stage steady-state request rate limit."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Additional tags merged onto every taggable resource in this module."
  type        = map(string)
  default     = {}
}
