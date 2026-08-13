# Architecture

## The shape of it

Three tiers, one public hostname.

```
Browser
  │  HTTPS
  ▼
CloudFront distribution ──── default behavior ────► S3 (private, OAC only)
  │
  └──────────────── /api/* ────────────────────────► API Gateway HTTP API
                                                        │  AWS_PROXY
                                                        ▼
                                                     Lambda (Python 3.13, arm64)
                                                        │
                                                        ▼
                                                     DynamoDB (on-demand, TTL)
```

Everything else — CloudWatch, SNS, X-Ray, Budgets, IAM, the state bucket — hangs
off that spine.

## Request walkthrough

### `GET /`

1. The browser resolves the CloudFront domain to the nearest edge location.
2. CloudFront matches the default cache behavior and consults its cache using the
   managed `CachingOptimized` policy.
3. On a miss it signs a SigV4 request to the S3 origin using the Origin Access
   Control. The bucket policy allows `s3:GetObject` for the
   `cloudfront.amazonaws.com` service principal **only when `AWS:SourceArn`
   matches this distribution** — no other distribution, in any account, can read
   it.
4. The response passes through the response headers policy, which attaches HSTS,
   CSP, `X-Content-Type-Options`, `frame-options: DENY`, a referrer policy and
   XSS protection.
5. There is deliberately **no** SPA error rewrite. CloudFront custom error
   responses are configured per distribution, not per cache behavior, so a
   403/404 rewrite would also catch legitimate API 404s and turn them into an
   HTML page with a 200 status. The `spa_fallback` variable exists, defaults to
   off, and documents the caveat. The correct fix when a client-side router is
   needed is a CloudFront Function on viewer-request scoped to the default
   behavior.

### `POST /api/items`

1. Same edge, but the path matches the `/api/*` ordered cache behavior.
2. That behavior uses the managed `CachingDisabled` cache policy — an API
   response cached at the edge is stale data with extra steps — and the managed
   `AllViewerExceptHostHeader` origin request policy.
3. `AllViewerExceptHostHeader` is load-bearing. It forwards every viewer header
   **except** `Host`. If CloudFront's `Host` reached API Gateway, the gateway
   would not recognise it and would answer 403 with a message that does not
   mention the header. This is the single most common way the dual-origin pattern
   fails.
4. API Gateway matches `ANY /api/{proxy+}` and invokes the Lambda function with a
   payload format 2.0 event.
5. The handler validates the body, writes an item to DynamoDB and returns 201.
6. API Gateway writes a JSON access log line; the handler writes its own JSON log
   line; the X-Ray SDK records a trace segment.

## Components

### Edge — `modules/static_site`

| Resource | Why |
| --- | --- |
| `aws_s3_bucket` + 5 companion resources | Private origin. Versioned, encrypted, `BucketOwnerEnforced`, lifecycle-pruned, all four public-access blocks on |
| `aws_cloudfront_origin_access_control` | SigV4 signing, `signing_behavior = always`. Replaces the legacy Origin Access Identity |
| `aws_cloudfront_distribution` | Two origins, two behaviors, SPA error rewrites, TLS 1.2 minimum |
| `aws_cloudfront_response_headers_policy` | Security headers on every response, including API responses |
| `aws_s3_bucket_policy` | Grants CloudFront read, pinned to the distribution ARN; denies non-TLS |
| `aws_s3_object` | Publishes `src/frontend` so a first `apply` yields a working site |

The bucket policy is written *after* the distribution exists, because it
references the distribution ARN. Terraform resolves this ordering itself.

### API — `modules/serverless_api`

| Resource | Why |
| --- | --- |
| `aws_apigatewayv2_api` + `_stage` + `_integration` + 2 `_route` | HTTP API on a `$default` auto-deploying stage. No stage path in the invoke URL, which is what lets CloudFront use it as an origin unmodified |
| `aws_lambda_function` | Python 3.13 on arm64, 256 MB, 10 s timeout, reserved concurrency 10, X-Ray active |
| `aws_dynamodb_table` | On-demand, `pk`/`sk`, TTL on `expires_at`, PITR, SSE |
| `aws_iam_role` + `aws_iam_role_policy` | Least privilege: logs scoped to its own log group, DynamoDB scoped to this table, X-Ray writes |
| `aws_cloudwatch_log_group` × 2 | Created explicitly so retention is finite. Lambda would otherwise create one implicitly with never-expire retention and then fight Terraform over it |
| `aws_lambda_permission` | `source_arn` scoped to this API. Without it, any API in the account could invoke the function |

