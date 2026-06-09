variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "alert_email" {
  type        = string
  description = "Email endpoint subscribed to observability alerts."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
