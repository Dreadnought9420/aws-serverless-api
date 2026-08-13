# Cost

## Summary

At portfolio traffic — say 10,000 page views and 50,000 API requests a month —
this stack costs **effectively nothing**: under USD 1/month outside the AWS Free
Tier, and USD 0.00 inside it.

That is not an accident. Idle cost drove the architecture
([ADR-0002](adr/0002-serverless-over-containers.md)), because a stack that bills
while nobody is looking at it gets torn down, and a torn-down project cannot be
demonstrated.

## Line by line

Prices are us-east-1 / eu-west-1 list prices as of August 2026 and will drift.
Check the [AWS pricing pages](https://aws.amazon.com/pricing/) before relying on
any number here.

| Service | Unit price | 10k views + 50k API calls | Notes |
| --- | --- | --- | --- |
| CloudFront | USD 0.085/GB out, USD 0.0100 per 10k HTTPS requests | ~USD 0.10 | Free tier: 1 TB out, 10M requests/month, permanently |
| S3 storage | USD 0.023/GB-month | < USD 0.01 | The site is a few hundred kilobytes |
| S3 requests | USD 0.0004 per 1k GET | < USD 0.01 | Only on CloudFront cache misses |
| API Gateway HTTP API | USD 1.00 per million | USD 0.05 | REST API would be USD 0.175 — 3.5x |
| Lambda requests | USD 0.20 per million | USD 0.01 | Free tier: 1M requests/month |
| Lambda compute (arm64) | USD 0.0000133334/GB-s | ~USD 0.02 | 256 MB × ~150 ms × 50k. Free tier: 400k GB-s |
| DynamoDB on-demand writes | USD 1.25 per million WRU | < USD 0.02 | |
| DynamoDB on-demand reads | USD 0.25 per million RRU | < USD 0.01 | |
| DynamoDB storage | USD 0.25/GB-month | < USD 0.01 | TTL prunes after 30 days |
| CloudWatch Logs ingest | USD 0.50/GB | ~USD 0.05 | Two log groups, 14-day retention |
| CloudWatch alarms | USD 0.10/alarm-month | USD 0.70 | 7 alarms. Free tier: 10 alarms |
| CloudWatch dashboard | USD 3.00/month above 3 | USD 0.00 | 1 dashboard; first 3 are free |
| X-Ray traces | USD 5.00 per million | < USD 0.01 | Free tier: 100k traces/month |
| SNS email | USD 2.00 per 100k | USD 0.00 | Free tier: 1,000 email notifications |
| AWS Budgets | First 2 budgets free | USD 0.00 | |
| Cost Explorer anomaly detection | Free | USD 0.00 | |
| S3 state bucket | USD 0.023/GB-month | < USD 0.01 | State is kilobytes; versions expire after 90 days |
| **Total** | | **≈ USD 1.00** | **USD 0.00 while free-tier eligible** |

## The four cost controls

Guardrails, in the order they take effect.

### 1. Reserved concurrency (prevention)

`lambda_reserved_concurrency = 10` is the hard ceiling. Even under a sustained
flood, compute cost cannot exceed 10 concurrent executions. Without it, a burst —
or a scraper, or a mistake in a loop — is an unbounded bill.

This is the most important line in the repository from a cost perspective, and
`make test` asserts it is set.

### 2. API Gateway stage throttling (prevention)

`throttling_rate_limit = 10` requests/second steady state, `burst = 20`. Excess
requests get a 429 from the gateway and never reach Lambda, so they cost the
gateway request price and nothing downstream.

### 3. AWS Budgets (detection)

Two notifications on a USD 10 monthly budget:

- **80 percent of actual spend** — you have already spent it.
- **100 percent of forecast** — you are *trending* over. This is the useful one:
  it arrives while there is still time to do something.

### 4. Cost Explorer anomaly detection (detection)

A dimensional monitor on `SERVICE` with a daily subscription above USD 5
absolute impact. It catches the shape of spend changing rather than the total —
useful when one service starts behaving differently while the total is still
under budget. The service is free.

## What would actually cost money

In rough order of likelihood:

1. **CloudFront data transfer.** Someone links the site somewhere popular, or a
   scraper hammers it. 1 TB/month is free, then USD 0.085/GB. The budget alert is
   the backstop.
2. **CloudWatch Logs ingest** if `log_retention_days` were raised or the handler
   started logging per-item at DEBUG. 14 days at INFO keeps this near zero.
3. **DynamoDB storage** if TTL were disabled. Items expire after 30 days by
   default; without that, storage grows forever.
4. **Extra CloudWatch alarms.** The first 10 are free, then USD 0.10 each. Seven
   alarms is deliberately inside that.
5. **PITR on DynamoDB** roughly doubles storage cost. Negligible at kilobytes,
   worth knowing at gigabytes.

## Deliberate cost decisions

| Choice | Cheaper alternative | Why not |
| --- | --- | --- |
| arm64 Lambda | — | arm64 *is* the cheaper option: ~20 percent less per GB-second for identical code |
| HTTP API | Lambda function URL (free) | Function URLs have no throttling and no access logs. Losing the throttle to save USD 0.05 is a bad trade |
| `PriceClass_100` | — | Already the cheapest. US and Europe edges only |
| No WAF | — | USD 5/month per Web ACL before a single request. That is 5x the entire rest of the stack |
| No NAT gateway | — | USD 32/month plus data processing. The function needs no VPC |
| No CloudFront access logs | — | v1 needs S3 ACLs we deliberately disallow; v2 adds recurring ingest cost. See [security.md](security.md) |
| Unencrypted SNS topic | — | A CMK is ~USD 1/month, doubling the bill, to encrypt "an alarm changed state" |
| PITR enabled | Disable it | Costs pennies here and is the difference between an accident and a disaster |

## Checking what you are actually spending

```bash
# Month to date, by service
aws ce get-cost-and-usage \
  --time-period Start="$(date +%Y-%m-01)",End="$(date +%F)" \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# This project only — works because default_tags puts Project on everything
aws ce get-cost-and-usage \
  --time-period Start="$(date +%Y-%m-01)",End="$(date +%F)" \
  --granularity MONTHLY --metrics UnblendedCost \
  --filter '{"Tags":{"Key":"Project","Values":["serverless-portfolio"]}}'
```

The second query only works because `default_tags` applies `Project` to every
taggable resource. Cost allocation tags must also be activated once in the
Billing console before they appear in Cost Explorer.

## Estimating a change before you merge

[Infracost](https://www.infracost.io/) can annotate pull requests with a cost
diff. It is not wired in here because at these numbers the diff is always
"USD 0.00" and the noise would train people to ignore it. It becomes worth adding
the moment anything with a fixed hourly charge enters the stack — an ALB, a NAT
gateway, an RDS instance, a WAF Web ACL.
