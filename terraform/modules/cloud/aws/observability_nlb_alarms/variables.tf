variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "public_ingress_nlb" {
  type = object({
    load_balancer_arn_suffix = string
    target_group_arn_suffix  = string
    target_count             = number
  })
  description = "Public ingress NLB CloudWatch dimensions and target metadata."
}

variable "alert_topic_arn" {
  type        = string
  description = "SNS topic ARN used for alarm and OK actions."
}

variable "traffic_thresholds" {
  type = object({
    processed_bytes_per_5m = number
    new_flows_per_5m       = number
    active_flows           = number
    client_resets_per_5m   = number
    target_resets_per_5m   = number
    elb_resets_per_5m      = number
  })
  description = "Baseline thresholds for public ingress NLB traffic alarms."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
