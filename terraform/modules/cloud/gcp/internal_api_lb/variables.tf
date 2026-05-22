variable "name" {
  type        = string
  description = "Base name for the internal API load balancer resources."
}

variable "region" {
  type        = string
  description = "GCP region for the internal API load balancer."
}

variable "network_id" {
  type        = string
  description = "VPC network ID."
}

variable "subnetwork_id" {
  type        = string
  description = "Subnetwork ID for the internal forwarding rule IP."
}

variable "backend_group_id" {
  type        = string
  description = "ID of a pre-created unmanaged instance group shared by the k3s server backends."
}

variable "port" {
  type        = number
  description = "TCP port for the Kubernetes API."
  default     = 6443
}

variable "ports" {
  type        = list(number)
  description = "Optional list of TCP ports for the forwarding rule. Defaults to [port]."
  default     = []
}

variable "health_check_port" {
  type        = number
  description = "Optional TCP port used by the health check. Defaults to the first exposed port."
  default     = 0
}

variable "allow_global_access" {
  type        = bool
  description = "Whether the internal forwarding rule allows global access."
  default     = false
}

variable "address" {
  type        = string
  description = "Optional static internal IP address for the forwarding rule."
  default     = ""
}
