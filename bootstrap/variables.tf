variable "aws_region" {
  description = "AWS region that hosts the Terraform state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short project slug used as a prefix for every bootstrap resource."
  type        = string
  default     = "serverless-portfolio"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be 3-31 chars, lowercase alphanumeric or hyphen, starting with a letter."
  }
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket. Leave null to derive it from the project name and account ID."
  type        = string
  default     = null
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository (the part before the slash)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.github_owner))
    error_message = "github_owner must be a valid GitHub account name."
  }
}

variable "github_repository" {
  description = "Repository name that CI runs from (the part after the slash)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository must be a valid GitHub repository name."
  }
}

variable "github_default_branch" {
  description = "Branch allowed to assume the plan role on push events."
  type        = string
  default     = "main"
}

variable "github_apply_environment" {
  description = "GitHub Actions environment name whose jobs may assume the apply role. Protect this environment with required reviewers."
  type        = string
  default     = "production"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false if the account already has one (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "state_noncurrent_version_retention_days" {
  description = "How long non-current state file versions are kept before expiring."
  type        = number
  default     = 90

  validation {
    condition     = var.state_noncurrent_version_retention_days >= 7
    error_message = "Keep at least 7 days of state history so a bad apply can be rolled back."
  }
}
