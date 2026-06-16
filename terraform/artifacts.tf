# Local files consumed by Ansible. They are generated and gitignored.
module "local_operator_artifacts" {
  source = "./modules/support/local_operator_artifacts"

  hosts_filename = "${path.module}/config/hosts.json"
  # Runtime addresses only; host discovery still comes from dynamic inventory.
  hosts_content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        ssh_user    = local.username
        ssh_port    = local.ssh_port
        instances   = local.gcp_compute_enabled ? try(module.gcp_instances[0].instance_ips, {}) : {}
        database_ip = try(module.gcp_database[0].private_ip, "")
        database = {
          host    = try(module.gcp_database[0].private_ip, "")
          port    = local.db_port
          name    = local.db_name
          user    = local.db_username
          managed = try(module.gcp_database[0].private_ip, "") != ""
        }
        cnpg_backup = {
          provider         = "gcs"
          enabled          = local.cnpg_backup_enabled
          bucket           = local.cnpg_backup_bucket_name
          destination_path = local.cnpg_backup_destination
          schedule         = local.cnpg_backup_schedule
          retention_policy = local.cnpg_backup_retention
        }
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        ssh_user    = local.username
        ssh_port    = local.ssh_port
        instances   = local.aws_compute_enabled ? try(module.aws_instances[0].instance_ips, {}) : {}
        database_ip = try(module.aws_database[0].address, "")
        database = {
          host    = try(module.aws_database[0].address, "")
          port    = try(module.aws_database[0].port, local.db_port)
          name    = local.db_name
          user    = local.db_username
          managed = try(module.aws_database[0].address, "") != ""
        }
        cnpg_backup = {
          provider         = "s3"
          enabled          = local.aws_cnpg_backup_enabled
          bucket           = local.aws_cnpg_backup_bucket_name
          destination_path = local.aws_cnpg_backup_destination
          schedule         = local.cnpg_backup_schedule
          retention_policy = local.cnpg_backup_retention
          region           = local.aws_region
        }
      }
    } : {},
    local.azure_enabled ? {
      azure = {
        ssh_user    = local.username
        ssh_port    = local.ssh_port
        instances   = local.azure_compute_enabled ? try(module.azure_instances[0].instance_ips, {}) : {}
        database_ip = try(module.azure_database[0].fqdn, "")
        database = {
          host    = try(module.azure_database[0].fqdn, "")
          port    = try(module.azure_database[0].port, local.db_port)
          name    = local.db_name
          user    = local.db_username
          managed = try(module.azure_database[0].fqdn, "") != ""
        }
      }
    } : {}
  ))

  ssh_config_filename = "${path.module}/config/ssh_config"
  # ProxyJump is resolved here so playbooks do not repeat address rules.
  ssh_config_content = trimspace(join("\n\n", concat(
    local.gcp_compute_enabled ? [
      for name, inst in local.gcp_hosts : trimspace(<<-EOT
        Host coinops-gcp-${name}
          HostName ${inst.role == "jump-host" ? inst.public_ip : inst.private_ip}
          User ${local.username}
          Port ${local.ssh_port}
          ${inst.role != "jump-host" && local.gcp_jump_host_name != "" ? "ProxyJump coinops-gcp-${local.gcp_jump_host_name}" : ""}
          IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}
          IdentitiesOnly yes
          ServerAliveInterval 15
          ServerAliveCountMax 4
          ConnectionAttempts 3
          ConnectTimeout 20
          ControlMaster no
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      EOT
      )
    ] : [],
    local.aws_compute_enabled ? [
      for name, inst in local.aws_hosts : trimspace(<<-EOT
        Host coinops-aws-${name}
          HostName ${inst.role == "jump-host" ? inst.public_ip : inst.private_ip}
          User ${local.username}
          Port ${local.ssh_port}
          ${inst.role != "jump-host" && local.aws_jump_host_name != "" ? "ProxyJump coinops-aws-${local.aws_jump_host_name}" : ""}
          IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}
          IdentitiesOnly yes
          ServerAliveInterval 15
          ServerAliveCountMax 4
          ConnectionAttempts 3
          ConnectTimeout 20
          ControlMaster no
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      EOT
      )
    ] : [],
    local.azure_compute_enabled ? [
      for name, inst in local.azure_hosts : trimspace(<<-EOT
        Host coinops-azure-${name}
          HostName ${inst.role == "jump-host" ? inst.public_ip : inst.private_ip}
          User ${local.username}
          Port ${local.ssh_port}
          ${inst.role != "jump-host" && local.azure_jump_host_name != "" ? "ProxyJump coinops-azure-${local.azure_jump_host_name}" : ""}
          IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}
          IdentitiesOnly yes
          ServerAliveInterval 15
          ServerAliveCountMax 4
          ConnectionAttempts 3
          ConnectTimeout 20
          ControlMaster no
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      EOT
      )
    ] : []
  )))

  ansible_runtime_filename = "${path.module}/config/ansible-runtime.json"
  # Derived module values: LB IPs, DB endpoints, tunnel tokens.
  ansible_runtime_content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        k3s_api_endpoint                = local.gcp_k3s_api_lb_enabled ? try(module.gcp_k3s_api_lb[0].ip_address, "") : ""
        headlamp_ingress_ip             = local.gcp_k3s_ingress_lb_enabled ? try(module.gcp_k3s_ingress_lb[0].ip_address, "") : ""
        headlamp_tunnel_enabled         = local.headlamp_tunnel_enabled
        headlamp_tunnel_token           = local.headlamp_tunnel_enabled ? cloudflare_zero_trust_tunnel_cloudflared.headlamp[0].tunnel_token : ""
        headlamp_public_host            = local.headlamp_domain
        homepage_public_ip              = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
        homepage_public_host            = local.homepage_domain
        homepage_public_endpoint        = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
        public_ingress_load_balancer_ip = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
        database_ip                     = try(module.gcp_database[0].private_ip, "")
        use_managed_db                  = try(module.gcp_database[0].private_ip, "") != ""
        database = {
          host    = try(module.gcp_database[0].private_ip, "")
          port    = local.db_port
          name    = local.db_name
          user    = local.db_username
          managed = try(module.gcp_database[0].private_ip, "") != ""
        }
        cnpg_backup = {
          provider         = "gcs"
          enabled          = local.cnpg_backup_enabled
          bucket           = local.cnpg_backup_bucket_name
          destination_path = local.cnpg_backup_destination
          schedule         = local.cnpg_backup_schedule
          retention_policy = local.cnpg_backup_retention
        }
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        kubernetes_runtime                    = local.aws_eks_enabled ? "eks" : "k3s"
        eks_cluster_name                      = local.aws_eks_enabled ? module.aws_eks[0].cluster_name : ""
        eks_kubeconfig_path                   = local.aws_eks_enabled ? local_file.aws_eks_kubeconfig[0].filename : ""
        eks_service_ipv4_cidr                 = local.aws_eks_enabled ? try(local.aws_eks_cfg.service_ipv4_cidr, "10.43.0.0/16") : ""
        eks_pod_cidr                          = local.aws_eks_enabled ? local.aws_vpc_cidr : ""
        k3s_api_endpoint                      = local.aws_k3s_api_lb_enabled ? try(module.aws_k3s_api_lb[0].dns_name, "") : ""
        headlamp_tunnel_enabled               = local.headlamp_tunnel_enabled
        headlamp_tunnel_token                 = local.headlamp_tunnel_enabled ? cloudflare_zero_trust_tunnel_cloudflared.headlamp[0].tunnel_token : ""
        headlamp_public_host                  = local.headlamp_domain
        coinops_tunnel_enabled                = local.coinops_tunnel_enabled
        coinops_public_host                   = local.coinops_domain
        homepage_public_host                  = local.homepage_domain
        homepage_public_endpoint              = local.aws_k3s_public_ingress_lb_enabled ? try(module.aws_k3s_public_ingress_lb[0].dns_name, "") : ""
        public_ingress_load_balancer_dns_name = local.aws_k3s_public_ingress_lb_enabled ? try(module.aws_k3s_public_ingress_lb[0].dns_name, "") : ""
        database_ip                           = try(module.aws_database[0].address, "")
        use_managed_db                        = try(module.aws_database[0].address, "") != ""
        database = {
          host    = try(module.aws_database[0].address, "")
          port    = try(module.aws_database[0].port, local.db_port)
          name    = local.db_name
          user    = local.db_username
          managed = try(module.aws_database[0].address, "") != ""
        }
        cnpg_backup = {
          provider         = "s3"
          enabled          = local.aws_cnpg_backup_enabled
          bucket           = local.aws_cnpg_backup_bucket_name
          destination_path = local.aws_cnpg_backup_destination
          schedule         = local.cnpg_backup_schedule
          retention_policy = local.cnpg_backup_retention
          region           = local.aws_region
        }
      }
    } : {},
    local.azure_enabled ? {
      azure = {
        database_ip    = try(module.azure_database[0].fqdn, "")
        use_managed_db = try(module.azure_database[0].fqdn, "") != ""
        database = {
          host    = try(module.azure_database[0].fqdn, "")
          port    = try(module.azure_database[0].port, local.db_port)
          name    = local.db_name
          user    = local.db_username
          managed = try(module.azure_database[0].fqdn, "") != ""
        }
      }
    } : {}
  ))

  ssh_sync_target_path = pathexpand("~/.ssh/extra_configs/coin-ops-ssh-config")
}
