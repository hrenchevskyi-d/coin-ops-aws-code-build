resource "google_compute_region_health_check" "api" {
  name               = "${var.name}-hc"
  region             = var.region
  check_interval_sec = 5
  timeout_sec        = 5

  tcp_health_check {
    port = var.port
  }
}

resource "google_compute_instance_group" "api" {
  name = "${var.name}-${replace(var.backend_zone, "/[^a-z0-9-]/", "-")}"
  zone = var.backend_zone
  instances = [
    for instance in values(var.backend_instances) : instance.self_link
  ]
}

resource "google_compute_region_backend_service" "api" {
  name                  = "${var.name}-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.api.id]
  session_affinity      = "NONE"

  backend {
    group          = google_compute_instance_group.api.id
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
  ports                 = [tostring(var.port)]
  subnetwork            = var.subnetwork_id
  ip_address            = google_compute_address.api.id
  allow_global_access   = var.allow_global_access
  network               = var.network_id
}
