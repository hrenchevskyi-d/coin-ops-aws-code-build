output "parameter_name" {
  description = "SSM parameter name containing the CloudWatch Agent configuration."
  value       = aws_ssm_parameter.cloudwatch_agent_linux.name
}

output "parameter_arn" {
  description = "SSM parameter ARN containing the CloudWatch Agent configuration."
  value       = aws_ssm_parameter.cloudwatch_agent_linux.arn
}
