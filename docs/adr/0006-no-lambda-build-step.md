# ADR-0006: Single-file handler, no Lambda build step

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

A Lambda function needs a deployment package. The options range from "Terraform
zips a directory" to "a container image built and pushed to ECR by a separate
pipeline". The choice determines whether `terraform apply` alone is enough to
deploy the project.

The handler here needs exactly one dependency, `boto3`, which is already present
in the managed Python runtime.

## Decision

Keep the handler as a single module in `src/api/` with no third-party
dependencies, and package it with the `archive_file` data source at plan time.
There is no build step, no `pip install`, no layer and no container image.

## Options Considered

### Option A: `archive_file` at plan time (chosen)

| Dimension | Assessment |
| --- | --- |
| Complexity | Lowest — one data source |
| Reproducibility | High — the zip is a pure function of the source directory |
| Cost | Zero |
| Dependency ceiling | Only what the managed runtime already provides |

**Pros:** `terraform apply` is the entire deploy; `source_code_hash` gives correct
change detection; nothing to install in CI beyond Terraform itself.
**Cons:** hard ceiling at zero third-party dependencies; the zip is rebuilt on
every plan, so file mtime noise can show as a diff if the archive is not
deterministic.

### Option B: A build step producing a zip with vendored dependencies

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium — a build job, artifact handling, ordering with Terraform |
| Reproducibility | Medium — needs a lockfile and a pinned builder image |
| Cost | Zero |
| Dependency ceiling | High |

**Pros:** any pure-Python dependency becomes available.
**Cons:** the build must run before plan, both locally and in CI, or Terraform
plans against a stale artifact. That ordering constraint is the single most
common way this pattern goes wrong.

### Option C: A container image on ECR

| Dimension | Assessment |
| --- | --- |
| Complexity | High — a registry, a build, a push, lifecycle policies |
| Reproducibility | High |
| Cost | ECR storage, small but non-zero |
| Dependency ceiling | Highest — native extensions, any base image |

**Pros:** up to 10 GB of dependencies; the same image runs locally.
**Cons:** slower cold starts; a registry to secure and prune; considerable extra
Terraform for a handler that imports one library.

## Trade-off Analysis

The dependency ceiling only matters if a dependency is needed. This handler
needs none: `boto3` ships with the runtime, and the rest is standard library.
Accepting the ceiling buys a genuinely single-command deploy, which is worth
more to a portfolio project than headroom that is not currently used.

The honest risk is that the first time a real dependency is needed — an AWS
Lambda Powertools, a validation library — the answer is "restructure the build",
not "add a line to requirements.txt". That is a real cost, and it is why this is
a recorded decision rather than an unexamined default.

## Consequences

- `terraform apply` is the whole deploy path; there is no build artifact to
  coordinate between jobs.
- Adding any third-party dependency requires moving to option B or C first.
- Handler quality is enforced by `ruff` and `mypy` in CI rather than by a build.
- `archive_file` writes into `modules/serverless_api/.build/`, which is
  git-ignored.

## Action Items

1. [x] Lint and type check the handler in CI
2. [x] Ignore build output in `.gitignore`
3. [ ] Move to a layer or an image the first time a real dependency is needed
