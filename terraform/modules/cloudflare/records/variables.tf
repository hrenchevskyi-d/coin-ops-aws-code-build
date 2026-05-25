variable "zone_id" {
  type = string
}

variable "records" {
  type = map(object({
    enabled         = bool
    name            = string
    content         = string
    type            = string
    proxied         = bool
    ttl             = number
    allow_overwrite = bool
  }))
  default = {}
}
