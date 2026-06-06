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
