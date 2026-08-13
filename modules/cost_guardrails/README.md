# modules/cost_guardrails

A monthly AWS Budget with actual and forecast notifications, plus a Cost Explorer
anomaly monitor.

## Usage

AWS Budgets and Cost Explorer are global services addressed through us-east-1, so
pass the us-east-1 alias in as this module's default provider:

```hcl
module "cost_guardrails" {
  source = "../modules/cost_guardrails"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix        = "serverless-portfolio-dev"
  alert_email        = var.alert_email
  monthly_budget_usd = 10

  tags = local.common_tags
}
```

Creating these in any other region fails, or silently creates something that
never fires.

## Why two notifications

- **80 percent of ACTUAL spend** — you have already spent it. Useful for
  awareness, useless for prevention.
- **100 percent of FORECAST** — you are trending over budget. This is the one
  that matters: it arrives while there is still time to act.

## Cost anomaly detection

A `DIMENSIONAL` monitor on `SERVICE` with a daily subscription above a USD 5
absolute impact. It detects the *shape* of spend changing rather than the total,
which catches a single service misbehaving while the overall bill is still under
budget. The service itself is free.

## What this module does not do

It does not stop spending. `aws_budgets_budget_action` can attach a deny policy
or stop instances when a threshold is crossed, but that means giving a budget
permission to modify IAM — a powerful and easily misconfigured capability. For a
personal project the alert is the right level of response. The real spending
ceilings are Lambda reserved concurrency and API Gateway stage throttling, both
in `modules/serverless_api`.

<!-- BEGIN_TF_DOCS -->
<!-- Run `make docs` to populate this section with terraform-docs. -->
<!-- END_TF_DOCS -->
