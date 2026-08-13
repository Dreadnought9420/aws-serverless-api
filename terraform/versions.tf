terraform {
  # 1.10 is the floor: S3 native state locking (use_lockfile) landed there and
  # this project deliberately does not create a DynamoDB lock table.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
