output "dns_name" {
  description = "NLB DNS name."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "NLB canonical hosted zone ID."
  value       = aws_lb.this.zone_id
}

output "arn" {
  description = "NLB ARN."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "NLB ARN suffix used by CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn" {
  description = "NLB target group ARN."
  value       = aws_lb_target_group.this.arn
}

output "target_group_arn_suffix" {
  description = "NLB target group ARN suffix used by CloudWatch metrics."
  value       = aws_lb_target_group.this.arn_suffix
}
