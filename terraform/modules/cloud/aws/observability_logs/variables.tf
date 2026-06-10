variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "log_group_name" {
  type        = string
  description = "CloudWatch log group name for Kubernetes container logs."
}

variable "retention_in_days" {
  type        = number
  description = "CloudWatch log retention period in days."
}

variable "log_metric_filters" {
  type        = map(any)
  description = "Log metric filters to create on the Kubernetes container log group."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
