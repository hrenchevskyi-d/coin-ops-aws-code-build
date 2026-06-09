variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "instance_ids" {
  type        = map(string)
  description = "Map of EC2 instance names to instance IDs monitored by alarms."
}

variable "alert_topic_arn" {
  type        = string
  description = "SNS topic ARN used for alarm and OK actions."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
