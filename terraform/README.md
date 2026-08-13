# terraform — workload stack

The root module CI plans and applies. It wires the four modules together and owns
nothing directly except a `aws_caller_identity` lookup.

## Backend

Partial configuration, so the same code can point at a different state location
without being edited:

```bash
terraform init -backend-config=backend.hcl        # local
# or, in CI
terraform init -backend-config="bucket=..." -backend-config="key=..." -backend-config="region=..."
```

`use_lockfile = true` writes a `<key>.tflock` object beside the state file. There
is no DynamoDB lock table ([ADR-0004](../docs/adr/0004-s3-native-state-locking.md)).

## Providers

Two configurations:

| Alias | Region | Used by |
| --- | --- | --- |
| default | `var.aws_region` | Everything regional |
| `us_east_1` | `us-east-1` | The CloudFront alarm, AWS Budgets, Cost Explorer |

`observability` receives both (it declares a `configuration_aliases` for the
CloudFront alarm); `cost_guardrails` receives `us_east_1` as its default
provider, because Budgets and Cost Explorer are only addressable there.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # alert_email is required

make init
make plan
make apply
make output
```

## Cost levers

| Variable | Default | Effect |
| --- | --- | --- |
| `lambda_reserved_concurrency` | `10` | Hard ceiling on compute cost. `-1` removes it |
| `log_retention_days` | `14` | CloudWatch Logs ingest and storage |
| `cloudfront_price_class` | `PriceClass_100` | Edge locations. Already the cheapest |
| `monthly_budget_usd` | `10` | Budget alert threshold, not a hard cap |

<!-- BEGIN_TF_DOCS -->
<!-- Run `make docs` to populate this section with terraform-docs. -->
<!-- END_TF_DOCS -->
