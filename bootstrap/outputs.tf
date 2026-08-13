output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Feed this to `terraform init -backend-config`."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_region" {
  description = "Region of the state bucket."
  value       = var.aws_region
}

output "plan_role_arn" {
  description = "IAM role ARN for the GitHub Actions plan job. Store as the AWS_PLAN_ROLE_ARN repository variable."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "IAM role ARN for the GitHub Actions apply job. Store as the AWS_APPLY_ROLE_ARN repository variable."
  value       = aws_iam_role.apply.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider."
  value       = local.oidc_provider_arn
}

output "github_actions_variables" {
  description = "Copy-paste block of the GitHub Actions repository variables to configure."

  value = {
    AWS_REGION         = var.aws_region
    AWS_PLAN_ROLE_ARN  = aws_iam_role.plan.arn
    AWS_APPLY_ROLE_ARN = aws_iam_role.apply.arn
    TF_STATE_BUCKET    = aws_s3_bucket.state.id
    TF_STATE_KEY       = "${var.project_name}/terraform.tfstate"
  }
}
