# Security

## Threat model

What this stack is actually defending against, and from whom.

| Actor | Capability | Primary control |
| --- | --- | --- |
| Anonymous internet user | Can call the public API and read the site | Stage throttling, reserved concurrency, input validation, TTL |
| Malicious pull request | Can propose arbitrary workflow and Terraform changes | `ci.yml` has no cloud credentials; apply requires a human approval and a separate role |
| Compromised GitHub account | Can push to `main` | Apply still requires the `production` environment approval; credentials expire in one hour |
| Compromised CI run | Holds a short-lived role session | Plan role is read-only; apply role is denied permission to modify the CI roles |
| Someone who finds the S3 bucket name | Can attempt direct object access | All four public-access blocks on; bucket policy allows only CloudFront with a pinned `AWS:SourceArn` |

What it is **not** defending against: an authenticated AWS account owner with
console access, a supply-chain compromise of Terraform or a provider, or a
determined DDoS (there is no WAF and no Shield Advanced).

## Identity

### No long-lived credentials, anywhere

No AWS access key exists in this repository, in GitHub secrets, or on a
developer machine used for CI. GitHub Actions assumes a role via OIDC and gets a
one-hour session ([ADR-0003](adr/0003-github-oidc-over-static-keys.md)).

### Trust policies

Both roles pin the audience and the subject:

```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
  },
  "StringEquals": {
    "token.actions.githubusercontent.com:sub":
      "repo:<owner>/<repo>:environment:production"
  }
}
```

The failure mode to watch for is a wildcard `sub` — `repo:*:*`, or
`repo:<owner>/*:ref:*`. Either turns a correctly configured OIDC setup into a
role that any repository can assume. This project pins the exact repository plus
a branch (plan) or an environment (apply).

### Privilege separation

| Role | Trusted from | Grants | Explicitly denied |
| --- | --- | --- | --- |
| `*-gha-plan` | `pull_request`, `refs/heads/main` | `ReadOnlyAccess`, read/write on the state prefix | — |
| `*-gha-apply` | `environment:production` | `PowerUserAccess`, IAM management scoped to `<project>-*` roles | `iam:*` on both CI roles |

The plan role needs write access to the state prefix even though it is
"read-only": taking and releasing an S3 native lock is a write.

The apply role is `PowerUserAccess` rather than `AdministratorAccess`, plus a
narrow IAM slice for the roles this project creates, plus an explicit `Deny` on
the two CI roles. A compromised apply session can therefore damage the workload
but cannot rewrite the trust policy that would let it come back.

### Lambda execution role

Least privilege, hand-written rather than the managed policy:

- `logs:CreateLogStream` and `logs:PutLogEvents` on **its own log group only**.
  `AWSLambdaBasicExecutionRole`, the usual shortcut, grants those account-wide.
- `dynamodb:GetItem`, `PutItem`, `DeleteItem`, `Query` on **this table only**.
  No `Scan`, no `BatchWriteItem`, no `DeleteTable`.
- `xray:PutTraceSegments` and `PutTelemetryRecords` — these genuinely require
  `Resource: "*"`; the X-Ray API has no resource-level permissions.

## Data protection

| Control | Where |
| --- | --- |
| Encryption at rest | S3 site bucket (AES256), S3 state bucket (SSE-KMS, `alias/aws/s3`), DynamoDB (SSE), CloudWatch Logs (service-managed) |
| Encryption in transit | CloudFront `redirect-to-https` on the site, `https-only` on `/api/*`, TLS 1.2 minimum, `https-only` to the API origin |
| TLS enforced at the bucket | `DenyInsecureTransport` statement on both bucket policies |
| Public access | All four block settings on both buckets |
| Object ownership | `BucketOwnerEnforced` — ACLs are disabled entirely, so no ACL can re-open a bucket |
| Versioning | Both buckets. State versioning is the rollback mechanism in the runbook |
| Backup | DynamoDB point-in-time recovery |
| Retention | Log groups 14 days, DynamoDB TTL 30 days, non-current state versions 90 days |

## Application controls

- **Input validation** in the handler: type, non-empty, length ceiling on
  `message`; a regex on the item id before it reaches DynamoDB; `limit` clamped
  to a maximum page size.
- **No injection surface.** DynamoDB is accessed through boto3's
  `Key()`/`Attr()` condition builders, never through string construction.
- **Errors are not echoed.** A `ClientError` returns a generic 503; the AWS error
  code goes to the log, not the response. AWS errors leak table names, ARNs and
  the account ID.
- **No stack traces in responses.** The catch-all in the entry point logs and
  returns a bare 500.
- **`textContent`, never `innerHTML`** in the frontend, so a stored message can
  never become markup.
- **CSP without `unsafe-inline`.** The page has no inline script or style — that
  is why `app.js` and `styles.css` are separate files rather than embedded.

## Edge controls

The response headers policy applies to every response, including API responses,
because they share the distribution:

