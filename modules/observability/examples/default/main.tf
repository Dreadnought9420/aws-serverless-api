# Minimal root module for the observability module.
#
# This exists because observability declares `configuration_aliases =
# [aws.us_east_1]` for the CloudFront alarm. A module with a configuration
# alias cannot be its own root module: nothing supplies the aliased provider,
# so `terraform validate` run directly in the module directory fails. CI
# validates this example instead, which exercises exactly the same module code
# with the providers wired up the way a real caller wires them.
#
# Validate only. Nothing here is meant to be applied.

provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "observability" {
  source = "../../"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix     = "example-dev"
  aws_region      = "eu-west-1"
  alert_email     = "alerts@example.com"
  function_name   = "example-dev-api"
  log_group_name  = "/aws/lambda/example-dev-api"
  api_id          = "abc123"
  table_name      = "example-dev-items"
  distribution_id = "E1EXAMPLE"

  tags = {
    Project = "example"
  }
}
