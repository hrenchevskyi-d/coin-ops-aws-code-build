output "log_group_name" {
  description = "Kubernetes container CloudWatch log group name."
  value       = aws_cloudwatch_log_group.k3s_container_logs.name
}

output "log_group_arn" {
  description = "Kubernetes container CloudWatch log group ARN."
  value       = aws_cloudwatch_log_group.k3s_container_logs.arn
}

output "metric_definitions" {
  description = "Log-derived custom metric definitions keyed by logical metric filter name."
  value = {
    for key, filter in aws_cloudwatch_log_metric_filter.log_metric_filters : key => {
      metric_name = filter.metric_transformation[0].name
      namespace   = filter.metric_transformation[0].namespace
    }
  }
}
