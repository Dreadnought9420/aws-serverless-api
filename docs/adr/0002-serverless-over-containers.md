# ADR-0002: Serverless compute over containers

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

The project needs a compute tier for a small HTTP API behind a static site. The
constraints are unusual for a production system and typical for a portfolio one:

- Traffic is near zero most of the time, with occasional bursts when the link is
  shared. There is no steady baseline to amortise a reserved instance against.
- Idle cost is the dominant cost. A stack that bills while nobody is using it
  will get torn down, and a project that gets torn down cannot be demonstrated.
- It must be reproducible from `terraform apply` with no manual bootstrap.
- Time-to-first-deploy matters more than peak throughput.

## Decision

Use API Gateway HTTP API in front of a Lambda function, backed by DynamoDB
on-demand. No VPC, no NAT gateway, no load balancer, no container registry.

## Options Considered

### Option A: Lambda + API Gateway + DynamoDB (chosen)

| Dimension | Assessment |
| --- | --- |
| Complexity | Low — four resources, no networking |
| Idle cost | ~USD 0. Free tier covers realistic portfolio traffic |
| Scalability | Automatic to the reserved-concurrency ceiling |
| Team familiarity | High |

**Pros:** nothing to patch; scales to zero; cold-start is acceptable for this
workload; the whole stack fits comfortably inside the free tier.
**Cons:** cold starts on the first request after idle; a 6 MB response payload
limit; vendor lock-in at the handler signature; local development needs an
emulator or a deployed stack.

### Option B: ECS Fargate + ALB + RDS

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium-high — VPC, subnets, NAT, target groups, task definitions |
| Idle cost | ~USD 40-60/month. ALB alone is ~USD 16/month before traffic |
| Scalability | Good, but scaling is slower and never reaches zero |
| Team familiarity | High |

**Pros:** portable container image; no cold starts; no runtime limits; a more
conventional shape for a real production service.
**Cons:** the ALB and NAT gateway bill continuously whether or not anyone visits;
significantly more Terraform to review; patching becomes the owner's problem.

### Option C: EKS

| Dimension | Assessment |
| --- | --- |
| Complexity | High |
| Idle cost | USD 73/month for the control plane alone, before any node |
| Scalability | Excellent |
| Team familiarity | Medium |

**Pros:** demonstrates Kubernetes competence; the most transferable to large
organisations.
**Cons:** the control-plane charge is unavoidable and permanent; the interesting
parts of the project would be drowned by cluster plumbing.

## Trade-off Analysis

The deciding factor is idle cost, because it determines whether the stack stays
deployed. Option B costs roughly USD 500 a year to keep a demo online; option C
roughly USD 1,000. Option A costs approximately nothing at this traffic level and
still exercises IAM, edge caching, observability and CI/CD — which is what the
project is meant to demonstrate.

Cold starts are the real cost of the choice: a Python 3.13 arm64 function at
256 MB with no dependencies beyond boto3 initialises in roughly 200-400 ms. For a
demo API that is invisible next to the CloudFront round trip. It would not be
acceptable for a latency-sensitive production API, and that is the boundary at
which this decision should be revisited.

## Consequences

- No VPC means no NAT gateway, which removes both the largest recurring cost and
  a common source of misconfiguration.
- Nothing to patch: no AMIs, no base images, no CVE triage on a container.
- The handler is coupled to the API Gateway payload format 2.0 event shape.
  Moving to containers later means rewriting the entry point, though the
  business logic is already isolated from it.
- Reserved concurrency becomes the primary cost control and must be set
  deliberately; without it a traffic spike is an unbounded bill.
- Local development is awkward. Only `/api/health` runs without AWS credentials.

## Action Items

1. [x] Set reserved concurrency on the function
2. [x] Cap the Lambda timeout below the API Gateway integration limit
3. [ ] Revisit if p99 latency requirements ever drop below ~200 ms
