variable "parameter_name" {
  type        = string
  description = "SSM parameter name for the CloudWatch Agent configuration."
}

variable "config" {
  type        = any
  description = "CloudWatch Agent configuration stored in SSM."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
