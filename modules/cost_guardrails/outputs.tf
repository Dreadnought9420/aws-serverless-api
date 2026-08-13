output "budget_name" {
  description = "Name of the monthly cost budget."
  value       = aws_budgets_budget.monthly.name
}

output "budget_limit_usd" {
  description = "Monthly limit the budget alerts against."
  value       = var.monthly_budget_usd
}

output "anomaly_monitor_arn" {
  description = "ARN of the Cost Explorer anomaly monitor, or null when anomaly detection is disabled."
  value       = try(aws_ce_anomaly_monitor.service[0].arn, null)
}
