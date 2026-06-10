variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "aws_region" {
  type        = string
  description = "AWS region used by dashboard widgets."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}

variable "alert_email" {
  type        = string
  description = "Email endpoint subscribed to observability alerts. Empty disables the subscription."
  default     = ""
}

variable "cloudwatch_agent_parameter" {
  type        = string
  description = "SSM parameter name for the CloudWatch Agent configuration."
}

variable "cloudwatch_agent_config" {
  type        = any
  description = "CloudWatch Agent configuration stored in SSM."
}

variable "instance_ids" {
  type        = map(string)
  description = "Map of EC2 instance names to instance IDs monitored by alarms and shown on dashboards."
  default     = {}
}

variable "ec2_alarms" {
  type        = map(any)
  description = "EC2 alarm definitions keyed by logical alarm name."
  default     = {}
}

variable "public_ingress_nlb" {
  type = object({
    enabled                  = bool
    load_balancer_arn_suffix = string
    target_group_arn_suffix  = string
    target_count             = number
  })
  description = "Public ingress NLB CloudWatch dimensions and target metadata."
}

variable "nlb_alarms" {
  type        = map(any)
  description = "NLB alarm definitions keyed by logical alarm name."
  default     = {}
}

variable "log_metric_definitions" {
  type = map(object({
    metric_name = string
    namespace   = string
  }))
  description = "Log-derived custom metric definitions keyed by logical metric filter name."
  default     = {}
}

variable "log_metric_alarms" {
  type        = map(any)
  description = "Alarm definitions for log-derived custom metrics."
  default     = {}
}

variable "dashboard_enabled" {
  type        = bool
  description = "Whether to create the CloudWatch observability dashboard."
  default     = true
}
