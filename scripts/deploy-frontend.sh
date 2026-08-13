#!/usr/bin/env bash
#
# Publish src/frontend to the origin bucket and invalidate the edge cache.
#
# Only needed when Terraform no longer owns the site objects
# (manage_site_content = false). While Terraform owns them, `terraform apply`
# does this and running both will fight over the same keys.

set -euo pipefail

cd "$(dirname "$0")/.."

BUCKET="$(terraform -chdir=terraform output -raw site_bucket_name)"
DISTRIBUTION="$(terraform -chdir=terraform output -raw cloudfront_distribution_id)"

echo "==> Syncing fingerprinted assets (long cache)"
aws s3 sync src/frontend "s3://${BUCKET}" \
  --delete \
  --exclude "*.html" \
  --cache-control "public, max-age=86400"

echo "==> Syncing HTML (always revalidated)"
aws s3 sync src/frontend "s3://${BUCKET}" \
  --exclude "*" \
  --include "*.html" \
  --cache-control "public, max-age=0, must-revalidate" \
  --content-type "text/html"

echo "==> Invalidating ${DISTRIBUTION}"
aws cloudfront create-invalidation \
  --distribution-id "${DISTRIBUTION}" \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text
