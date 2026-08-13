data "aws_caller_identity" "current" {}

locals {
  topic_name = "${var.name_prefix}-alerts"

  # Every alarm treats missing data as "not breaching". Serverless metrics are
  # sparse by nature: with no traffic there are no data points, and the default
  # of "missing" would leave alarms stuck in INSUFFICIENT_DATA.
  common_alarm = {
    period             = var.alarm_period_seconds
    evaluation_periods = 1
    treat_missing_data = "notBreaching"
  }
}

# ---------------------------------------------------------------------------
# Notification channel
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name              = local.topic_name
  kms_master_key_id = var.sns_kms_key_id

  tags = merge(var.tags, {
    Name = local.topic_name
  })
}

data "aws_iam_policy_document" "alerts" {
  statement {
    sid    = "AllowCloudWatchAlarmsToPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    # Without this, an alarm in any AWS account could publish to this topic.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# Compute alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
  alarm_description   = "The API function returned at least ${var.lambda_error_threshold} error(s) in ${var.alarm_period_seconds}s."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.lambda_error_threshold
  period              = local.common_alarm.period
  evaluation_periods  = local.common_alarm.evaluation_periods
  treat_missing_data  = local.common_alarm.treat_missing_data

  dimensions = {
    FunctionName = var.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.name_prefix}-lambda-throttles"
  alarm_description   = "The API function was throttled, which usually means reserved concurrency is too low."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  period              = local.common_alarm.period
  evaluation_periods  = local.common_alarm.evaluation_periods
  treat_missing_data  = local.common_alarm.treat_missing_data

  dimensions = {
    FunctionName = var.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration_p95" {
  alarm_name          = "${var.name_prefix}-lambda-duration-p95"
  alarm_description   = "p95 function duration exceeded ${var.lambda_duration_threshold_ms}ms."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  extended_statistic  = "p95"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.lambda_duration_threshold_ms
  period              = local.common_alarm.period
  evaluation_periods  = 2
  treat_missing_data  = local.common_alarm.treat_missing_data

  dimensions = {
    FunctionName = var.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Edge and API alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx"
  alarm_description   = "The HTTP API returned server errors."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.api_5xx_threshold
  period              = local.common_alarm.period
  evaluation_periods  = local.common_alarm.evaluation_periods
  treat_missing_data  = local.common_alarm.treat_missing_data

  dimensions = {
    ApiId = var.api_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_rate" {
  provider = aws.us_east_1

  alarm_name          = "${var.name_prefix}-cloudfront-5xx-rate"
  alarm_description   = "More than ${var.cloudfront_5xx_rate_threshold}% of edge requests returned 5xx."
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cloudfront_5xx_rate_threshold
  period              = local.common_alarm.period
  evaluation_periods  = local.common_alarm.evaluation_periods
  treat_missing_data  = local.common_alarm.treat_missing_data

  dimensions = {
    DistributionId = var.distribution_id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Storage alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dynamodb_read_throttle" {
  alarm_name          = "${var.name_prefix}-dynamodb-read-throttle"
  alarm_description   = "DynamoDB throttled read requests on ${var.table_name}."
  namespace           = "AWS/DynamoDB"
  metric_name         = "ReadThrottleEvents"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = local.common_alarm.period
  evaluation_periods  = local.common_alarm.evaluation_periods
  treat_missing_data  = local.common_alarm.treat_missing_data

  dimensions = {
    TableName = var.table_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttle" {
  alarm_name          = "${var.name_prefix}-dynamodb-write-throttle"
  alarm_description   = "DynamoDB throttled write requests on ${var.table_name}."
  namespace           = "AWS/DynamoDB"
  metric_name         = "WriteThrottleEvents"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = local.common_alarm.period
  evaluation_periods  = local.common_alarm.evaluation_periods
  treat_missing_data  = local.common_alarm.treat_missing_data

  dimensions = {
    TableName = var.table_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title  = "API requests and errors"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300

          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id, { label = "Requests" }],
            [".", "4xx", ".", ".", { label = "4xx" }],
            [".", "5xx", ".", ".", { label = "5xx" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          title  = "API latency"
          region = var.aws_region
          view   = "timeSeries"
          period = 300

          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          title  = "Lambda invocations, errors and throttles"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300

          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.function_name, { label = "Invocations" }],
            [".", "Errors", ".", ".", { label = "Errors" }],
            [".", "Throttles", ".", ".", { label = "Throttles" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          title  = "Lambda duration and concurrency"
          region = var.aws_region
          view   = "timeSeries"
          period = 300

          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.function_name, { stat = "p95", label = "Duration p95" }],
            [".", "ConcurrentExecutions", ".", ".", { stat = "Maximum", label = "Concurrency max" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          title  = "DynamoDB consumed capacity"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300

          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.table_name, { label = "Read units" }],
            [".", "ConsumedWriteCapacityUnits", ".", ".", { label = "Write units" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6

        properties = {
          title  = "CloudFront traffic"
          region = "us-east-1"
          view   = "timeSeries"
          period = 300

          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.distribution_id, "Region", "Global", { stat = "Sum", label = "Requests" }],
            [".", "5xxErrorRate", ".", ".", ".", ".", { stat = "Average", label = "5xx rate %" }],
            [".", "CacheHitRate", ".", ".", ".", ".", { stat = "Average", label = "Cache hit %" }],
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6

        properties = {
          title  = "Recent function errors"
          region = var.aws_region
          query  = "SOURCE '${var.log_group_name}' | fields @timestamp, level, message, request_id | filter level = 'ERROR' | sort @timestamp desc | limit 50"
          view   = "table"
        }
      },
    ]
  })
}
