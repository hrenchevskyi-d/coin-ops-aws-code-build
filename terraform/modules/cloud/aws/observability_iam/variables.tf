variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "policy_arns" {
  type        = set(string)
  description = "Managed IAM policy ARNs attached to the EC2 observability role."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
