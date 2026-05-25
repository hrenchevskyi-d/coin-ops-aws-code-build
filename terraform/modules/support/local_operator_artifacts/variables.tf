variable "hosts_filename" {
  type = string
}

variable "hosts_content" {
  type = string
}

variable "ssh_config_filename" {
  type = string
}

variable "ssh_config_content" {
  type = string
}

variable "ansible_runtime_filename" {
  type = string
}

variable "ansible_runtime_content" {
  type = string
}

variable "sync_ssh_config" {
  type    = bool
  default = true
}

variable "ssh_sync_target_path" {
  type = string
}
