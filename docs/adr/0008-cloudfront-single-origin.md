# ADR-0008: CloudFront as the single public origin

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

The browser needs to load static assets and call an API. The usual arrangement is
two public hostnames — a CloudFront domain for the site and an `execute-api`
domain for the API — which immediately requires CORS: a preflight `OPTIONS` on
every non-simple request, an `Access-Control-Allow-Origin` policy to maintain,
and a circular Terraform dependency if the API's allowed origin is the
CloudFront domain that has not been created yet.

## Decision

Give the CloudFront distribution two origins:

- default behavior to the private S3 bucket over Origin Access Control
- `/api/*` behavior to the HTTP API over `https-only`, with the managed
  `CachingDisabled` cache policy and the managed `AllViewerExceptHostHeader`
  origin request policy

The browser only ever talks to one hostname, so every request is same-origin and
no CORS configuration exists anywhere in the stack.

## Options Considered

### Option A: One distribution, two origins (chosen)

| Dimension | Assessment |
| --- | --- |
| Complexity | Low — one extra cache behavior |
| Cost | Zero extra; CloudFront request pricing is the same |
| Security | Strong — one TLS surface, one place for security headers |
| Frontend simplicity | Highest — relative URLs, no base URL configuration |

**Pros:** no CORS anywhere; no circular dependency; security headers apply to API
responses too; the API's origin domain need never be published.
**Cons:** the `AllViewerExceptHostHeader` policy is mandatory and non-obvious —
forwarding CloudFront's `Host` header makes API Gateway reject the request with
a 403 that is hard to diagnose.

### Option B: Separate CloudFront and execute-api domains with CORS

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium — CORS config plus a way to break the dependency cycle |
| Cost | Zero extra |
| Security | Weaker — two public surfaces, and a wildcard origin is the usual shortcut |
| Frontend simplicity | Lower — the API base URL has to be injected at build time |

**Pros:** the API is independently addressable; conventional and familiar.
**Cons:** preflight round trip on every mutating request; the frontend needs the
API URL baked in or fetched at runtime; `allow_origins = ["*"]` is the path of
least resistance and is what most projects end up shipping.

### Option C: A custom domain with Route 53 and ACM for both

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium-high — hosted zone, certificate, validation records |
| Cost | USD 0.50/month for the hosted zone, plus the domain |
| Security | Strong |
| Frontend simplicity | High |

**Pros:** a real hostname, and the certificate work is worth demonstrating.
**Cons:** requires owning a domain, which makes the project impossible to deploy
from a clean fork. That is disqualifying for something meant to be cloned and run.

## Trade-off Analysis

Option A removes an entire category of configuration rather than configuring it
correctly. The circular dependency in option B is the tell that the two-origin
model is fighting the architecture: the API needs to know the CloudFront domain,
which needs the API domain.

Option C is strictly better for a real deployment and is the documented upgrade
path — `viewer_certificate` and an `aliases` block are the only changes needed —
but it cannot be the default when the goal is `git clone && terraform apply`.

## Consequences

- The frontend uses relative URLs and needs no build-time configuration.
- Security headers from the response headers policy apply to API responses as
  well as static assets.
- The `execute-api` endpoint stays reachable directly. It is not a secret and is
  documented as debug-only, but it does mean the API has a second, unheadered
  public surface. Locking it down would need a WAF or an API-Gateway-level
  origin check, both of which are recorded as deferred in `docs/security.md`.
- The API behavior must use `CachingDisabled`. Caching API responses at the edge
  would serve stale data, and it is a two-character mistake to make.

## Action Items

1. [x] Use the managed `AllViewerExceptHostHeader` origin request policy
2. [x] Assert the API behavior uses `CachingDisabled` in a unit test
3. [ ] Add `aliases` plus an ACM certificate when a domain is available
