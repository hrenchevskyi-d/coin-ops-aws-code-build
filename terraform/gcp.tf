# GCP is the richest path today: it owns optional k3s load balancers, managed DB,
# Secret Manager, and public ingress plumbing when enabled in config.
data "google_secret_manager_secret_version" "db_secrets" {
  count   = local.read_gcp_secret_backend ? 1 : 0
  project = local.gcp_project_id
  secret  = local.db_secret_name
  version = "latest"
}

data "google_secret_manager_secret_version" "app_secrets" {
  count   = local.read_gcp_secret_backend ? 1 : 0
  project = local.gcp_project_id
  secret  = local.app_secret_name
  version = "latest"
}

module "gcp_network" {
  count     = local.gcp_enabled ? 1 : 0
  source    = "./modules/cloud/gcp/network"
  vpc_name  = local.gcp_vpc_name
  region    = local.gcp_region
  subnets   = local.gcp_subnets
  cloud_nat = try(local.gcp_network_cfg.cloud_nat, {})
}

module "gcp_firewall" {
  count          = local.gcp_enabled ? 1 : 0
  source         = "./modules/cloud/gcp/firewall"
  network_id     = module.gcp_network[0].network_id
  firewall_rules = local.firewall_rules
}

module "gcp_instances" {
  count               = local.gcp_compute_enabled ? 1 : 0
  source              = "./modules/cloud/gcp/instances"
  instances           = local.gcp_instances_cfg
  defaults            = local.general
  cloud_defaults      = local.gcp_cfg
  instance_sizes      = local.gcp_instance_sizes
  network_id          = module.gcp_network[0].network_id
  subnet_ids          = module.gcp_network[0].subnet_ids
  ssh_public_key      = local.ssh_public_key
  private_subnet_cidr = local.gcp_private_subnet_cidr
  vpc_cidr            = local.gcp_vpc_cidr
  username            = local.username
  ssh_port            = local.ssh_port
  project_name        = local.project_name

  depends_on = [module.gcp_firewall]
}

module "gcp_nat_route" {
  count       = local.gcp_compute_enabled && local.gcp_has_route_host ? 1 : 0
  source      = "./modules/cloud/gcp/nat_route"
  network_id  = module.gcp_network[0].network_id
  routes      = local.gcp_route_specs
  next_hop_ip = try(module.gcp_instances[0].instance_ips[local.gcp_route_host_name].private_ip, "")

}

module "gcp_database" {
  count        = local.gcp_enabled && local.database_enabled ? 1 : 0
  source       = "./modules/cloud/gcp/database"
  project_name = local.project_name
  region       = local.gcp_region
  network_id   = module.gcp_network[0].network_id
  db_password  = local.effective_db_password
  db_name      = local.db_name
  db_username  = local.db_username
  db_tier      = try(local.gcp_db_profile.tier, "db-f1-micro")
  disk_type    = try(local.gcp_db_profile.disk_type, "PD_HDD")
  disk_size    = try(local.gcp_db_profile.disk_size, 10)
}

# GCP load balancers need a backend instance group; k3s servers are unmanaged
# VMs, so we assemble the group explicitly from Terraform instance details.
module "gcp_k3s_servers_group" {
  count  = (local.gcp_k3s_api_lb_enabled || local.gcp_k3s_ingress_lb_enabled || local.gcp_k3s_public_ingress_lb_enabled) ? 1 : 0
  source = "./modules/cloud/gcp/unmanaged_instance_group"
  name   = "${local.project_name}-k3s-servers-${replace(local.gcp_zone, "/[^a-z0-9-]/", "-")}"
  zone   = local.gcp_zone
  instances = [
    for instance in values(local.gcp_host_details) : instance.self_link
    if instance.role == "k3s-server"
  ]
  named_ports = {}

}

module "gcp_k3s_api_lb" {
  count               = local.gcp_k3s_api_lb_enabled ? 1 : 0
  source              = "./modules/cloud/gcp/internal_api_lb"
  name                = try(local.gcp_k3s_api_lb_cfg.name, "${local.project_name}-k3s-api")
  region              = local.gcp_region
  network_id          = module.gcp_network[0].network_id
  subnetwork_id       = module.gcp_network[0].subnet_ids[try(local.gcp_k3s_api_lb_cfg.internal_subnet, "internal")]
  backend_group_id    = module.gcp_k3s_servers_group[0].id
  port                = try(local.gcp_k3s_api_lb_cfg.port, 6443)
  allow_global_access = try(local.gcp_k3s_api_lb_cfg.allow_global_access, false)
  address             = try(local.gcp_k3s_api_lb_cfg.address, "")
}

module "gcp_k3s_ingress_lb" {
  count               = local.gcp_k3s_ingress_lb_enabled ? 1 : 0
  source              = "./modules/cloud/gcp/internal_api_lb"
  name                = try(local.gcp_k3s_ingress_lb_cfg.name, "${local.project_name}-k3s-ingress")
  region              = local.gcp_region
  network_id          = module.gcp_network[0].network_id
  subnetwork_id       = module.gcp_network[0].subnet_ids[try(local.gcp_k3s_ingress_lb_cfg.internal_subnet, "internal")]
  backend_group_id    = module.gcp_k3s_servers_group[0].id
  port                = try(local.gcp_k3s_ingress_lb_cfg.port, 80)
  ports               = try(local.gcp_k3s_ingress_lb_cfg.ports, [])
  health_check_port   = try(local.gcp_k3s_ingress_lb_cfg.health_check_port, 80)
  allow_global_access = try(local.gcp_k3s_ingress_lb_cfg.allow_global_access, false)
  address             = try(local.gcp_k3s_ingress_lb_cfg.address, "")
}

# Public ingress is intentionally GCP-only right now. Other clouds can still be
# tested through direct IPs or private routing until equivalent modules exist.
module "gcp_k3s_public_ingress_lb" {
  count             = local.gcp_k3s_public_ingress_lb_enabled ? 1 : 0
  source            = "./modules/cloud/gcp/external_tcp_lb"
  name              = try(local.gcp_k3s_public_ingress_lb_cfg.name, "${local.project_name}-k3s-public-ingress")
  region            = local.gcp_region
  backend_group_id  = module.gcp_k3s_servers_group[0].id
  health_check_port = try(local.gcp_k3s_public_ingress_lb_cfg.health_check_port, 32443)
  frontend_ports    = try(local.gcp_k3s_public_ingress_lb_cfg.frontend_ports, [443])
}

module "gcp_secrets" {
  count                      = local.write_gcp_secret_backend ? 1 : 0
  source                     = "./modules/cloud/gcp/secrets"
  db_secret_name             = local.db_secret_name
  app_secret_name            = local.app_secret_name
  db_password                = local.effective_db_password
  rabbitmq_password          = local.effective_rabbitmq_password
  ghcr_token                 = local.effective_ghcr_token
  cloudflare_api_token       = local.effective_cloudflare_api_token
  tailscale_auth_key         = local.effective_tailscale_auth_key
  github_oauth_client_id     = local.effective_github_oauth_client_id
  github_oauth_client_secret = local.effective_github_oauth_client_secret
}
