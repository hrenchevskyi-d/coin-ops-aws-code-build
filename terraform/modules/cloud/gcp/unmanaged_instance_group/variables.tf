variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "instances" {
  type = list(string)
}

variable "named_ports" {
  type    = map(number)
  default = {}
}
