# ADR-0004: S3 native state locking over a DynamoDB lock table

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

Terraform state needs a remote backend with locking, so that a CI apply and a
local plan cannot corrupt state by writing concurrently.

For roughly a decade the standard answer on AWS was an S3 bucket plus a DynamoDB
table with a `LockID` primary key. Terraform 1.10 added `use_lockfile`, which
implements locking with a conditional write of a `<key>.tflock` object in the
same bucket. The DynamoDB arguments (`dynamodb_table`, `dynamodb_endpoint`,
`endpoints.dynamodb`) are now deprecated and slated for removal.

## Decision

Use the S3 backend with `use_lockfile = true` and `encrypt = true`. Create no
DynamoDB lock table. Pin `required_version = ">= 1.10.0"` so a configuration
that silently runs without locking cannot be produced by an older CLI.

## Options Considered

### Option A: S3 native lock file (chosen)

| Dimension | Assessment |
| --- | --- |
| Complexity | Low — one backend argument, one resource |
| Cost | Effectively zero; a few conditional PUTs per run |
| Correctness | Uses S3 conditional writes; strongly consistent since 2020 |
| Team familiarity | Medium — newer, so less blog coverage |

**Pros:** one fewer resource to create, tag, secure and pay for; one IAM policy
instead of two; the lock lives beside the state it protects.
**Cons:** requires Terraform 1.10 or newer; a stale lock is cleared by deleting
an S3 object rather than a DynamoDB item, which is unfamiliar.

### Option B: S3 plus a DynamoDB lock table

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium — a second resource and a second IAM statement |
| Cost | Pennies on-demand, but not zero |
| Correctness | Proven over a decade |
| Team familiarity | High |

**Pros:** every runbook and Stack Overflow answer assumes it; works on any
Terraform version.
**Cons:** deprecated; an extra resource whose only purpose is a lock; two places
to get IAM wrong.

### Option C: Terraform Cloud / HCP Terraform remote state

| Dimension | Assessment |
| --- | --- |
| Complexity | Low |
| Cost | Free tier available |
| Correctness | Managed |
| Team familiarity | Medium |

**Pros:** locking, history, drift detection and a run UI without building any of it.
**Cons:** introduces a dependency outside the AWS account, and the point of this
project is to show the AWS and GitHub Actions side of the workflow.

## Trade-off Analysis

Option B is not wrong, it is obsolete. Writing new configuration against a
deprecated argument means a forced migration later for no benefit today. The
only real reason to choose it is a Terraform version floor below 1.10, which
this project does not have.

Option C would remove the most interesting part of the CI design — the OIDC
trust boundary between GitHub and AWS — and replace it with someone else's
control plane.

## Consequences

- The bootstrap stack creates one bucket and no table.
- The CI IAM policy needs `s3:PutObject` and `s3:DeleteObject` on the state
  prefix even for the read-only plan role, because taking and releasing a lock
  is a write.
- A run killed mid-apply leaves a `<key>.tflock` object behind. Clearing it is
  `terraform force-unlock <id>`, with `aws s3 rm` as the fallback — documented in
  `docs/runbook.md`.
- Anyone on Terraform 1.9 or older cannot use this backend at all. That is the
  intended behaviour: silently running without a lock is worse.

## Action Items

1. [x] Set `required_version = ">= 1.10.0"` in every module
2. [x] Grant the plan role write access to the state prefix so it can lock
3. [x] Document stale-lock recovery in the runbook
