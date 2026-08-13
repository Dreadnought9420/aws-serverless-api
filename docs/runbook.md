# Runbook

Operational procedures for the serverless portfolio stack. Every command assumes
the repository root as the working directory.

## Contents

- [First-time setup](#first-time-setup)
- [Routine deploy](#routine-deploy)
- [Rollback](#rollback)
- [Alarm response](#alarm-response)
- [State operations](#state-operations)
- [Common failures](#common-failures)
- [Teardown](#teardown)

---

## First-time setup

### 1. Bootstrap

```bash
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
$EDITOR bootstrap/terraform.tfvars      # github_owner, github_repository
./scripts/bootstrap.sh
```

Needs credentials that can create IAM roles and an S3 bucket. This is the only
time real credentials touch a laptop.

If the account already has a GitHub OIDC provider — only one is allowed per
account — set `create_oidc_provider = false` first. The stack then references the
existing one by ARN.

### 2. GitHub configuration

Repository variables (**Settings → Secrets and variables → Actions → Variables**):
`AWS_REGION`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `TF_STATE_BUCKET`,
`TF_STATE_KEY`, `ALERT_EMAIL`.

Then **Settings → Environments → New environment → `production`**, and add
yourself under **Required reviewers**.

Skipping the reviewer means every merge to `main` applies to AWS without a human
in the loop. The IAM trust policy still restricts *who* can assume the role, but
nothing pauses for approval.

### 3. First apply

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars      # alert_email
make init && make plan && make apply
```

### 4. Confirm the SNS subscription

AWS emails a confirmation link to `alert_email`. **Until it is clicked, no alarm
notification is delivered.** The alarm still changes state and the dashboard
still shows it; the email simply never arrives.

Verify:

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn "$(terraform -chdir=terraform output -raw alerts_topic_arn)" \
  --query 'Subscriptions[].SubscriptionArn'
```

A value of `PendingConfirmation` means it has not been confirmed.

---

## Routine deploy

### Through CI (normal path)

1. Branch, change, open a pull request.
2. `ci.yml` runs format, validate, lint, mocked tests and security scans with no
   AWS access at all.
3. `terraform.yml` plans with the read-only role and posts the plan as a comment.
4. Read the plan. Look specifically for `destroy` and `replace` lines.
5. Merge. The apply job waits at the `production` environment gate.
6. Approve. Apply consumes **the plan artifact from that run**, not a new plan.
7. The job invalidates the CloudFront cache and prints the outputs.

### Locally (break-glass)

```bash
make init
make plan
# read the plan
make apply
```

`make apply` applies the `tfplan` file `make plan` produced. Never
`terraform apply` without a plan file on anything you care about.

### Frontend-only change

While `manage_site_content = true`, Terraform owns the objects, so a frontend
change is a normal apply followed by:

```bash
make invalidate
```

Once a separate frontend pipeline takes over, set `manage_site_content = false`
and use `./scripts/deploy-frontend.sh`. Running both at once means Terraform and
`aws s3 sync` fight over the same keys on every deploy.

---

## Rollback

### Application or infrastructure regression

Revert the commit and let the pipeline apply the previous state:

```bash
git revert <sha>
git push
# approve the apply
```

This is the preferred path. It leaves the repository as the source of truth.

### Emergency: previous state file

Only when the configuration is fine and state itself is wrong.

```bash
BUCKET=$(terraform -chdir=bootstrap output -raw state_bucket_name)
KEY=<project>/terraform.tfstate

aws s3api list-object-versions --bucket "$BUCKET" --prefix "$KEY" \
  --query 'Versions[?IsLatest==`false`].[VersionId,LastModified]' --output table

aws s3api get-object --bucket "$BUCKET" --key "$KEY" \
  --version-id <VERSION_ID> restored.tfstate

# Inspect before pushing it anywhere.
terraform -chdir=terraform state push restored.tfstate
```

Keep `restored.tfstate` and the version ID as evidence. `state push` is the most
destructive command in the toolbox; the bucket is versioned precisely so this is
recoverable, but only if the current state is preserved first.

### CloudFront-only rollback

Distribution changes take 5-10 minutes to propagate. Reverting is a normal apply
plus the same wait. There is no instant switch.

---

## Alarm response

### `lambda-errors`

```bash
aws logs tail "$(terraform -chdir=terraform output -raw lambda_log_group_name)" \
  --since 30m --filter-pattern '"ERROR"'
```

Every log line is JSON with `event`, `request_id`, `method`, `path` and
`duration_ms`. Correlate `request_id` with the API access log group.

- `aws_call_failed` — DynamoDB or IAM. Check the table exists and the role policy
  still matches the table ARN.
- `unhandled_error` — a real bug. The stack trace is in the same log group under
  the `unhandled_error` logger record.

### `lambda-throttles`

Reserved concurrency is capping real traffic. Either raise
`lambda_reserved_concurrency` deliberately, or accept the throttle as the cost
control it was designed to be. Do not raise it reflexively — that limit is the
only thing standing between a traffic spike and an unbounded bill.

### `lambda-duration-p95`

```bash
aws logs start-query \
  --log-group-name "$(terraform -chdir=terraform output -raw lambda_log_group_name)" \
  --start-time "$(date -d '1 hour ago' +%s)" --end-time "$(date +%s)" \
  --query-string 'fields @timestamp, duration_ms, path | sort duration_ms desc | limit 20'
```

Check X-Ray for where the time goes. If it is DynamoDB, look at item size and
`Limit`. If it is initialisation, the function is cold-starting more than
expected.

### `api-5xx`

A 5xx from the gateway rather than the function usually means the integration
failed: the function was throttled, timed out, or the permission is wrong. Check
`integrationError` in the access log group.

### `cloudfront-5xx-rate`

Almost always an origin problem rather than CloudFront itself. Check `api-5xx`
first. If the API is healthy, check the S3 origin: an OAC or bucket-policy change
shows up here as 403s counted as 5xx at the edge.

### Budget or anomaly alert

```bash
aws ce get-cost-and-usage \
  --time-period Start="$(date -d '7 days ago' +%F)",End="$(date +%F)" \
  --granularity DAILY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

For this stack the plausible causes are, in order: CloudFront data transfer from
unexpected traffic, Lambda invocations from the same, and DynamoDB storage if TTL
is not pruning. See [cost.md](cost.md).

---

## State operations

### Stale lock

A run killed mid-apply leaves a `.tflock` object behind. Terraform prints the
lock ID when it refuses to proceed.

```bash
terraform -chdir=terraform force-unlock <LOCK_ID>
```

If that fails, delete the object directly — **only after confirming no apply is
running**:

```bash
aws s3api delete-object \
  --bucket "$(terraform -chdir=bootstrap output -raw state_bucket_name)" \
  --key "<project>/terraform.tfstate.tflock"
```

Breaking a lock while an apply is genuinely in flight can corrupt state. Check
the Actions tab first.

### Inspect state

```bash
terraform -chdir=terraform state list
terraform -chdir=terraform state show module.api.aws_lambda_function.api
```

### Import an existing resource

Use an `import` block rather than `terraform import`, so the import is reviewable
in a pull request:

```hcl
import {
  to = module.api.aws_dynamodb_table.items
  id = "serverless-portfolio-dev-items"
}
```

Then `terraform plan` and confirm it reports no changes before merging.

---

## Common failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Error: Unsupported argument: use_lockfile` | Terraform < 1.10 | Upgrade. The version floor exists so you cannot silently run without a lock |
| CI: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy `sub` does not match | Compare `github_owner`/`github_repository` in the bootstrap tfvars with the actual repository. For apply, the run must be in the `production` environment |
| CI apply hangs forever | `production` environment has a reviewer and nobody approved | Approve in the Actions tab |
| API returns 403 with an unhelpful body | CloudFront is forwarding `Host` to API Gateway | The `/api/*` behavior must use the managed `AllViewerExceptHostHeader` origin request policy |
| Site returns 403 from CloudFront | Bucket policy `AWS:SourceArn` does not match, or the objects are not there | `aws s3 ls s3://$(terraform -chdir=terraform output -raw site_bucket_name)` |
| API responses are stale | The `/api/*` behavior is caching | It must use the managed `CachingDisabled` cache policy |
| Alarms sit in `INSUFFICIENT_DATA` | `treat_missing_data` is not `notBreaching` | Already handled in the module; if you add an alarm, match the pattern |
| No alarm emails | SNS subscription never confirmed | See [First-time setup](#first-time-setup) step 4 |
| `BucketAlreadyExists` on first apply | S3 bucket names are globally unique | The name includes the account ID; if it still collides, set `state_bucket_name` explicitly |
| `terraform destroy` fails on the state bucket | `prevent_destroy` on the bootstrap bucket | Intentional. Remove the lifecycle block deliberately if you really mean it |
| Drift issue opened every morning | Something is changing resources outside Terraform | Read the diff before applying. It may be a legitimate emergency fix that belongs in code |

---

## Teardown

```bash
make destroy-plan    # prints every resource that will be deleted
```

Read it. `for_each` and locals pull in implicit dependents that are not obvious
from the module list.

```bash
make destroy
```

Then, if you are done with the account entirely:

```bash
# The state bucket has prevent_destroy and versioning. Removing it is manual,
# deliberate, and irreversible.
aws s3 rm "s3://$(terraform -chdir=bootstrap output -raw state_bucket_name)" --recursive
terraform -chdir=bootstrap destroy
```

The `bootstrap` destroy fails until the `prevent_destroy` lifecycle block on
`aws_s3_bucket.state` is removed. That is the guardrail working.
