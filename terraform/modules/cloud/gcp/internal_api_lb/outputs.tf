output "ip_address" {
  value = google_compute_address.api.address
}

output "forwarding_rule" {
  value = google_compute_forwarding_rule.api.name
}
