output "log_group_name" {
  description = "Kubernetes container CloudWatch log group name."
  value       = aws_cloudwatch_log_group.k3s_container_logs.name
}

output "log_group_arn" {
  description = "Kubernetes container CloudWatch log group ARN."
  value       = aws_cloudwatch_log_group.k3s_container_logs.arn
}
