# No secrets here; only endpoints and generated local file paths.
output "gcp_instance_ips" {
  description = "GCP instance IP addresses"
  value       = try(module.gcp_instances[0].instance_ips, {})
}

output "aws_instance_ips" {
  description = "AWS instance IP addresses"
  value       = try(module.aws_instances[0].instance_ips, {})
}

output "azure_instance_ips" {
  description = "Azure instance IP addresses"
  value       = try(module.azure_instances[0].instance_ips, {})
}

output "hosts_file" {
  description = "Path to the generated hosts.json file for local debugging"
  value       = module.local_operator_artifacts.hosts_filename
}

output "ssh_config_file" {
  description = "Path to generated SSH config with bastion and private hosts"
  value       = module.local_operator_artifacts.ssh_config_filename
}

output "ansible_runtime_file" {
  description = "Path to the generated non-secret Terraform-to-Ansible runtime metadata"
  value       = module.local_operator_artifacts.ansible_runtime_filename
}

output "database_endpoints" {
  description = "Managed PostgreSQL endpoints by cloud. Empty when the cloud uses the containerized fallback."
  value = {
    gcp = local.gcp_enabled ? {
      host    = try(module.gcp_database[0].private_ip, "")
      port    = local.db_port
      name    = local.db_name
      user    = local.db_username
      managed = try(module.gcp_database[0].private_ip, "") != ""
    } : null
    aws = local.aws_enabled ? {
      host    = try(module.aws_database[0].address, "")
      port    = try(module.aws_database[0].port, local.db_port)
      name    = local.db_name
      user    = local.db_username
      managed = try(module.aws_database[0].address, "") != ""
    } : null
    azure = local.azure_enabled ? {
      host    = try(module.azure_database[0].fqdn, "")
      port    = try(module.azure_database[0].port, local.db_port)
      name    = local.db_name
      user    = local.db_username
      managed = try(module.azure_database[0].fqdn, "") != ""
    } : null
  }
}

output "public_endpoints" {
  description = "Cloud-specific public UI endpoints. DNS is created only for dns.primary_cloud; non-primary clouds are tested by direct public IP."
  value = {
    for cloud, ip in local.ui_public_ips : cloud => {
      public_ip  = ip
      direct_url = format("https://%s", ip)
      dns_name   = cloud == local.dns_primary_cloud ? local.app_domain : null
      dns_url    = cloud == local.dns_primary_cloud ? format("https://%s", local.app_domain) : null
    }
    if lookup(local.cloud_has_ui, cloud, false)
  }
}

output "control_plane_cloud" {
  description = "Cloud selected in JSON as the intended Terraform control plane. The active backend is generated into backend.active.tf by bootstrap."
  value       = local.control_plane_cloud
}

output "gcp_k3s_api_load_balancer_ip" {
  description = "Internal HA endpoint for the k3s Kubernetes API in GCP."
  value       = local.gcp_k3s_api_lb_enabled ? try(module.gcp_k3s_api_lb[0].ip_address, "") : ""
}

output "gcp_k3s_ingress_load_balancer_ip" {
  description = "Internal ingress endpoint for Traefik/Headlamp in GCP."
  value       = local.gcp_k3s_ingress_lb_enabled ? try(module.gcp_k3s_ingress_lb[0].ip_address, "") : ""
}

output "gcp_k3s_public_ingress_load_balancer_ip" {
  description = "Public HTTPS endpoint for Homepage and future public apps in GCP."
  value       = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
}

output "homepage_public_url" {
  description = "Preferred public Homepage URL when the GCP public ingress load balancer is enabled."
  value       = local.gcp_k3s_public_ingress_lb_enabled ? "https://${local.homepage_domain}" : ""
}
