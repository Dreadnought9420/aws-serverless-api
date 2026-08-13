# modules/serverless_api

API Gateway HTTP API → Lambda → DynamoDB, with least-privilege IAM, finite log
retention and X-Ray tracing.

## Usage

```hcl
module "api" {
  source = "../modules/serverless_api"

  name_prefix = "serverless-portfolio-dev"
  source_dir  = "${path.root}/../src/api"

  tags = local.common_tags
}
```

## Design notes

- **HTTP API, not REST API** — roughly 70 percent cheaper and lower latency; none
  of the REST-only features are needed
  ([ADR-0005](../../docs/adr/0005-http-api-over-rest-api.md)).
- **`$default` auto-deploying stage** means the invoke URL carries no stage path,
  which is what lets CloudFront use it as an origin without an `origin_path`
  rewrite. It also removes the `aws_api_gateway_deployment` staleness bug class
  entirely.
- **The log group is created explicitly.** If it is not, Lambda creates one
  implicitly on first invocation with never-expire retention, and Terraform then
  fights it on every apply.
- **No `AWSLambdaBasicExecutionRole`.** That managed policy grants `logs:*`
  account-wide. The inline policy scopes log writes to this function's log group
  and DynamoDB to this table.
- **`source_arn` on the Lambda permission** is scoped to this API. Without it,
  any API in the account could invoke the function.
- **Reserved concurrency is the cost blast radius.** Without it, a traffic spike
  is an unbounded bill. A unit test asserts it is set.
- **arm64 by default** — identical code, roughly 20 percent cheaper per
  GB-second.
- **The timeout is validated below 29 seconds**, because API Gateway's
  integration timeout is 30 and a function that outlives it produces a confusing
  504.
- **`archive_file` packages the handler at plan time.** There is no build step,
  which is why the handler has no third-party dependencies
  ([ADR-0006](../../docs/adr/0006-no-lambda-build-step.md)).

## Data model

Single partition, time-ordered sort key
([ADR-0007](../../docs/adr/0007-single-partition-dynamodb-model.md)):

```
pk = "ITEM"
sk = "<zero-padded epoch seconds>~<uuid4>"
```

The sort key is what the API exposes as `id`, so get and delete are one O(1)
request each with no secondary index.

<!-- BEGIN_TF_DOCS -->
<!-- Run `make docs` to populate this section with terraform-docs. -->
<!-- END_TF_DOCS -->
