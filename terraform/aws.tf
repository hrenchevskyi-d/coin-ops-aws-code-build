# AWS is gated by locals so disabled plans do not need AWS credentials.
# Skip secret reads while seeding or repairing secrets.
data "aws_secretsmanager_secret_version" "db_secrets" {
  count     = local.read_aws_secret_backend ? 1 : 0
  secret_id = local.db_secret_name
}

data "aws_secretsmanager_secret_version" "app_secrets" {
  count     = local.read_aws_secret_backend ? 1 : 0
  secret_id = local.app_secret_name
}

module "aws_network" {
  count    = local.aws_enabled ? 1 : 0
  source   = "./modules/cloud/aws/network"
  vpc_name = local.aws_vpc_name
  vpc_cidr = local.aws_vpc_cidr
  subnets  = local.aws_subnets
  zone     = lookup(local.aws_cfg, "zone", "${local.aws_region}a")
  zones    = lookup(local.aws_cfg, "zones", {})
  managed_nat_gateway = try(local.aws_network_cfg.managed_nat_gateway, {
    enabled       = false
    public_subnet = ""
  })
}

module "aws_security_groups" {
  count          = local.aws_enabled ? 1 : 0
  source         = "./modules/cloud/aws/security_groups"
  vpc_id         = module.aws_network[0].vpc_id
  firewall_rules = local.firewall_rules
  egress_cidrs   = local.egress_cidrs
}

module "aws_instances" {
  count          = local.aws_compute_enabled ? 1 : 0
  source         = "./modules/cloud/aws/instances"
  instances      = local.aws_instances_cfg
  defaults       = local.general
  cloud_defaults = local.aws_cfg
  instance_sizes = local.aws_instance_sizes
  subnet_ids     = module.aws_network[0].subnet_ids
  sg_ids         = module.aws_security_groups[0].sg_ids
  iam_instance_profile_name = try(
    module.aws_observability_iam[0].instance_profile_name,
    null
  )
  ssh_public_key      = local.ssh_public_key
  private_subnet_cidr = local.aws_private_subnet_cidr
  vpc_cidr            = local.aws_vpc_cidr
  username            = local.username
  ssh_port            = local.ssh_port
  project_name        = local.project_name
}

# VM gateway routes are separate from AWS managed NAT.
module "aws_nat_route" {
  count                    = local.aws_compute_enabled && local.aws_has_route_host ? 1 : 0
  source                   = "./modules/cloud/aws/nat_route"
  private_route_table_id   = module.aws_network[0].private_route_table_id
  public_route_table_id    = module.aws_network[0].public_route_table_id
  nat_network_interface_id = try(module.aws_instances[0].instance_primary_network_interface_ids[local.aws_route_host_name], "")
  private_routes           = local.aws_private_route_specs
  public_routes            = local.aws_public_route_specs

  depends_on = [module.aws_instances]
}

module "aws_eks" {
  count  = local.aws_eks_enabled ? 1 : 0
  source = "./modules/cloud/aws/eks"

  project_name       = local.project_name
  cluster_name       = try(local.aws_eks_cfg.cluster_name, "${local.project_name}-eks")
  kubernetes_version = try(local.aws_eks_cfg.version, "1.33")
  cluster_subnet_ids = concat(
    [for name in try(local.aws_eks_cfg.private_subnets, []) : module.aws_network[0].subnet_ids[name]],
    [for name in try(local.aws_eks_cfg.public_subnets, []) : module.aws_network[0].subnet_ids[name]]
  )
  node_subnet_ids         = [for name in try(local.aws_eks_cfg.private_subnets, []) : module.aws_network[0].subnet_ids[name]]
  service_ipv4_cidr       = try(local.aws_eks_cfg.service_ipv4_cidr, "10.43.0.0/16")
  endpoint_public_access  = try(local.aws_eks_cfg.endpoint_public, true)
  endpoint_private_access = try(local.aws_eks_cfg.endpoint_private, true)
  public_access_cidrs     = try(local.aws_eks_cfg.public_access_cidrs, ["0.0.0.0/0"])
  node_group              = local.aws_eks_cfg.node_group
  addons                  = try(local.aws_eks_cfg.addons, {})

  tags = {
    Cloud = "aws"
  }

  depends_on = [module.aws_network]
}