The deployment package is produced by `archive_file` at plan time. There is no
build step ([ADR-0006](adr/0006-no-lambda-build-step.md)).

### Observability — `modules/observability`

Seven alarms, one dashboard, one SNS topic:

| Alarm | Metric | Fires when |
| --- | --- | --- |
| `lambda-errors` | `AWS/Lambda Errors` | Any error in 5 minutes |
| `lambda-throttles` | `AWS/Lambda Throttles` | Reserved concurrency is too low for real traffic |
| `lambda-duration-p95` | `AWS/Lambda Duration` p95 | Above 3 s for two periods |
| `api-5xx` | `AWS/ApiGateway 5xx` | Any server error |
| `cloudfront-5xx-rate` | `AWS/CloudFront 5xxErrorRate` | Above 5 percent |
| `dynamodb-read-throttle` | `ReadThrottleEvents` | Any throttled read |
| `dynamodb-write-throttle` | `WriteThrottleEvents` | Any throttled write |

Two details that are easy to get wrong:

- **`treat_missing_data = "notBreaching"`.** Serverless metrics are sparse. With
  no traffic there are no data points, and the CloudWatch default of `missing`
  parks every alarm in `INSUFFICIENT_DATA` — where it stays, silently, until
  someone notices the dashboard is grey.
- **CloudFront metrics only exist in us-east-1**, under the dimension
  `Region = "Global"`. The module declares a `configuration_aliases = [aws.us_east_1]`
  provider and creates that one alarm through it. Any other region, or any other
  dimension value, matches nothing and the alarm never fires.

The SNS topic is unencrypted by default, and that is deliberate: CloudWatch
cannot publish to a topic encrypted with the AWS-managed `alias/aws/sns` key, so
encryption requires a customer-managed key at roughly USD 1/month whose policy
grants `kms:GenerateDataKey` to `cloudwatch.amazonaws.com`. The `sns_kms_key_id`
variable is there for when that trade-off changes.

### Cost guardrails — `modules/cost_guardrails`

AWS Budgets and Cost Explorer are global services addressed through us-east-1,
so the root module passes the `aws.us_east_1` alias in as this module's default
provider.

- A monthly cost budget with two notifications: one at 80 percent of actual
  spend, one at 100 percent of *forecast*. The forecast alert is the useful one —
  it arrives while there is still time to act.
- A dimensional Cost Explorer anomaly monitor on `SERVICE`, with a daily
  subscription above a USD 5 absolute impact. The service itself is free.

### State and CI identity — `bootstrap/`

Applied once, by a human, with local state. It creates the things CI needs before
CI can exist:

- a versioned, encrypted, TLS-only S3 bucket for state, with `prevent_destroy`
- the GitHub Actions OIDC identity provider
- `*-gha-plan` — `ReadOnlyAccess` plus read/write on the state prefix
- `*-gha-apply` — `PowerUserAccess`, a scoped IAM slice for `<project>-*` roles,
  and an explicit `Deny` on both CI roles so it cannot escalate its own privileges

Its own state stays local, which is a deliberate chicken-and-egg resolution: the
stack that creates the state bucket cannot store its state in that bucket. It is
also nearly static — after the first apply it changes only when the repository
or the permission model changes.

## Naming and tagging

Every resource is prefixed `<project_name>-<environment>`, so changing
`environment` produces a parallel stack rather than mutating the existing one.

`default_tags` on both providers applies `Project`, `Environment`, `Owner`,
`ManagedBy` and `Repository` to everything taggable, which makes Cost Explorer
grouping and orphan hunting work without per-resource effort.

## What this architecture is not

- **Not multi-region.** One region plus CloudFront's global edge. Multi-region
  would mean DynamoDB global tables, a second stack and Route 53 failover.
- **Not multi-account.** A real organisation separates dev and prod into
  different accounts. Here `environment` separates them by name prefix and state
  key within one account.
- **Not zero-downtime on every change.** A CloudFront distribution update takes
  minutes to propagate. Nothing here is behind a blue/green switch.
- **Not authenticated.** The API is public and writable. It is rate-limited,
  concurrency-capped and TTL-pruned, but anyone can post to it. Adding auth means
  a JWT authorizer on the HTTP API and a Cognito user pool or an external IdP.
