mock_provider "aws" {}

variables {
  name_prefix = "unit-test"
  alert_email = "alerts@example.com"
}

run "budget_alerts_on_actual_and_forecast_spend" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly.time_unit == "MONTHLY"
    error_message = "The budget must reset monthly."
  }

  assert {
    condition     = length(aws_budgets_budget.monthly.notification) == 2
    error_message = "Both an ACTUAL and a FORECASTED notification must be configured; forecast is what gives you time to react."
  }

  assert {
    condition     = tonumber(aws_budgets_budget.monthly.limit_amount) == 10
    error_message = "The default monthly limit must be USD 10."
  }
}

run "anomaly_detection_watches_per_service_spend" {
  command = plan

  assert {
    condition     = aws_ce_anomaly_monitor.service[0].monitor_dimension == "SERVICE"
    error_message = "The anomaly monitor must be dimensional on SERVICE to pinpoint which service moved."
  }

  assert {
    condition     = aws_ce_anomaly_subscription.daily[0].frequency == "DAILY"
    error_message = "Anomaly notifications must arrive daily."
  }
}

run "anomaly_detection_can_be_switched_off" {
  command = plan

  variables {
    enable_anomaly_detection = false
  }

  assert {
    condition     = length(aws_ce_anomaly_monitor.service) == 0
    error_message = "Disabling anomaly detection must create no monitor."
  }
}

run "rejects_an_invalid_email" {
  command = plan

  variables {
    alert_email = "not-an-email"
  }

  expect_failures = [var.alert_email]
}

run "rejects_a_zero_budget" {
  command = plan

  variables {
    monthly_budget_usd = 0
  }

  expect_failures = [var.monthly_budget_usd]
}
