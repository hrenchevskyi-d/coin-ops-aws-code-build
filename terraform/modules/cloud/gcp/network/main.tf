# GCP network module optionally provisions Cloud NAT. VM gateway routing is
# handled by nat_route, so the two egress models can be toggled independently.
locals {
  fallback_subnets = {
    internal = { cidr = "10.10.1.0/24" }
    external = { cidr = "10.10.2.0/24" }
  }
  subnets = length(var.subnets) > 0 ? var.subnets : local.fallback_subnets

  # Normalize optional object input so callers can pass {} without Terraform
  # fighting map/object type differences.
  cloud_nat_cfg = jsondecode(
    length(var.cloud_nat) > 0
    ? jsonencode(var.cloud_nat)
    : jsonencode({})
  )
  cloud_nat_enabled     = try(local.cloud_nat_cfg.enabled, false)
  cloud_nat_name        = try(local.cloud_nat_cfg.name, "${var.vpc_name}-nat")
  cloud_nat_router_name = try(local.cloud_nat_cfg.router_name, "${var.vpc_name}-router")
  cloud_nat_subnets     = try(local.cloud_nat_cfg.subnet_names, ["internal"])
  cloud_nat_subnetwork_entries = [
    for subnet_name in local.cloud_nat_subnets : {
      name = google_compute_subnetwork.subnet[subnet_name].id
    }
    if contains(keys(google_compute_subnetwork.subnet), subnet_name)
  ]
}

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  for_each      = local.subnets
  name          = "${each.key}-subnet"
  ip_cidr_range = each.value.cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_router" "nat" {
  count   = local.cloud_nat_enabled ? 1 : 0
  name    = local.cloud_nat_router_name
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  count  = local.cloud_nat_enabled ? 1 : 0
  name   = local.cloud_nat_name
  router = google_compute_router.nat[0].name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = local.cloud_nat_subnetwork_entries
    content {
      name                    = subnetwork.value.name
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }
}
