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

variable "backend_zone" {
  type        = string
  description = "GCP zone shared by the backend instances in the unmanaged instance group."
}

variable "backend_instances" {
  type = map(object({
    self_link  = string
    zone       = string
    private_ip = string
    public_ip  = optional(string)
    role       = string
  }))
  description = "Map of backend instances keyed by instance name. Each value must include self_link and zone."
}

variable "port" {
  type        = number
  description = "TCP port for the Kubernetes API."
  default     = 6443
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
