variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "retention_in_days" {
  type        = number
  description = "CloudWatch log retention period in days."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
