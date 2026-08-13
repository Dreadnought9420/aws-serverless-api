provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = var.project_name
      Component  = "bootstrap"
      ManagedBy  = "Terraform"
      Repository = "${var.github_owner}/${var.github_repository}"
    }
  }
}
