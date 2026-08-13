# Unit tests for the observability module.
#
# Two mocked providers are needed because the module declares an aws.us_east_1
# configuration alias for the CloudFront alarm.

mock_provider "aws" {}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  name_prefix     = "unit-test"
  aws_region      = "eu-west-1"
  alert_email     = "alerts@example.com"
  function_name   = "unit-test-api"
  log_group_name  = "/aws/lambda/unit-test-api"
  api_id          = "abc123"
  table_name      = "unit-test-items"
  distribution_id = "E1EXAMPLE"
}

run "alarms_treat_no_traffic_as_healthy" {
  command = plan

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.lambda_errors.treat_missing_data == "notBreaching",
      aws_cloudwatch_metric_alarm.api_5xx.treat_missing_data == "notBreaching",
      aws_cloudwatch_metric_alarm.cloudfront_5xx_rate.treat_missing_data == "notBreaching",
    ])
    error_message = "Serverless metrics are sparse. Alarms must treat missing data as not breaching or they sit in INSUFFICIENT_DATA."
  }
}

run "every_alarm_notifies_the_topic" {
  command = plan

  assert {
    condition = alltrue([
      contains(aws_cloudwatch_metric_alarm.lambda_errors.alarm_actions, aws_sns_topic.alerts.arn),
      contains(aws_cloudwatch_metric_alarm.lambda_throttles.alarm_actions, aws_sns_topic.alerts.arn),
      contains(aws_cloudwatch_metric_alarm.lambda_duration_p95.alarm_actions, aws_sns_topic.alerts.arn),
      contains(aws_cloudwatch_metric_alarm.api_5xx.alarm_actions, aws_sns_topic.alerts.arn),
      contains(aws_cloudwatch_metric_alarm.cloudfront_5xx_rate.alarm_actions, aws_sns_topic.alerts.arn),
      contains(aws_cloudwatch_metric_alarm.dynamodb_read_throttle.alarm_actions, aws_sns_topic.alerts.arn),
      contains(aws_cloudwatch_metric_alarm.dynamodb_write_throttle.alarm_actions, aws_sns_topic.alerts.arn),
    ])
    error_message = "An alarm with no action is decoration. Every alarm must publish to the SNS topic."
  }
}

run "cloudfront_alarm_targets_the_global_metric" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.cloudfront_5xx_rate.dimensions["Region"] == "Global"
    error_message = "CloudFront metrics are published under Region=Global; any other value matches nothing."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cloudfront_5xx_rate.namespace == "AWS/CloudFront"
    error_message = "The CloudFront alarm must read the AWS/CloudFront namespace."
  }
}

run "dashboard_is_valid_json_with_every_widget" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.main.dashboard_body).widgets) == 7
    error_message = "The dashboard must render all seven widgets."
  }
}

run "rejects_an_invalid_email" {
  command = plan

  variables {
    alert_email = "nope"
  }

  expect_failures = [var.alert_email]
}
