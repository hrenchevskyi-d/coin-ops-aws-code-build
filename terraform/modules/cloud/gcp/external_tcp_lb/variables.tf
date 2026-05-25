variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "backend_group_id" {
  type = string
}

variable "health_check_port" {
  type    = number
  default = 32443
}

variable "frontend_ports" {
  type    = list(number)
  default = [443]
}
