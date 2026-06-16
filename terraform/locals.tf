locals {
  # Split JSON keeps deployment settings reviewable without touching Terraform logic.
  # Later files win on duplicate keys, so keep shared defaults in earlier files
  # and environment-specific deploy decisions in deploy.json/instances.json.
  cfg = merge(
    try(jsondecode(file("${path.module}/config/clouds.json")), {}),
    try(jsondecode(file("${path.module}/config/general.json")), {}),
    try(jsondecode(file("${path.module}/config/deploy.json")), {}),
    try(jsondecode(file("${path.module}/config/database.json")), {}),
    try(jsondecode(file("${path.module}/config/observability.json")), {}),
    try(jsondecode(file("${path.module}/config/dns.json")), {}),
    try(jsondecode(file("${path.module}/config/secrets.json")), {}),
    try(jsondecode(file("${path.module}/config/instances.json")), {})
  )
  mapping  = try(jsondecode(file("${path.module}/config/cloud_mappings.json")), {})
  networks = try(jsondecode(file("${path.module}/config/networks.json")), {})

  clouds          = lookup(local.cfg, "clouds", {})
  cloud_providers = lookup(local.clouds, "providers", {})
  gcp_provider    = lookup(local.cloud_providers, "gcp", {})
  aws_provider    = lookup(local.cloud_providers, "aws", {})
  azure_provider  = lookup(local.cloud_providers, "azure", {})
  gcp_account     = lookup(local.gcp_provider, "account", {})
  aws_account     = lookup(local.aws_provider, "account", {})
  azure_account   = lookup(local.azure_provider, "account", {})
  deploy          = lookup(local.cfg, "deploy", {})
  database        = lookup(local.cfg, "database", {})
  observability   = lookup(local.cfg, "observability", {})
  dns             = lookup(local.cfg, "dns", {})
  general         = lookup(local.cfg, "general", {})
  secrets         = lookup(local.cfg, "secrets", {})

  enabled_clouds          = toset(try(local.clouds.enabled, ["gcp"]))
  control_plane_cloud     = try(local.clouds.control_plane, "gcp")
  secret_backend          = try(local.clouds.secret_backend, local.control_plane_cloud)
  default_instance_clouds = try(tolist(local.clouds.default_instance_clouds), tolist(local.enabled_clouds))

  instances = lookup(local.cfg, "instances", {})
  kubernetes_cfg = merge({
    runtime = "k3s"
  }, try(local.deploy.kubernetes, {}))
  kubernetes_runtime = lower(try(local.kubernetes_cfg.runtime, "k3s"))
  aws_eks_cfg = merge({
    enabled             = false
    cluster_name        = "${try(local.general.project_name, "coin-ops")}-eks"
    version             = "1.33"
    private_subnets     = []
    public_subnets      = []
    service_ipv4_cidr   = "10.43.0.0/16"
    endpoint_public     = true
    endpoint_private    = true
    public_access_cidrs = ["0.0.0.0/0"]
    node_group = {
      name           = "system"
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 3
      disk_size      = 30
    }
    addons = {}
  }, try(local.deploy.eks, {}))
  # Each instance can opt into a subset of clouds; missing clouds means "use the
  # repo default cloud set" so old configs do not need per-host cloud lists.
  instance_clouds = {
    for name, cfg in local.instances : name => toset(try(tolist(lookup(cfg, "clouds", local.default_instance_clouds)), local.default_instance_clouds))
  }
  gcp_instances_base = {
    for name, cfg in local.instances : name => cfg
    if contains(local.instance_clouds[name], "gcp")
  }
  aws_instances_base = {
    for name, cfg in local.instances : name => cfg
    if contains(local.instance_clouds[name], "aws")
    && (local.aws_k3s_enabled || lookup(cfg, "role", "") != "k3s-server")
  }
  azure_instances_base = {
    for name, cfg in local.instances : name => cfg
    if contains(local.instance_clouds[name], "azure")
  }

  gcp_enabled           = contains(local.enabled_clouds, "gcp")
  aws_enabled           = contains(local.enabled_clouds, "aws")
  azure_enabled         = contains(local.enabled_clouds, "azure")
  aws_eks_enabled       = local.aws_enabled && local.kubernetes_runtime == "eks" && try(local.aws_eks_cfg.enabled, false)
  aws_k3s_enabled       = local.aws_enabled && !local.aws_eks_enabled
  gcp_compute_enabled   = local.gcp_enabled && length(local.gcp_instances_base) > 0
  aws_compute_enabled   = local.aws_enabled && length(local.aws_instances_base) > 0
  azure_compute_enabled = local.azure_enabled && length(local.azure_instances_base) > 0

  cloud_networks = lookup(local.networks, "cloud_networks", {})
  routing        = lookup(local.networks, "routing", {})
  security       = lookup(local.networks, "security", {})
  firewall_rules = lookup(local.networks, "firewall_rules", {})
  default_network_cfg = {
    vpc_name = "coin-ops-vpc"
    vpc_cidr = "10.10.0.0/16"
    subnets = {
      internal = { cidr = "10.10.1.0/24" }
      database = { cidr = "10.10.3.0/24" }
      external = { cidr = "10.10.2.0/24", public = true }
    }
    remote_routes = []
  }
  gcp_network_cfg_raw   = merge(local.default_network_cfg, lookup(local.cloud_networks, "gcp", {}))
  aws_network_cfg_raw   = merge(local.default_network_cfg, lookup(local.cloud_networks, "aws", {}))
  azure_network_cfg_raw = merge(local.default_network_cfg, lookup(local.cloud_networks, "azure", {}))
  # If remote_routes is omitted, derive cross-cloud routes from enabled clouds.
  # Explicit remote_routes overrides the generated mesh.
  gcp_network_cfg = merge(local.gcp_network_cfg_raw, {
    remote_routes = length(try(local.gcp_network_cfg_raw.remote_routes, [])) > 0 ? local.gcp_network_cfg_raw.remote_routes : [
      for remote_cloud, remote_cfg in {
        aws   = local.aws_network_cfg_raw
        azure = local.azure_network_cfg_raw
        } : {
        name             = "coin-ops-gcp-to-${remote_cloud}"
        destination_cidr = remote_cfg.vpc_cidr
      } if contains(local.enabled_clouds, remote_cloud)
    ]
  })
  aws_network_cfg = merge(local.aws_network_cfg_raw, {
    remote_routes = length(try(local.aws_network_cfg_raw.remote_routes, [])) > 0 ? local.aws_network_cfg_raw.remote_routes : [
      for remote_cloud, remote_cfg in {
        gcp   = local.gcp_network_cfg_raw
        azure = local.azure_network_cfg_raw
        } : {
        name             = "coin-ops-aws-to-${remote_cloud}"
        destination_cidr = remote_cfg.vpc_cidr
      } if contains(local.enabled_clouds, remote_cloud)
    ]
  })
  azure_network_cfg = merge(local.azure_network_cfg_raw, {
    remote_routes = length(try(local.azure_network_cfg_raw.remote_routes, [])) > 0 ? local.azure_network_cfg_raw.remote_routes : [
      for remote_cloud, remote_cfg in {
        gcp = local.gcp_network_cfg_raw
        aws = local.aws_network_cfg_raw
        } : {
        name             = "coin-ops-azure-to-${remote_cloud}"
        destination_cidr = remote_cfg.vpc_cidr
      } if contains(local.enabled_clouds, remote_cloud)
    ]
  })
  private_default_route     = lookup(local.routing, "private_default_route", {})
  remote_target_tags        = try(local.routing.remote_target_tags, ["internal-vm", "app-ui", "app-backend"])
  egress_cidrs              = lookup(local.security, "egress_cidrs", ["0.0.0.0/0"])
  gcp_vpc_name              = try(local.gcp_network_cfg.vpc_name, "coin-ops-gcp-vpc")
  gcp_vpc_cidr              = try(local.gcp_network_cfg.vpc_cidr, "10.20.0.0/16")
  gcp_subnets               = try(local.gcp_network_cfg.subnets, local.default_network_cfg.subnets)
  gcp_private_subnet_cidr   = try(local.gcp_subnets["internal"].cidr, "10.20.1.0/24")
  aws_vpc_name              = try(local.aws_network_cfg.vpc_name, "coin-ops-aws-vpc")
  aws_vpc_cidr              = try(local.aws_network_cfg.vpc_cidr, "10.30.0.0/16")
  aws_subnets               = try(local.aws_network_cfg.subnets, local.default_network_cfg.subnets)
  aws_private_subnet_cidr   = try(local.aws_subnets["internal"].cidr, "10.30.1.0/24")
  azure_vpc_name            = try(local.azure_network_cfg.vpc_name, "coin-ops-azure-vpc")
  azure_vpc_cidr            = try(local.azure_network_cfg.vpc_cidr, "10.40.0.0/16")
  azure_subnets             = try(local.azure_network_cfg.subnets, local.default_network_cfg.subnets)
  azure_private_subnet_cidr = try(local.azure_subnets["internal"].cidr, "10.40.1.0/24")

  gcp_instance_sizes = try(local.mapping.instance_sizes.gcp, {})
  aws_instance_sizes = try(local.mapping.instance_sizes.aws, {})
  azure_instance_sizes = merge(
    try(local.mapping.instance_sizes.azure, {}),
    try(local.general.azure_instance_sizes, {})
  )
  gcp_regions   = try(local.mapping.regions.gcp, {})
  aws_regions   = try(local.mapping.regions.aws, {})
  azure_regions = try(local.mapping.regions.azure, {})
  aws_zone_map  = try(local.aws_regions[local.region_profile].zones, {})
  gcp_images    = try(local.mapping.images.gcp, {})
  aws_images    = try(local.mapping.images.aws, {})
  azure_images  = try(local.mapping.images.azure, {})

  ssh_public_key = fileexists(pathexpand(var.ssh_public_key_path)) ? file(pathexpand(var.ssh_public_key_path)) : ""

  database_enabled = try(local.database.enabled, true)
  secrets_enabled  = try(local.secrets.enabled, true)
  secret_names     = try(local.secrets.names, {})
  db_secret_name   = try(local.secret_names.db, "coinops-db-secrets")
  app_secret_name  = try(local.secret_names.app, "coinops-app-secrets")

  cnpg_backup_cfg = merge({
    enabled        = true
    provider       = ""
    bucket_name    = ""
    path           = "coinops-postgres"
    retention_days = 30
    schedule       = "0 0 2 * * *"
  }, try(local.deploy.cnpg_backup, {}))
  cnpg_backup_provider = (
    trimspace(try(local.cnpg_backup_cfg.provider, "")) != ""
    ? lower(trimspace(local.cnpg_backup_cfg.provider))
    : (local.secret_backend == "aws" ? "s3" : "gcs")
  )
  gcp_cnpg_backup_enabled = (
    local.gcp_enabled
    && local.secrets_enabled
    && local.secret_backend == "gcp"
    && local.cnpg_backup_provider == "gcs"
    && try(local.cnpg_backup_cfg.enabled, true)
  )
  aws_cnpg_backup_enabled = (
    local.aws_enabled
    && local.secrets_enabled
    && local.secret_backend == "aws"
    && local.cnpg_backup_provider == "s3"
    && try(local.cnpg_backup_cfg.enabled, true)
  )
  cnpg_backup_enabled = local.gcp_cnpg_backup_enabled

  cnpg_backup_path      = trim(try(local.cnpg_backup_cfg.path, "coinops-postgres"), "/")
  cnpg_backup_schedule  = try(local.cnpg_backup_cfg.schedule, "0 0 2 * * *")
  cnpg_backup_retention = "${try(local.cnpg_backup_cfg.retention_days, 30)}d"
  gcp_cnpg_backup_bucket_name = (
    try(local.cnpg_backup_cfg.bucket_name, "") != ""
    ? local.cnpg_backup_cfg.bucket_name
    : lower("${local.project_name}-${substr(md5(local.gcp_project_id), 0, 8)}-cnpg-backups")
  )
  aws_cnpg_backup_bucket_name = (
    try(local.cnpg_backup_cfg.bucket_name, "") != ""
    ? local.cnpg_backup_cfg.bucket_name
    : lower("${replace(local.project_name, "_", "-")}-${substr(md5(coalesce(local.aws_account_id, local.aws_region)), 0, 8)}-cnpg-backups")
  )
  cnpg_backup_bucket_name     = local.gcp_cnpg_backup_bucket_name
  cnpg_backup_destination     = "gs://${local.gcp_cnpg_backup_bucket_name}/${local.cnpg_backup_path}"
  aws_cnpg_backup_destination = "s3://${local.aws_cnpg_backup_bucket_name}/${local.cnpg_backup_path}"

  db_name          = try(local.database.name, "cognitor")
  db_username      = try(local.database.username, "cognitor")
  db_port          = try(local.database.port, 5432)
  gcp_db_profile   = try(local.database.cloud_profiles.gcp, {})
  aws_db_profile   = try(local.database.cloud_profiles.aws, {})
  azure_db_profile = try(local.database.cloud_profiles.azure, {})

  seed_secret_manager = local.secrets_enabled && var.seed_secret_manager
  # Reads are disabled while seeding because the secret may not exist yet.
  # suppress_secret_manager_reads keeps plan/refresh usable during repair work.
  read_gcp_secret_backend    = local.secrets_enabled && local.secret_backend == "gcp" && !local.seed_secret_manager && !var.suppress_secret_manager_reads
  read_aws_secret_backend    = local.secrets_enabled && local.secret_backend == "aws" && !local.seed_secret_manager && !var.suppress_secret_manager_reads
  read_azure_secret_backend  = local.secrets_enabled && local.secret_backend == "azure" && !local.seed_secret_manager && !var.suppress_secret_manager_reads
  write_gcp_secret_backend   = local.secrets_enabled && local.gcp_enabled
  write_aws_secret_backend   = local.secrets_enabled && local.aws_enabled
  write_azure_secret_backend = local.secrets_enabled && local.azure_enabled

  gcp_hosts        = local.gcp_compute_enabled ? try(module.gcp_instances[0].instance_ips, {}) : {}
  gcp_host_details = local.gcp_compute_enabled ? try(module.gcp_instances[0].instance_details, {}) : {}
  aws_hosts        = local.aws_compute_enabled ? try(module.aws_instances[0].instance_ips, {}) : {}
  azure_hosts      = local.azure_compute_enabled ? try(module.azure_instances[0].instance_ips, {}) : {}

  gcp_k3s_server_names = local.gcp_compute_enabled ? [
    for name, cfg in local.gcp_instances_base : name
    if lookup(cfg, "role", "") == "k3s-server"
  ] : []
  gcp_k3s_api_lb_cfg = merge(
    {
      enabled             = false
      name                = "${local.project_name}-k3s-api"
      port                = 6443
      internal_subnet     = "internal"
      allow_global_access = false
      address             = ""
    },
    try(local.gcp_network_cfg.k3s_api_load_balancer, {})
  )
  gcp_k3s_api_lb_enabled = (
    local.gcp_compute_enabled
    && try(local.gcp_k3s_api_lb_cfg.enabled, false)
    && length(local.gcp_k3s_server_names) > 0
  )
  # Without the internal API LB, Ansible uses a direct server endpoint and SSH tunnel.
  gcp_k3s_api_lb_backends = local.gcp_k3s_api_lb_enabled ? {
    for name in local.gcp_k3s_server_names : name => local.gcp_host_details[name]
  } : {}
  gcp_k3s_ingress_lb_cfg = merge(
    {
      enabled             = false
      name                = "${local.project_name}-k3s-ingress"
      port                = 80
      internal_subnet     = "internal"
      allow_global_access = false
      address             = ""
    },
    try(local.gcp_network_cfg.k3s_ingress_load_balancer, {})
  )
  gcp_k3s_ingress_lb_enabled = (
    local.gcp_compute_enabled
    && try(local.gcp_k3s_ingress_lb_cfg.enabled, false)
    && length(local.gcp_k3s_server_names) > 0
  )
  gcp_k3s_ingress_lb_backends = local.gcp_k3s_ingress_lb_enabled ? {
    for name in local.gcp_k3s_server_names : name => local.gcp_host_details[name]
  } : {}
  gcp_k3s_public_ingress_lb_cfg = merge(
    {
      enabled           = false
      name              = "${local.project_name}-k3s-public-ingress"
      health_check_port = 443
      frontend_ports    = [443]
    },
    try(local.gcp_network_cfg.k3s_public_ingress_load_balancer, {})
  )
  gcp_k3s_public_ingress_lb_enabled = (
    local.gcp_compute_enabled
    && try(local.gcp_k3s_public_ingress_lb_cfg.enabled, false)
    && length(local.gcp_k3s_server_names) > 0
  )

  aws_k3s_server_names = local.aws_compute_enabled ? [
    for name, cfg in local.aws_instances_base : name
    if lookup(cfg, "role", "") == "k3s-server"
  ] : []
  aws_k3s_api_lb_cfg = merge(
    {
      enabled           = false
      name              = "${local.project_name}-k3s-api"
      port              = 6443
      internal_subnets  = ["internal"]
      health_check_port = 6443
    },
    try(local.aws_network_cfg.k3s_api_load_balancer, {})
  )
  aws_k3s_api_lb_enabled = (
    local.aws_k3s_enabled
    && local.aws_compute_enabled
    && try(local.aws_k3s_api_lb_cfg.enabled, false)
    && length(local.aws_k3s_server_names) > 0
  )
  aws_k3s_public_ingress_lb_cfg = merge(
    {
      enabled           = false
      name              = "${local.project_name}-k3s-public-ingress"
      port              = 443
      public_subnets    = ["external"]
      health_check_port = 443
    },
    try(local.aws_network_cfg.k3s_public_ingress_load_balancer, {})
  )
  aws_k3s_public_ingress_lb_enabled = (
    local.aws_k3s_enabled
    && local.aws_compute_enabled
    && try(local.aws_k3s_public_ingress_lb_cfg.enabled, false)
    && length(local.aws_k3s_server_names) > 0
  )

  gcp_jump_host_name = local.gcp_compute_enabled ? try([
    for name, cfg in local.gcp_instances_base : name
    if lookup(cfg, "role", "") == "jump-host" && lookup(cfg, "has_public_ip", false)
  ][0], "") : ""
  gcp_gateway_host_name = local.gcp_compute_enabled ? try([
    for name, cfg in local.gcp_instances_base : name
    if lookup(cfg, "role", "") == "gateway"
  ][0], "") : ""
  gcp_nat_host_name = local.gcp_compute_enabled ? try([
    for name, cfg in local.gcp_instances_base : name
    if lookup(cfg, "role", "") == "nat"
    ][0], try([
      for name, cfg in local.gcp_instances_base : name
      if lookup(cfg, "role", "") == "gateway"
      ][0], try([
        for name, cfg in local.gcp_instances_base : name
        if lookup(cfg, "can_ip_forward", false)
  ][0], ""))) : ""
  aws_jump_host_name = local.aws_compute_enabled ? try([
    for name, cfg in local.aws_instances_base : name
    if lookup(cfg, "role", "") == "jump-host" && lookup(cfg, "has_public_ip", false)
  ][0], "") : ""
  aws_gateway_host_name = local.aws_compute_enabled ? try([
    for name, cfg in local.aws_instances_base : name
    if lookup(cfg, "role", "") == "gateway"
  ][0], "") : ""
  aws_nat_host_name = local.aws_compute_enabled ? try([
    for name, cfg in local.aws_instances_base : name
    if lookup(cfg, "role", "") == "nat"
    ][0], try([
      for name, cfg in local.aws_instances_base : name
      if lookup(cfg, "role", "") == "gateway"
      ][0], try([
        for name, cfg in local.aws_instances_base : name
        if lookup(cfg, "can_ip_forward", false)
  ][0], ""))) : ""
  azure_jump_host_name = local.azure_compute_enabled ? try([
    for name, cfg in local.azure_instances_base : name
    if lookup(cfg, "role", "") == "jump-host" && lookup(cfg, "has_public_ip", false)
  ][0], "") : ""
  azure_gateway_host_name = local.azure_compute_enabled ? try([
    for name, cfg in local.azure_instances_base : name
    if lookup(cfg, "role", "") == "gateway"
  ][0], "") : ""
  azure_nat_host_name = local.azure_compute_enabled ? try([
    for name, cfg in local.azure_instances_base : name
    if lookup(cfg, "role", "") == "nat"
    ][0], try([
      for name, cfg in local.azure_instances_base : name
      if lookup(cfg, "role", "") == "gateway"
      ][0], try([
        for name, cfg in local.azure_instances_base : name
        if lookup(cfg, "can_ip_forward", false)
  ][0], ""))) : ""

  # Prefer a dedicated gateway for routing, but keep nat/can_ip_forward as a
  # compatibility fallback for older instance maps.
  gcp_route_host_name   = local.gcp_gateway_host_name != "" ? local.gcp_gateway_host_name : local.gcp_nat_host_name
  aws_route_host_name   = local.aws_gateway_host_name != "" ? local.aws_gateway_host_name : local.aws_nat_host_name
  azure_route_host_name = local.azure_gateway_host_name != "" ? local.azure_gateway_host_name : local.azure_nat_host_name

  private_default_route_cfg     = try(local.routing.private_default_route, null)
  private_default_route_enabled = local.private_default_route_cfg != null

  # Do not create routes without a gateway/NAT host.
  gcp_has_route_host = (
    local.gcp_route_host_name != ""
    && (
      local.private_default_route_enabled
      || length(try(local.gcp_network_cfg.remote_routes, [])) > 0
    )
  )
  aws_has_route_host = (
    local.aws_route_host_name != ""
    && (
      local.private_default_route_enabled
      || length(try(local.aws_network_cfg.remote_routes, [])) > 0
    )
  )
  azure_has_route_host = (
    local.azure_route_host_name != ""
    && (
      local.private_default_route_enabled
      || length(try(local.azure_network_cfg.remote_routes, [])) > 0
    )
  )

  nat_route_name       = try(local.private_default_route_cfg.name, "private-default-via-gateway")
  nat_destination_cidr = try(local.private_default_route_cfg.destination_cidr, "0.0.0.0/0")
  nat_priority         = try(local.private_default_route_cfg.priority, 800)
  nat_target_tags      = try(local.private_default_route_cfg.target_tags, ["internal-vm"])
  gcp_default_route_specs = (local.gcp_has_route_host && local.private_default_route_enabled) ? {
    (local.nat_route_name) = {
      destination_cidr = local.nat_destination_cidr
      priority         = local.nat_priority
      target_tags      = local.nat_target_tags
    }
  } : {}
  gcp_remote_route_specs = local.gcp_has_route_host ? {
    for route in try(local.gcp_network_cfg.remote_routes, []) :
    lookup(route, "name", "coin-ops-gcp-route-${replace(route.destination_cidr, "/", "-")}") => {
      destination_cidr = route.destination_cidr
      priority         = try(route.priority, local.nat_priority + 10)
      target_tags      = try(route.target_tags, local.remote_target_tags)
    }
  } : {}
  gcp_route_specs = merge(
    local.gcp_default_route_specs,
    local.gcp_remote_route_specs
  )
  aws_private_route_specs = local.aws_has_route_host ? merge(
    {
      for route_name in(local.private_default_route_enabled ? [local.nat_route_name] : []) :
      route_name => {
        destination_cidr = local.nat_destination_cidr
      }
    },
    {
      for route in try(local.aws_network_cfg.remote_routes, []) :
      lookup(route, "name", "coin-ops-aws-route-${replace(route.destination_cidr, "/", "-")}") => {
        destination_cidr = route.destination_cidr
      }
    }
  ) : {}
  aws_public_route_specs = local.aws_has_route_host ? {
    for route in try(local.aws_network_cfg.remote_routes, []) :
    lookup(route, "name", "coin-ops-aws-route-${replace(route.destination_cidr, "/", "-")}") => {
      destination_cidr = route.destination_cidr
    }
  } : {}
  azure_private_route_specs = local.azure_has_route_host ? merge(
    {
      for route_name in(local.private_default_route_enabled ? ["default-via-gateway"] : []) :
      route_name => {
        destination_cidr = local.nat_destination_cidr
      }
    },
    {
      for route in try(local.azure_network_cfg.remote_routes, []) :
      lookup(route, "name", "coin-ops-azure-route-${replace(route.destination_cidr, "/", "-")}") => {
        destination_cidr = route.destination_cidr
      }
    }
  ) : {}
  azure_public_route_specs = local.azure_has_route_host ? {
    for route in try(local.azure_network_cfg.remote_routes, []) :
    lookup(route, "name", "coin-ops-azure-route-${replace(route.destination_cidr, "/", "-")}") => {
      destination_cidr = route.destination_cidr
    }
  } : {}

  username = trimspace(try(local.general.username, ""))
  ssh_port = try(local.general.ssh_port, 22)

  project_name          = try(local.general.project_name, "coin-ops")
  gcp_project_id        = try(local.gcp_account.project_id, var.gcp_project_id)
  aws_account_id        = try(local.aws_account.account_id, "")
  azure_subscription_id = try(local.azure_account.subscription_id, var.azure_subscription_id)
  azure_tenant_id       = try(local.azure_account.tenant_id, var.azure_tenant_id)
  region_profile        = try(local.general.region_profile, "europe-central")
  image_profile         = try(local.general.image_profile, "debian-12")
  aws_region            = try(local.aws_regions[local.region_profile].region, try(local.general.aws_region, var.aws_region))
  gcp_region            = try(local.gcp_regions[local.region_profile].region, try(local.general.gcp_region, var.gcp_region))
  azure_location        = trimspace(try(local.general.azure_location, "")) != "" ? trimspace(local.general.azure_location) : try(local.azure_regions[local.region_profile].location, var.azure_location)
  gcp_zone              = try(local.gcp_regions[local.region_profile].zone, "${local.gcp_region}-a")
  aws_zone              = try(local.aws_regions[local.region_profile].zone, "${local.aws_region}a")

  azure_resource_group_name = try(local.azure_account.resource_group_name, "${local.project_name}-azure-rg")
  azure_key_vault_name      = try(local.azure_account.key_vault_name, "${replace(local.project_name, "-", "")}kv")

  app_domain      = try(local.deploy.app_domain, var.app_domain)
  homepage_domain = try(local.deploy.homepage.hostname, "home.${local.app_domain}")
  headlamp_cfg    = try(local.deploy.headlamp, {})
  jenkins_cfg = merge({
    enabled        = false
    namespace      = "jenkins"
    release_name   = "jenkins"
    chart_version  = ""
    controller_tag = "2.516.1-jdk21"
    storage_class  = "gp2"
    storage_size   = "8Gi"
    repository_url = ""
    branch         = "main"
    job_name       = "coinops-eks-deploy"
  }, try(local.deploy.jenkins, {}))
  jenkins_enabled = local.aws_eks_enabled && try(local.jenkins_cfg.enabled, false)
  # Cloudflare Tunnel is only for Headlamp access. Coin-Ops ingress continues
  # through the normal k3s/Traefik path so app routing stays observable.
  headlamp_tunnel_cfg = merge({
    enabled       = false
    namespace     = "cloudflare-tunnel"
    release_name  = "headlamp-tunnel"
    replica_count = 2
    chart_version = ""
    service       = "http://headlamp.headlamp.svc.cluster.local:80"
    access = {
      enabled        = true
      allowed_emails = []
    }
  }, try(local.headlamp_cfg.cloudflare_tunnel, {}))
  cloudflare_config                      = lookup(local.dns, "cloudflare", {})
  cloudflare_zone_id                     = try(local.cloudflare_config.zone_id, var.cloudflare_zone_id)
  cloudflare_account_id                  = try(local.cloudflare_config.account_id, var.cloudflare_account_id)
  headlamp_tunnel_name                   = "${local.project_name}-headlamp"
  headlamp_access_identity_provider_name = "${local.project_name}-headlamp-github"
  headlamp_access_application_name       = "${local.project_name}-headlamp"
  headlamp_access_policy_name            = "${local.project_name}-headlamp-github-access"

  gcp_cfg = {
    zone = local.gcp_zone
  }

  aws_cfg = {
    zone  = local.aws_zone
    zones = local.aws_zone_map
  }

  azure_cfg = {
    location            = local.azure_location
    resource_group_name = local.azure_resource_group_name
  }

  gcp_instances_cfg = {
    for name, cfg in local.gcp_instances_base : name => merge(
      cfg,
      {
        # Prefer explicit custom images, then a configured image family, then
        # Debian. This lets golden-image rollouts be per-host without changing modules.
        os_image = (
          try(local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].os_image, "") != ""
          ? local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].os_image
          : (
            try(local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].image_family, "") != ""
            ? "projects/${local.gcp_project_id}/global/images/family/${local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].image_family}"
            : "debian-cloud/debian-12"
          )
        )
      }
    )
  }

  aws_instances_cfg = {
    for name, cfg in local.aws_instances_base : name => merge(
      cfg,
      {
        ami_filter = try(local.aws_images[lookup(cfg, "image_profile", local.image_profile)].ami_filter, "debian-12-amd64-*")
        ami_owner  = try(local.aws_images[lookup(cfg, "image_profile", local.image_profile)].ami_owner, "136693071363")
      }
    )
  }

  azure_instances_cfg = {
    for name, cfg in local.azure_instances_base : name => merge(
      cfg,
      {
        source_image_id = try(local.azure_images[lookup(cfg, "image_profile", local.image_profile)].image_id, "")
        source_image_reference = {
          publisher = try(local.azure_images[lookup(cfg, "image_profile", local.image_profile)].publisher, try(local.azure_images[local.image_profile].publisher, "Debian"))
          offer     = try(local.azure_images[lookup(cfg, "image_profile", local.image_profile)].offer, try(local.azure_images[local.image_profile].offer, "debian-12"))
          sku       = try(local.azure_images[lookup(cfg, "image_profile", local.image_profile)].sku, try(local.azure_images[local.image_profile].sku, "12-gen2"))
          version   = try(local.azure_images[lookup(cfg, "image_profile", local.image_profile)].version, try(local.azure_images[local.image_profile].version, "latest"))
        }
      }
    )
  }

  gcp_db_secrets    = local.read_gcp_secret_backend ? try(jsondecode(data.google_secret_manager_secret_version.db_secrets[0].secret_data), {}) : {}
  gcp_app_secrets   = local.read_gcp_secret_backend ? try(jsondecode(data.google_secret_manager_secret_version.app_secrets[0].secret_data), {}) : {}
  aws_db_secrets    = local.read_aws_secret_backend ? try(jsondecode(data.aws_secretsmanager_secret_version.db_secrets[0].secret_string), {}) : {}
  aws_app_secrets   = local.read_aws_secret_backend ? try(jsondecode(data.aws_secretsmanager_secret_version.app_secrets[0].secret_string), {}) : {}
  azure_db_secrets  = local.read_azure_secret_backend ? try(jsondecode(data.azurerm_key_vault_secret.db_secrets[0].value), {}) : {}
  azure_app_secrets = local.read_azure_secret_backend ? try(jsondecode(data.azurerm_key_vault_secret.app_secrets[0].value), {}) : {}

  active_db_secrets = (
    local.secret_backend == "aws"
    ? local.aws_db_secrets
    : (
      local.secret_backend == "azure"
      ? local.azure_db_secrets
      : local.gcp_db_secrets
    )
  )
  active_app_secrets = (
    local.secret_backend == "aws"
    ? local.aws_app_secrets
    : (
      local.secret_backend == "azure"
      ? local.azure_app_secrets
      : local.gcp_app_secrets
    )
  )

  effective_db_password = (
    local.seed_secret_manager ? var.db_password : try(local.active_db_secrets.DB_PASSWORD, var.db_password)
  )
  effective_rabbitmq_password = (
    local.seed_secret_manager ? var.rabbitmq_password : try(local.active_db_secrets.RABBITMQ_PASSWORD, var.rabbitmq_password)
  )
  effective_ghcr_token = (
    local.seed_secret_manager ? var.ghcr_token : try(local.active_app_secrets.GHCR_TOKEN, var.ghcr_token)
  )
  effective_cloudflare_api_token = (
    local.seed_secret_manager ? var.cloudflare_api_token : try(local.active_app_secrets.CLOUDFLARE_API_TOKEN, var.cloudflare_api_token)
  )
  cloudflare_provider_api_token = (
    trimspace(coalesce(nonsensitive(local.effective_cloudflare_api_token), "")) != ""
    ? trimspace(coalesce(nonsensitive(local.effective_cloudflare_api_token), ""))
    : "placeholder_token"
  )
  effective_tailscale_auth_key = (
    local.seed_secret_manager ? var.tailscale_auth_key : try(local.active_app_secrets.TAILSCALE_AUTH_KEY, var.tailscale_auth_key)
  )
  effective_github_oauth_client_id = (
    local.seed_secret_manager ? var.github_oauth_client_id : try(local.active_app_secrets.GITHUB_OAUTH_CLIENT_ID, var.github_oauth_client_id)
  )
  effective_github_oauth_client_secret = (
    local.seed_secret_manager ? var.github_oauth_client_secret : try(local.active_app_secrets.GITHUB_OAUTH_CLIENT_SECRET, var.github_oauth_client_secret)
  )
  effective_cnpg_backup_gcs_credentials  = try(base64decode(google_service_account_key.cnpg_backup[0].private_key), try(local.active_app_secrets.CNPG_BACKUP_GCS_CREDENTIALS, ""))
  effective_cnpg_backup_s3_access_key_id = try(aws_iam_access_key.cnpg_backup[0].id, try(local.active_app_secrets.CNPG_BACKUP_S3_ACCESS_KEY_ID, ""))
  effective_cnpg_backup_s3_secret_access_key = try(
    aws_iam_access_key.cnpg_backup[0].secret,
    try(local.active_app_secrets.CNPG_BACKUP_S3_SECRET_ACCESS_KEY, "")
  )
  headlamp_tunnel_enabled = (
    try(local.headlamp_cfg.enabled, true)
    && try(local.headlamp_tunnel_cfg.enabled, false)
    && local.cloudflare_zone_id != ""
    && local.cloudflare_account_id != ""
    && nonsensitive(local.effective_cloudflare_api_token) != ""
    && nonsensitive(local.effective_github_oauth_client_id) != ""
    && nonsensitive(local.effective_github_oauth_client_secret) != ""
  )
  headlamp_access_enabled        = local.headlamp_tunnel_enabled && try(local.headlamp_tunnel_cfg.access.enabled, true)
  headlamp_access_allowed_emails = try(local.headlamp_tunnel_cfg.access.allowed_emails, [])
}
