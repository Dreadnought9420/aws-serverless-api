## What changed

<!-- One or two sentences. What does this pull request do, and why? -->

## Plan review

- [ ] I read the plan comment on this pull request, not just the diff
- [ ] The plan shows no unexpected `destroy` or `replace`
- [ ] Any resource replacement is intentional and the downtime is acceptable

## Checks

- [ ] `make check` passes locally (`fmt`, `validate`, `lint`, `test`, `scan`)
- [ ] New or changed variables have a `description` and an explicit `type`
- [ ] New or changed outputs have a `description`
- [ ] A new module behaviour is covered by an assertion in `*.tftest.hcl`
- [ ] Provider or Terraform version bumps are in a separate pull request

## Rollback

<!-- How is this undone if it misbehaves? Revert and re-apply, or something else? -->
