# ADR-0005: API Gateway HTTP API over REST API

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

API Gateway offers two products with confusingly similar names. REST API (v1) is
the original, feature-rich and expensive. HTTP API (v2) is newer, cheaper and
faster, with a deliberately smaller feature set.

This API is a JSON CRUD surface behind CloudFront, with no API keys, no usage
plans, no request/response transformation and no WAF association of its own.

## Decision

Use HTTP API (`aws_apigatewayv2_*`) with a `$default` auto-deploying stage,
payload format 2.0, and JSON access logging to CloudWatch Logs.

## Options Considered

### Option A: HTTP API (chosen)

| Dimension | Assessment |
| --- | --- |
| Complexity | Low — API, integration, route, stage |
| Cost | USD 1.00 per million requests (first 300M/month) |
| Latency | Lower; roughly 10 ms less overhead per request |
| Team familiarity | Medium |

**Pros:** roughly 70 percent cheaper; fewer resources to declare; `$default`
stage means no separate deployment resource and no stale-deployment bugs;
built-in JWT authorizer if auth is ever needed.
**Cons:** no request validation, no API keys or usage plans, no WAF association,
no X-Ray tracing at the gateway (Lambda tracing still works), no
request/response mapping templates.

### Option B: REST API

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium — plus deployment, method, integration-response resources |
| Cost | USD 3.50 per million requests plus data transfer |
| Latency | Higher |
| Team familiarity | High |

**Pros:** request validation at the edge; API keys and usage plans; WAF can be
attached directly; caching; the `aws_api_gateway_*` resources are what most
tutorials show.
**Cons:** 3.5x the request cost; the `aws_api_gateway_deployment` /
`stage` relationship is a well-known source of "changes not taking effect"
bugs; more resources to review for no benefit here.

### Option C: Lambda function URL

| Dimension | Assessment |
| --- | --- |
| Complexity | Lowest — one resource |
| Cost | Free; no per-request gateway charge at all |
| Latency | Lowest |
| Team familiarity | Medium |

**Pros:** no gateway at all; direct HTTPS endpoint on the function.
**Cons:** no throttling controls, no access logs, no routing, and only one
function per URL. Throttling in particular matters — it is the mechanism that
keeps a traffic spike from becoming a bill.

## Trade-off Analysis

Every REST-only feature is either unnecessary here or provided elsewhere:
request validation is done in the handler, where the error messages are better
anyway; WAF would attach to CloudFront rather than the API; caching is CloudFront's
job. That leaves cost and latency, on both of which HTTP API wins.

Option C is tempting and is the right answer for a webhook receiver, but losing
stage-level throttling and access logs is not worth saving USD 1 per million
requests on an API that will never see a million requests.

## Consequences

- The handler is written against payload format 2.0
  (`event["requestContext"]["http"]["method"]`), which differs from the v1 shape.
  Switching to REST API later means rewriting the routing layer.
- Input validation lives entirely in the handler and is therefore covered by
  handler tests rather than by the gateway.
- If API keys or per-client usage plans are ever needed, this decision has to be
  revisited — HTTP API cannot do it.
- The `$default` stage means the invoke URL carries no stage path, which is what
  lets CloudFront use the API as an origin without an `origin_path` rewrite.

## Action Items

1. [x] Set stage-level throttling as a cost control
2. [x] Enable JSON access logging with integration latency and error fields
3. [ ] Revisit if the API ever needs per-client rate limits
