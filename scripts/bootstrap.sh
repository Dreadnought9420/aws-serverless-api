#!/usr/bin/env bash
#
# One-time setup: create the Terraform state bucket, the GitHub OIDC provider
# and the two CI roles, then print the GitHub configuration to apply.
#
# Run this once per AWS account, with credentials that can create IAM roles.
# Everything after this point runs through CI with no long-lived keys.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f bootstrap/terraform.tfvars ]]; then
  echo "bootstrap/terraform.tfvars is missing." >&2
  echo "Copy bootstrap/terraform.tfvars.example and fill in github_owner and github_repository." >&2
  exit 1
fi

echo "==> Checking AWS credentials"
aws sts get-caller-identity >/dev/null

echo "==> Initialising the bootstrap stack (local state, by design)"
terraform -chdir=bootstrap init -input=false

echo "==> Planning"
terraform -chdir=bootstrap plan -input=false -out=bootstrap.tfplan

cat <<'PROMPT'

Review the plan above. It creates:
  - an S3 bucket for Terraform state (versioned, encrypted, TLS-only)
  - the GitHub Actions OIDC identity provider
  - two IAM roles: read-only for plan, power-user for apply

PROMPT

read -r -p "Apply? [y/N] " answer
[[ "${answer}" == "y" || "${answer}" == "Y" ]] || { echo "Aborted."; exit 1; }

terraform -chdir=bootstrap apply -input=false bootstrap.tfplan

echo
echo "==> Set these as GitHub Actions repository variables"
echo "    (Settings -> Secrets and variables -> Actions -> Variables)"
echo

BUCKET="$(terraform -chdir=bootstrap output -raw state_bucket_name)"
REGION="$(terraform -chdir=bootstrap output -raw state_bucket_region)"
PLAN_ROLE="$(terraform -chdir=bootstrap output -raw plan_role_arn)"
APPLY_ROLE="$(terraform -chdir=bootstrap output -raw apply_role_arn)"
STATE_KEY="$(terraform -chdir=bootstrap output -json github_actions_variables | grep -o '"TF_STATE_KEY":"[^"]*"' | cut -d'"' -f4)"

cat <<VARS
  AWS_REGION         = ${REGION}
  AWS_PLAN_ROLE_ARN  = ${PLAN_ROLE}
  AWS_APPLY_ROLE_ARN = ${APPLY_ROLE}
  TF_STATE_BUCKET    = ${BUCKET}
  TF_STATE_KEY       = ${STATE_KEY}
  ALERT_EMAIL        = <the address you want alarms sent to>
VARS

echo
echo "==> Writing terraform/backend.hcl for local runs"
cat > terraform/backend.hcl <<BACKEND
bucket = "${BUCKET}"
key    = "${STATE_KEY}"
region = "${REGION}"
BACKEND
echo "    terraform/backend.hcl written."

echo
echo "Next:"
echo "  1. Protect the 'production' environment with required reviewers"
echo "     (Settings -> Environments), or the apply role assumes without approval."
echo "  2. cp terraform/terraform.tfvars.example terraform/terraform.tfvars and edit it."
echo "  3. make init && make plan"
