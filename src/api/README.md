# API source

Single-file Lambda handler, packaged by Terraform's `archive_file` data source
at plan time. There is no build step and no dependency install: `boto3` is part
of the managed Python runtime.

Adding a third-party dependency means switching to a build step (a Lambda layer
or a container image) — see `docs/adr/0006-no-lambda-build-step.md`.

## Local smoke test

```bash
TABLE_NAME=serverless-portfolio-dev-items \
python3 -c "
import handler, json
print(handler.lambda_handler({'requestContext': {'http': {'method': 'GET', 'path': '/health'}}}, None))
"
```

`/health` is the only route that does not touch DynamoDB, so it is the only one
that runs without AWS credentials.
