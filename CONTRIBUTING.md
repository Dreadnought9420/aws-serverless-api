# Contributing

## Before you start

```bash
make hooks     # install pre-commit and run it once over the repo
make check     # everything CI runs: fmt, validate, lint, test, scan
```

If `make check` passes locally, CI will pass. If it does not, fix it locally —
CI is not a linter you run remotely.

## Conventions

### Terraform

- **Files**: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. Add
  `locals.tf` or `providers.tf` only when there is enough to justify it.
- **Naming**: descriptive resource names (`aws_s3_bucket.site`, not
  `aws_s3_bucket.main`). Reserve `this` for a genuine singleton.
- **Variables**: always a `description`, always an explicit `type`. Add a
  `validation` block whenever an invalid value would fail at apply time rather
  than plan time — a validation error at plan is worth far more than an API error
  ten minutes into an apply.
- **Outputs**: always a `description`. Expose a stable subset, not whole
  provider objects.
- **Block order**: `count`/`for_each` → arguments → `tags` → `depends_on` →
  `lifecycle`.
- **`for_each` over `count`** for anything that is a collection. `count` is for a
  boolean create/skip toggle only. A list index is not a stable identity:
  removing a middle element renumbers everything after it.
- **`moved` blocks** when renaming a resource. A text rename forces
  destroy-and-recreate; a `moved` block does not.

### Comments

Comment the **why**, not the what. `# Create an S3 bucket` above
`resource "aws_s3_bucket"` is noise. This is not:

```hcl
# The log group must exist first, otherwise Lambda creates it implicitly with
# never-expire retention and Terraform then fights it.
depends_on = [aws_cloudwatch_log_group.lambda]
```

If you find yourself writing a paragraph, it probably belongs in an ADR.

### Python

Modern Python 3.13, full type hints, `ruff` for lint and format, `mypy --strict`.

```bash
make python
```

`src/api/` has **no third-party dependencies** and adding one is a design change
— see [ADR-0006](docs/adr/0006-no-lambda-build-step.md).

### Commits

Conventional commits: `feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, `test:`,
`chore:`, `deps:`.

Keep provider and Terraform version bumps in their own commit and their own pull
request. Mixing an upgrade with a functional change makes a bad plan impossible
to attribute.

## Tests

Every module has `tests/defaults.tftest.hcl` using `mock_provider "aws"`, so the
suite creates nothing and costs nothing.

```bash
make test
```

Add an assertion when you add behaviour that a plan diff would not make obvious.
Good candidates: a security setting that is easy to flip, a value with a
non-obvious required constant, a limit whose absence would be expensive.

Two mechanics worth knowing:

- `command = plan` only sees values known at plan time. Use `command = apply`
  (still against the mock) for computed values such as ARNs.
- Set-type nested blocks cannot be indexed with `[0]`. Use
  `one([for x in <block> : x.attr])`, which works for both lists and sets.

Variable validation is tested with `expect_failures = [var.name]`.

## Adding an ADR

Write a record when a decision is expensive to reverse, looks wrong without its
justification, or was a close call. Copy the structure of an existing record,
take the next number, and add a row to `docs/adr/README.md`.

Records are immutable once accepted. A decision that turns out badly gets a new
record that supersedes the old one — the point of the log is showing what was
known at the time.

## Changing the diagram

`docs/diagrams/architecture.drawio` is the source. Edit it in draw.io desktop or
at [app.diagrams.net](https://app.diagrams.net), then:

```bash
make diagram
```

Keep the official AWS architecture icon set (`mxgraph.aws4.*`) for AWS services
and the GitHub mark for GitHub. Do not substitute generic boxes — the icons are
what make the diagram readable at a glance.

## Pull requests

1. Branch from `main`.
2. `make check`.
3. Open the pull request and fill in the template.
4. **Read the plan comment**, not just the file diff. Look for `destroy` and
   `replace` — a plan diff and a code diff are different things, and the plan is
   the one that tells you what will actually happen.
5. Merge. The apply waits at the `production` approval gate.

### What a reviewer looks for

- Does the plan contain any unexpected `destroy` or `replace`?
- Are new variables typed, described and validated?
- Does a new security-relevant setting have a test asserting it?
- Is an IAM policy scoped to a resource ARN rather than `*`?
- Does a new suppression in `.checkov.yaml` or `.trivyignore` have a matching row
  in `docs/security.md`?
- Is a load-bearing decision recorded in an ADR?

## Things that will get a change rejected

- A long-lived AWS access key anywhere, in any form.
- A wildcard `sub` in an OIDC trust policy.
- `terraform apply -auto-approve` against real infrastructure.
- Re-planning inside the apply job instead of applying the reviewed artifact.
- A scheduled workflow that auto-applies drift.
- An IAM policy with `Resource: "*"` where a specific ARN would work.
- A scanner suppression with no justification in `docs/security.md`.
