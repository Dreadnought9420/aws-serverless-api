variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"serverless-portfolio-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-41 chars, lowercase alphanumeric or hyphen, starting with a letter."
  }
}

variable "bucket_suffix" {
  description = "Suffix appended to the origin bucket name to make it globally unique (typically the AWS account ID)."
  type        = string
}

variable "content_dir" {
  description = "Absolute or module-relative path to the directory of static files to publish."
  type        = string
}

variable "manage_site_content" {
  description = "Let Terraform own the objects in the origin bucket. Set to false once a separate frontend pipeline takes over uploads."
  type        = bool
  default     = true
}

variable "api_origin_domain_name" {
  description = "Domain name of the HTTP API to serve under the API path pattern, without scheme or trailing slash."
  type        = string
}

variable "api_path_pattern" {
  description = "CloudFront path pattern routed to the API origin instead of S3."
  type        = string
  default     = "/api/*"
}

variable "default_root_object" {
  description = "Object returned for requests to the distribution root."
  type        = string
  default     = "index.html"
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (US/EU only) is the cheapest."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

# Read this before turning spa_fallback on. CloudFront custom error responses
# are configured per DISTRIBUTION, not per cache behavior. Because this
# distribution also serves the API under /api/*, enabling the rewrite turns
# every legitimate API 404 into an HTML page with a 200 status. Enable it only
# if the API moves to its own distribution, or replace it with a CloudFront
# Function on viewer-request scoped to the default behavior.
variable "spa_fallback" {
  description = "Rewrite 403 and 404 responses to the root object with a 200 status. Off by default; see the comment above."
  type        = bool
  default     = false
}

variable "content_security_policy" {
  description = "Value of the Content-Security-Policy response header served by CloudFront."
  type        = string
  default     = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
}

variable "hsts_max_age_seconds" {
  description = "max-age directive for the Strict-Transport-Security header."
  type        = number
  default     = 31536000

  validation {
    condition     = var.hsts_max_age_seconds >= 31536000
    error_message = "HSTS max-age must be at least one year (31536000) to be eligible for preload lists."
  }
}

variable "tags" {
  description = "Additional tags merged onto every taggable resource in this module."
  type        = map(string)
  default     = {}
}