| Header | Value |
| --- | --- |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` |
| `Content-Security-Policy` | `default-src 'self'` with no `unsafe-inline` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `X-XSS-Protection` | `1; mode=block` |

## Supply chain

- Terraform and provider versions are pinned; `.terraform.lock.hcl` is committed
  and reviewed.
- Dependabot watches GitHub Actions, Terraform providers and pip weekly.
- Provider and runtime upgrades go in their own pull request, never mixed with a
  functional change.
- `gitleaks` runs as a pre-commit hook.
- Checkov and Trivy run on every pull request; Checkov results are uploaded as
  SARIF to the Security tab.

## Accepted gaps

Every suppression in `.checkov.yaml` and `.trivyignore` appears here. Nothing is
silenced without a reason written down.

| Check | Control | Why it is accepted | Revisit when |
| --- | --- | --- | --- |
| `CKV_AWS_86`, `AVD-AWS-0010` | CloudFront access logging | v1 standard logging requires S3 ACLs, which conflict with the `BucketOwnerEnforced` ownership enforced everywhere here. v2 delivers to CloudWatch Logs at recurring ingest cost. API access logs already capture the request path that matters | The site handles anything non-public, or an incident needs edge-level forensics |
| `CKV_AWS_68`, `CKV2_AWS_47`, `AVD-AWS-0011` | WAF on CloudFront | USD 5/month per Web ACL before a single request — 5x the entire rest of the stack. The API is throttled, concurrency-capped and stores only short public strings | The API stores anything sensitive, or abuse actually happens |
| `CKV_AWS_144` | S3 cross-region replication | Single-region by design. The site is rebuildable from git in one `apply` | The stack becomes multi-region |
| `CKV_AWS_18`, `AVD-AWS-0089` | S3 server access logging | Nothing reaches the bucket except CloudFront over OAC. Bucket-level access logs would record only CloudFront's own reads | The bucket ever gains a second reader |
| `CKV_AWS_117` | Lambda in a VPC | The function calls only AWS public API endpoints. A VPC would add a NAT gateway (USD 32/month) or interface endpoints for no security gain | The function needs to reach a private resource |
| `CKV_AWS_173` | KMS CMK for Lambda env vars | The variables are a table name, a log level and a TTL. None is a secret. AWS-managed encryption already applies | A secret ever enters the environment — at which point it should go to Secrets Manager instead |
| `CKV_AWS_272` | Lambda code signing | Requires a Signer profile and a signing pipeline. Deferred, not rejected | The deployment package stops being built from source in the same repository |
| `CKV_AWS_26` (implicit) | SNS topic encryption | CloudWatch cannot publish to a topic encrypted with the AWS-managed `alias/aws/sns` key. Encryption requires a CMK at ~USD 1/month whose policy grants `kms:GenerateDataKey` to `cloudwatch.amazonaws.com`. The messages say "an alarm changed state" | Alarm payloads ever carry sensitive detail. `sns_kms_key_id` is already a variable |

Additional suppressions, all of the same shape — a control whose cost or
operational burden is out of proportion to what this stack actually protects:

| Check | Control | Why it is accepted |
| --- | --- | --- |
| `CKV_AWS_158` | CloudWatch Logs CMK | Logs are already encrypted at rest with an AWS-managed key. A CMK adds ~USD 1/month to encrypt request paths and status codes |
| `CKV_AWS_338` | One-year log retention | 14 days is deliberate: ingest and storage are the main CloudWatch cost driver, and there is no compliance retention requirement |
| `CKV_AWS_119` | DynamoDB CMK | The table holds short public strings. The AWS-owned key is free and sufficient |
| `CKV2_AWS_62` | S3 event notifications | Nothing consumes bucket events |
| `CKV_AWS_310` | CloudFront origin failover | Needs a second replicated bucket. Single-region by design |
| `CKV_AWS_374` | CloudFront geo restriction | The site is meant to be reachable from anywhere |

### Confirmed by a real Checkov run

The table above was written ahead of the first CI run. These seven were what
Checkov actually reported, and each was assessed rather than reflexively
silenced:

| Check | Control | Why it is accepted |
| --- | --- | --- |
| `CKV_AWS_109` | "IAM policy without constraints" on the apply role | The statement *is* constrained to `role/<project>-*`, and the same document carries an explicit `Deny` on both CI roles. Checkov's heuristic does not read `Deny` statements as constraints. `iam:CreateServiceLinkedRole` genuinely requires `Resource: "*"` — AWS rejects anything narrower |
| `CKV_AWS_116` | Lambda dead letter queue | A DLQ only receives events from **asynchronous** invocation. This function is invoked synchronously by API Gateway, so a failure returns a 5xx to the caller and trips the `api-5xx` alarm. A DLQ here would never receive a single message |
| `CKV_AWS_309` (×2) | API Gateway v2 route authorization | The API is deliberately public. It is throttled, concurrency-capped, length-validated and TTL-pruned instead |
| `CKV_AWS_174` | CloudFront viewer certificate TLS ≥ 1.2 | The default `*.cloudfront.net` certificate pins its own minimum protocol version; the argument is inert until an ACM certificate replaces it |
| `CKV2_AWS_42` | CloudFront custom SSL certificate | Same root cause. Both need an owned domain plus ACM in us-east-1, which would make this repo undeployable from a clean fork — see [ADR-0008](adr/0008-cloudfront-single-origin.md) |
| `CKV_AWS_145` | S3 default encryption with KMS (site bucket) | SSE-KMS behind CloudFront OAC needs a key policy granting the CloudFront service principal `kms:Decrypt`, and bills a KMS request on every cache miss. The **state** bucket, where it matters, does use SSE-KMS |

**If a scanner reports something new**, either fix it or add it to this table
with a reason. A suppression with no row here should not pass review.

Two more gaps that no scanner flags but are worth stating plainly:

- **The API is unauthenticated and writable.** Anyone can POST to it. It is
  throttled, concurrency-capped, length-limited and TTL-pruned, but it is open by
  design. Adding auth means a JWT authorizer on the HTTP API.
- **The `execute-api` endpoint is directly reachable.** Traffic normally arrives
  through CloudFront, which is what applies the security headers, but the origin
  is not itself restricted to CloudFront. Closing that would need a WAF rule or a
  shared-secret header check at the gateway.

## Reporting a vulnerability

Open a private security advisory through the repository's **Security** tab
rather than a public issue.
