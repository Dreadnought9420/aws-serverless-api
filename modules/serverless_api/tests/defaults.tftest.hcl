# Unit tests for the serverless_api module.
#
# The aws provider is mocked; the archive provider is not, because zipping the
# handler is a local operation and asserting it produces a package is part of
# what these tests are for. Run from this module's directory:
#
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "unit-test"
  source_dir  = "../../src/api"
}

run "function_runs_on_a_current_supported_runtime" {
  command = plan

  assert {
    condition     = aws_lambda_function.api.runtime == "python3.13"
    error_message = "The function must target a supported Python runtime."
  }

  assert {
    condition     = aws_lambda_function.api.architectures[0] == "arm64"
    error_message = "Default to Graviton: same code, roughly 20 percent cheaper per GB-second."
  }

  assert {
    condition     = aws_lambda_function.api.handler == "handler.lambda_handler"
    error_message = "Handler entry point must match the packaged module."
  }
}

run "function_has_a_cost_blast_radius_limit" {
  command = plan

  assert {
    condition     = aws_lambda_function.api.reserved_concurrent_executions > 0
    error_message = "Reserved concurrency must be set; without it a traffic spike is an unbounded bill."
  }

  assert {
    condition     = aws_lambda_function.api.timeout < 30
    error_message = "The function timeout must stay under the API Gateway integration limit of 30s."
  }
}

run "function_is_traced_and_its_logs_expire" {
  command = plan

  assert {
    condition     = one([for t in aws_lambda_function.api.tracing_config : t.mode]) == "Active"
    error_message = "X-Ray tracing must be active."
  }

  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 14
    error_message = "Log retention must be finite; never-expire logs accumulate cost forever."
  }

  assert {
    condition     = aws_cloudwatch_log_group.lambda.name == "/aws/lambda/unit-test-api"
    error_message = "The log group name must match the convention Lambda would create implicitly."
  }
}

run "table_is_serverless_encrypted_and_self_pruning" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.items.billing_mode == "PAY_PER_REQUEST"
    error_message = "The table must be on-demand; provisioned capacity bills whether or not it is used."
  }

  assert {
    condition     = one([for t in aws_dynamodb_table.items.ttl : t.enabled])
    error_message = "TTL must be enabled so demo data does not accumulate indefinitely."
  }

  assert {
    condition     = one([for p in aws_dynamodb_table.items.point_in_time_recovery : p.enabled])
    error_message = "Point-in-time recovery must be enabled by default."
  }
}

run "api_is_http_not_rest" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "The API must be an HTTP API (see ADR 0005)."
  }

  assert {
    condition     = aws_apigatewayv2_integration.lambda.payload_format_version == "2.0"
    error_message = "HTTP API integrations must use payload format 2.0, which the handler is written against."
  }

  assert {
    condition     = one([for s in aws_apigatewayv2_stage.default.default_route_settings : s.throttling_rate_limit]) > 0
    error_message = "The stage must be throttled."
  }

  # Assert the block exists rather than the ARN inside it: destination_arn is
  # computed, so at plan time it is unknown and a condition that depends on an
  # unknown value cannot be evaluated.
  assert {
    condition     = length(aws_apigatewayv2_stage.default.access_log_settings) == 1
    error_message = "Access logging must be configured on the stage."
  }
}

run "handler_package_is_built" {
  command = plan

  assert {
    condition     = data.archive_file.lambda.output_base64sha256 != ""
    error_message = "The deployment package must be produced at plan time; there is no separate build step."
  }
}

run "rejects_a_timeout_above_the_api_gateway_limit" {
  command = plan

  variables {
    lambda_timeout_seconds = 60
  }

  expect_failures = [var.lambda_timeout_seconds]
}

run "rejects_an_unsupported_architecture" {
  command = plan

  variables {
    lambda_architecture = "riscv"
  }

  expect_failures = [var.lambda_architecture]
}

run "rejects_a_retention_period_cloudwatch_does_not_accept" {
  command = plan

  variables {
    log_retention_days = 13
  }

  expect_failures = [var.log_retention_days]
}
