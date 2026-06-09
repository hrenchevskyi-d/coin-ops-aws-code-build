variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "container_log_group_name" {
  type        = string
  description = "CloudWatch log group used by Kubernetes container log metric filters."
}

variable "alert_topic_arn" {
  type        = string
  description = "SNS topic ARN used for alarm and OK actions."
}

variable "container_log_silence_minutes" {
  type        = number
  description = "Minutes without container logs before the silence alarm fires."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