resource "local_file" "aws_eks_kubeconfig" {
  count    = local.aws_eks_enabled ? 1 : 0
  filename = "${path.module}/../ansible/artifacts/kubeconfig-aws-eks.yaml"
  content = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = module.aws_eks[0].cluster_name
    clusters = [
      {
        name = module.aws_eks[0].cluster_name
        cluster = {
          server                     = module.aws_eks[0].cluster_endpoint
          certificate-authority-data = module.aws_eks[0].cluster_ca_certificate
        }
      }
    ]
    contexts = [
      {
        name = module.aws_eks[0].cluster_name
        context = {
          cluster = module.aws_eks[0].cluster_name
          user    = module.aws_eks[0].cluster_name
        }
      }
    ]
    users = [
      {
        name = module.aws_eks[0].cluster_name
        user = {
          exec = {
            apiVersion = "client.authentication.k8s.io/v1beta1"
            command    = "aws"
            args       = ["eks", "get-token", "--region", local.aws_region, "--cluster-name", module.aws_eks[0].cluster_name]
          }
        }
      }
    ]
  })
}

module "aws_k3s_api_lb" {
  count  = local.aws_k3s_api_lb_enabled ? 1 : 0
  source = "./modules/cloud/aws/network_load_balancer"

  name       = try(local.aws_k3s_api_lb_cfg.name, "${local.project_name}-k3s-api")
  vpc_id     = module.aws_network[0].vpc_id
  subnet_ids = [for name in try(local.aws_k3s_api_lb_cfg.internal_subnets, ["internal"]) : module.aws_network[0].subnet_ids[name]]
  internal   = true
  target_instance_ids = {
    for name in local.aws_k3s_server_names : name => module.aws_instances[0].instance_ids[name]
  }
  target_security_group_id          = try(module.aws_security_groups[0].sg_ids["k3s-server"], "")
  allowed_target_cidrs              = [local.aws_vpc_cidr]
  enable_target_security_group_rule = false
  port                              = try(local.aws_k3s_api_lb_cfg.port, 6443)
  health_check_port                 = try(local.aws_k3s_api_lb_cfg.health_check_port, 6443)
  tags = {
    Project = local.project_name
    Cloud   = "aws"
  }
}

module "aws_k3s_public_ingress_lb" {
  count  = local.aws_k3s_public_ingress_lb_enabled ? 1 : 0
  source = "./modules/cloud/aws/network_load_balancer"

  name       = try(local.aws_k3s_public_ingress_lb_cfg.name, "${local.project_name}-k3s-public-ingress")
  vpc_id     = module.aws_network[0].vpc_id
  subnet_ids = [for name in try(local.aws_k3s_public_ingress_lb_cfg.public_subnets, ["external"]) : module.aws_network[0].subnet_ids[name]]
  internal   = false
  target_instance_ids = {
    for name in local.aws_k3s_server_names : name => module.aws_instances[0].instance_ids[name]
  }
  target_security_group_id          = try(module.aws_security_groups[0].sg_ids["k3s-server"], "")
  allowed_target_cidrs              = [local.aws_vpc_cidr]
  enable_target_security_group_rule = false
  port                              = try(local.aws_k3s_public_ingress_lb_cfg.port, 443)
  health_check_port                 = try(local.aws_k3s_public_ingress_lb_cfg.health_check_port, 443)
  tags = {
    Project = local.project_name
    Cloud   = "aws"
  }
}

module "aws_database" {
  count                     = local.aws_enabled && local.database_enabled ? 1 : 0
  source                    = "./modules/cloud/aws/database"
  project_name              = local.project_name
  vpc_id                    = module.aws_network[0].vpc_id
  subnet_ids                = module.aws_network[0].database_subnet_ids
  backend_security_group_id = try(module.aws_security_groups[0].sg_ids["app-backend"], "")
  db_password               = local.effective_db_password
  db_name                   = local.db_name
  db_username               = local.db_username
  db_port                   = local.db_port
  engine_version            = try(local.database.version, "16")
  instance_class            = try(local.aws_db_profile.instance_class, "db.t4g.micro")
  allocated_storage         = try(local.aws_db_profile.allocated_storage, 20)
  storage_type              = try(local.aws_db_profile.storage_type, "gp3")
  backup_retention_period   = try(local.aws_db_profile.backup_retention_period, 7)
  multi_az                  = try(local.aws_db_profile.multi_az, false)
}

module "aws_secrets" {
  count                            = local.write_aws_secret_backend ? 1 : 0
  source                           = "./modules/cloud/aws/secrets"
  db_secret_name                   = local.db_secret_name
  app_secret_name                  = local.app_secret_name
  db_password                      = local.effective_db_password
  rabbitmq_password                = local.effective_rabbitmq_password
  ghcr_token                       = local.effective_ghcr_token
  cloudflare_api_token             = local.effective_cloudflare_api_token
  tailscale_auth_key               = local.effective_tailscale_auth_key
  github_oauth_client_id           = local.effective_github_oauth_client_id
  github_oauth_client_secret       = local.effective_github_oauth_client_secret
  cnpg_backup_s3_access_key_id     = local.effective_cnpg_backup_s3_access_key_id
  cnpg_backup_s3_secret_access_key = local.effective_cnpg_backup_s3_secret_access_key
}
