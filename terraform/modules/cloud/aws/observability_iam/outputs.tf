output "role_name" {
  description = "EC2 observability IAM role name."
  value       = aws_iam_role.ec2_observability.name
}

output "role_arn" {
  description = "EC2 observability IAM role ARN."
  value       = aws_iam_role.ec2_observability.arn
}

output "instance_profile_name" {
  description = "EC2 observability IAM instance profile name."
  value       = aws_iam_instance_profile.ec2_observability.name
}

output "instance_profile_arn" {
  description = "EC2 observability IAM instance profile ARN."
  value       = aws_iam_instance_profile.ec2_observability.arn
}
