# Architecture Decision Records

One file per decision, numbered, immutable once accepted. A decision that turns
out badly is superseded by a new record rather than edited — the point of the
log is that a future reader can see what was known at the time.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-serverless-over-containers.md) | Serverless compute over containers | Accepted |
| [0003](0003-github-oidc-over-static-keys.md) | GitHub OIDC federation over static IAM keys | Accepted |
| [0004](0004-s3-native-state-locking.md) | S3 native state locking over a DynamoDB lock table | Accepted |
| [0005](0005-http-api-over-rest-api.md) | API Gateway HTTP API over REST API | Accepted |
| [0006](0006-no-lambda-build-step.md) | Single-file handler, no Lambda build step | Accepted |
| [0007](0007-single-partition-dynamodb-model.md) | Single-partition DynamoDB model | Accepted |
| [0008](0008-cloudfront-single-origin.md) | CloudFront as the single public origin | Accepted |
