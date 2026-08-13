locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
    Repository  = var.repository_url
  }

  # Source paths are resolved from the root module so the modules stay
  # relocatable and do not reach outside their own directory.
  api_source_dir      = "${path.root}/../src/api"
  frontend_source_dir = "${path.root}/../src/frontend"
}
