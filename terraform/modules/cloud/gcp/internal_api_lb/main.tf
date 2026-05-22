locals {
  effective_ports       = length(var.ports) > 0 ? var.ports : [var.port]
  effective_health_port = var.health_check_port > 0 ? var.health_check_port : local.effective_ports[0]
}

resource "google_compute_region_health_check" "api" {
  name               = "${var.name}-hc"
  region             = var.region
  check_interval_sec = 5
  timeout_sec        = 5

  tcp_health_check {
    port = local.effective_health_port
  }
}

resource "google_compute_region_backend_service" "api" {
  name                  = "${var.name}-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.api.id]
  session_affinity      = "NONE"

  backend {
    group          = var.backend_group_id
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_address" "api" {
  name         = "${var.name}-ip"
  region       = var.region
  subnetwork   = var.subnetwork_id
  address_type = "INTERNAL"
  address      = trimspace(var.address) != "" ? var.address : null
}

resource "google_compute_forwarding_rule" "api" {
  name                  = "${var.name}-fr"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.api.id
  ip_protocol           = "TCP"
  ports                 = [for port in local.effective_ports : tostring(port)]
  subnetwork            = var.subnetwork_id
  ip_address            = google_compute_address.api.id
  allow_global_access   = var.allow_global_access
  network               = var.network_id
}
