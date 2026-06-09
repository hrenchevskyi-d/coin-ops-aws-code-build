variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "aws_region" {
  type        = string
  description = "AWS region used by dashboard widgets."
}

variable "instance_ids" {
  type        = map(string)
  description = "Map of EC2 instance names to instance IDs shown on dashboards."
}

variable "public_ingress_nlb" {
  type = object({
    enabled                  = bool
    load_balancer_arn_suffix = string
    target_group_arn_suffix  = string
  })
  description = "Public ingress NLB CloudWatch dimensions for dashboard widgets."
}
