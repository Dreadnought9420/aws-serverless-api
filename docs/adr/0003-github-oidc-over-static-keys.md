# ADR-0003: GitHub OIDC federation over static IAM keys

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

GitHub Actions needs to run `terraform plan` and `terraform apply` against an
AWS account. Something has to authenticate.

Long-lived IAM access keys stored as repository secrets are still the most
common pattern in public repositories, and they are the single most common
source of leaked AWS credentials: they do not expire, they are copied into local
`.env` files, and a compromised workflow or a malicious dependency exfiltrates a
credential that stays valid until someone notices.

## Decision

Create an IAM OIDC identity provider for `token.actions.githubusercontent.com`
and two IAM roles that GitHub Actions assumes with `sts:AssumeRoleWithWebIdentity`.
No AWS access keys exist anywhere in the repository, in GitHub secrets, or on any
developer machine used for CI.

The two roles have deliberately different blast radii:

| Role | Trust condition on `sub` | Permissions |
| --- | --- | --- |
| `*-gha-plan` | `repo:<owner>/<repo>:pull_request` and `...:ref:refs/heads/main` | `ReadOnlyAccess` plus read/write on the state object |
| `*-gha-apply` | `repo:<owner>/<repo>:environment:production` | `PowerUserAccess`, a scoped IAM slice, and an explicit deny on the CI roles themselves |

Because the apply role only trusts a token whose `sub` names the `production`
environment, and that environment requires a reviewer, the approval gate is
enforced by IAM rather than only by GitHub's UI.

## Options Considered

### Option A: OIDC federation (chosen)

| Dimension | Assessment |
| --- | --- |
| Complexity | Low — one IAM provider, two roles, one action |
| Cost | Zero |
| Blast radius if CI is compromised | Bounded: 1-hour credentials, scoped to one repo and branch/environment |
| Team familiarity | Medium — well documented, occasionally fiddly to get the trust policy right |

**Pros:** no secret to rotate, leak or expire; credentials last one hour; the
trust policy is a reviewable artifact in Terraform.
**Cons:** a wrong `sub` or `aud` condition fails with an opaque `AccessDenied`;
over-broad conditions silently let other repositories in.

### Option B: Long-lived IAM user access keys in GitHub secrets

| Dimension | Assessment |
| --- | --- |
| Complexity | Lowest to set up |
| Cost | Zero |
| Blast radius if CI is compromised | Unbounded until manually revoked |
| Team familiarity | High |

**Pros:** works everywhere, including CI systems without OIDC support.
**Cons:** never expires; rotation is manual and therefore does not happen; a leak
is an account compromise, not an incident.

### Option C: A self-hosted runner on an EC2 instance with an instance profile

| Dimension | Assessment |
| --- | --- |
| Complexity | High — an instance to run, patch and secure |
| Cost | An always-on instance |
| Blast radius | Bounded by the instance profile, but the host itself is a target |
| Team familiarity | Medium |

**Pros:** no federation, no keys, credentials come from the instance metadata service.
**Cons:** an always-on box defeats the point of a serverless project, and a
self-hosted runner on a public repository is a well-known attack path.

## Trade-off Analysis

Option B's only advantage is setup time — perhaps fifteen minutes saved once. The
cost is a permanent credential in a system that is, by design, executing code
from pull requests. Option C reintroduces the always-on cost that ADR-0002
specifically avoided.

The subtle part of option A is the trust policy. `sub` wildcards such as
`repo:*:*` or `repo:<owner>/*:ref:*` are the common failure: they turn a
correctly configured OIDC setup into a role any repository can assume. This
project pins the exact repository plus either a branch or an environment.

## Consequences

- No AWS credential exists that can be leaked from the repository.
- A CI run that needs new permissions requires a Terraform change to the
  bootstrap stack, which is deliberate friction.
- The bootstrap stack itself must be applied once with real credentials by a
  human. That is the one manual step, and it uses local state.
- Debugging a failed assume-role means reading the trust policy, because the API
  error does not say which condition failed.
- Only one OIDC provider for GitHub can exist per AWS account, so
  `create_oidc_provider` has to be settable to false in an account that already
  has one.

## Action Items

1. [x] Pin `aud` to `sts.amazonaws.com` and `sub` to this repository
2. [x] Split plan and apply into separate roles
3. [x] Deny the apply role permission to modify either CI role
4. [ ] Protect the `production` GitHub environment with a required reviewer —
       manual step, see `docs/runbook.md`
