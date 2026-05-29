# Low-level DNS records. Hostname ownership is decided in root locals/dns.
resource "cloudflare_record" "this" {
  for_each = {
    for key, record in var.records : key => record if record.enabled
  }

  zone_id         = var.zone_id
  name            = each.value.name
  content         = each.value.content
  type            = each.value.type
  proxied         = each.value.proxied
  ttl             = each.value.ttl
  allow_overwrite = each.value.allow_overwrite
}
