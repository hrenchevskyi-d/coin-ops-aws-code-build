resource "google_compute_address" "this" {
  name         = "${var.name}-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_region_health_check" "this" {
  name               = "${var.name}-hc"
  region             = var.region
  check_interval_sec = 5
  timeout_sec        = 5

  tcp_health_check {
    port = var.health_check_port
  }
}

resource "google_compute_region_backend_service" "this" {
  name                  = "${var.name}-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.this.id]
  session_affinity      = "NONE"

  backend {
    group          = var.backend_group_id
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "this" {
  for_each = {
    for port in var.frontend_ports : tostring(port) => port
  }

  name                  = "${var.name}-${each.key}-fr"
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  backend_service       = google_compute_region_backend_service.this.id
  ip_protocol           = "TCP"
  port_range            = each.key
  ip_address            = google_compute_address.this.address
}
