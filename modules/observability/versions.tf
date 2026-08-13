terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"

      # CloudFront publishes its metrics only to us-east-1, so alarms on the
      # distribution have to be created there regardless of where the rest of
      # the stack lives.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
