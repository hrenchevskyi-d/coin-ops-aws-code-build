output "alert_topic_arn" {
  description = "SNS topic ARN used by observability alarms."
  value       = aws_sns_topic.observability_alerts.arn
}

output "alert_topic_name" {
  description = "SNS topic name used by observability alarms."
  value       = aws_sns_topic.observability_alerts.name
}

output "cloudwatch_agent_parameter_name" {
  description = "SSM parameter name containing the CloudWatch Agent configuration."
  value       = aws_ssm_parameter.cloudwatch_agent_linux.name
}

output "cloudwatch_agent_parameter_arn" {
  description = "SSM parameter ARN containing the CloudWatch Agent configuration."
  value       = aws_ssm_parameter.cloudwatch_agent_linux.arn
}
