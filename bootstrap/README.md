# bootstrap

Applied **once per AWS account, by a human, with local state**. It creates the
things CI needs to exist before CI can exist.

## What it creates

- A versioned, encrypted, TLS-only S3 bucket for Terraform state, with
  `prevent_destroy` and a 90-day expiry on non-current versions
- The GitHub Actions OIDC identity provider (`token.actions.githubusercontent.com`)
- `<project>-gha-plan` — `ReadOnlyAccess` plus read/write on the state prefix,
  assumable from pull requests and from `main`
- `<project>-gha-apply` — `PowerUserAccess`, IAM management scoped to
  `<project>-*` roles, explicitly denied permission to modify either CI role,
  assumable only from the `production` GitHub environment

## Why its state is local

The stack that creates the state bucket cannot store its state in that bucket.
Migrating it afterwards is possible and not worth it: this stack is nearly
static, changing only when the repository or the permission model changes, and
keeping it local means there is exactly one manual step in the whole project.

Commit `bootstrap/terraform.tfstate`? No — it is git-ignored. If you lose it, the
resources still exist; re-import them or recreate them with different names.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars    # github_owner, github_repository
../scripts/bootstrap.sh
```

Or manually:

```bash
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output github_actions_variables
```

## Notes

- **Only one GitHub OIDC provider is allowed per AWS account.** If the account
  already has one, set `create_oidc_provider = false`; the roles then reference
  the existing provider by ARN.
- `thumbprint_list` is deliberately omitted. Since mid-2023 AWS validates
  GitHub's OIDC endpoint against its own trust store and ignores any thumbprint
  supplied here. Pinning one only creates a rotation chore that silently breaks
  CI when GitHub rotates its certificate.
- The state bucket carries `prevent_destroy`. `terraform destroy` will fail until
  that lifecycle block is removed deliberately.

<!-- BEGIN_TF_DOCS -->
<!-- Run `make docs` to populate this section with terraform-docs. -->
<!-- END_TF_DOCS -->
