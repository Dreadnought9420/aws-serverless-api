# modules/static_site

A private S3 origin behind a CloudFront distribution that also proxies `/api/*`
to an HTTP API, so the browser sees a single origin and no CORS is needed
anywhere ([ADR-0008](../../docs/adr/0008-cloudfront-single-origin.md)).

## Usage

```hcl
module "site" {
  source = "../modules/static_site"

  name_prefix            = "serverless-portfolio-dev"
  bucket_suffix          = data.aws_caller_identity.current.account_id
  content_dir            = "${path.root}/../src/frontend"
  api_origin_domain_name = module.api.api_origin_domain_name

  tags = local.common_tags
}
```

## Design notes

- **OAC, not OAI.** Origin Access Control signs with SigV4 and is the current
  mechanism; Origin Access Identity is legacy.
- **The bucket policy pins `AWS:SourceArn`** to this distribution. Without that
  condition, any CloudFront distribution in any AWS account could read the
  bucket.
- **`BucketOwnerEnforced`** disables ACLs entirely, so no ACL can re-open the
  bucket later.
- **`/api/*` must use `CachingDisabled`.** Caching API responses at the edge
  serves stale data, and it is a two-character mistake to make. A unit test
  asserts it.
- **`/api/*` must use `AllViewerExceptHostHeader`.** Forwarding CloudFront's
  `Host` header to API Gateway produces a 403 whose message does not mention the
  header. This is the most common way the dual-origin pattern fails.
- **Content types come from the file extension.** Anything unmapped is served as
  `application/octet-stream` rather than guessed — an unknown blob served as
  `text/html` is an XSS vector.
- **HTML is served `must-revalidate`**, other assets with a one-day cache. Once
  the build pipeline emits content-hashed filenames, the asset cache can go up.

## Trade-offs accepted here

CloudFront access logging is not enabled — v1 requires S3 ACLs, which conflict
with `BucketOwnerEnforced`, and v2 costs recurring CloudWatch ingest. There is no
WAF. Both are written up in [docs/security.md](../../docs/security.md).

<!-- BEGIN_TF_DOCS -->
<!-- Run `make docs` to populate this section with terraform-docs. -->
<!-- END_TF_DOCS -->
