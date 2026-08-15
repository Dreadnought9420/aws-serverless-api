# modules/observability

Seven CloudWatch alarms, one dashboard, one SNS topic with an email subscription.

## Usage

This module declares a `configuration_aliases` for `aws.us_east_1`, so the caller
must pass both providers:

```hcl
module "observability" {
  source = "../modules/observability"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix     = "serverless-portfolio-dev"
  aws_region      = var.aws_region
  alert_email     = var.alert_email
  function_name   = module.api.function_name
  log_group_name  = module.api.log_group_name
  api_id          = module.api.api_id
  table_name      = module.api.table_name
  distribution_id = module.site.distribution_id

  tags = local.common_tags
}
```

## The two things that are easy to get wrong

**`treat_missing_data = "notBreaching"`.** Serverless metrics are sparse — with
no traffic there are no data points at all. CloudWatch's default of `missing`
parks every alarm in `INSUFFICIENT_DATA`, where it stays silently until someone
notices the dashboard is grey. Every alarm here sets it explicitly, and a unit
test asserts it.

**CloudFront metrics only exist in us-east-1**, under the dimension
`Region = "Global"`. That is why the module needs a provider alias for one alarm.
Any other region, or any other dimension value, matches nothing and the alarm
never fires — silently.

## Validating this module

It cannot be validated as its own root module. `configuration_aliases =
[aws.us_east_1]` means a caller has to supply the aliased provider, and when the
module *is* the root there is no caller — `terraform validate` run directly here
fails on the CloudFront alarm's `provider = aws.us_east_1`.

`examples/default/` is a minimal root that wires both providers up. CI validates
that, which covers the same module code:

```bash
terraform -chdir=examples/default init -backend=false
terraform -chdir=examples/default validate
```

`terraform test` still runs in this directory, because the test files declare
`mock_provider "aws" { alias = "us_east_1" }`.

## SNS encryption

The topic is unencrypted by default and that is deliberate: CloudWatch cannot
publish to a topic encrypted with the AWS-managed `alias/aws/sns` key, so
encryption requires a customer-managed key (~USD 1/month) whose policy grants
`kms:GenerateDataKey` to `cloudwatch.amazonaws.com`. Pass one via
`sns_kms_key_id` when the messages start carrying anything sensitive.

## After the first apply

AWS sends a subscription confirmation email. **Until it is clicked, no
notification is delivered** — alarms still change state, the email just never
arrives.

<!-- BEGIN_TF_DOCS -->
<!-- Run `make docs` to populate this section with terraform-docs. -->
<!-- END_TF_DOCS -->
