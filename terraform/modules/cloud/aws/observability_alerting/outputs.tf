output "topic_arn" {
  description = "SNS topic ARN used by observability alarms."
  value       = aws_sns_topic.observability_alerts.arn
}

output "topic_name" {
  description = "SNS topic name used by observability alarms."
  value       = aws_sns_topic.observability_alerts.name
}
