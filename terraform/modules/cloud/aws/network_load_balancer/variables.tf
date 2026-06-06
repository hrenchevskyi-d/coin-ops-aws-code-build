variable "name" {
  type        = string
  description = "Base name for the Network Load Balancer resources."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the target group."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs where the NLB is attached."
}

variable "internal" {
  type        = bool
  description = "Whether the NLB is internal."
  default     = false
}

variable "target_instance_ids" {
  type        = map(string)
  description = "Map of stable target names to EC2 instance IDs registered as NLB targets."
}

variable "target_security_group_id" {
  type        = string
  description = "Security group ID attached to the target instances."
  default     = ""
}

variable "allowed_target_cidrs" {
  type        = list(string)
  description = "CIDR ranges allowed to reach the target port through the NLB."
  default     = []
}

variable "port" {
  type        = number
  description = "Target and listener TCP port."
}

variable "health_check_port" {
  type        = number
  description = "TCP health check port. Defaults to port when set to 0."
  default     = 0
}

variable "enable_target_security_group_rule" {
  type        = bool
  description = "Whether to create an ingress rule on target_security_group_id."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
