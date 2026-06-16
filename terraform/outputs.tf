# No secrets here; only endpoints and generated local file paths.
output "gcp_instance_ips" {
  description = "GCP instance IP addresses"
  value       = try(module.gcp_instances[0].instance_ips, {})
}

output "aws_instance_ips" {
  description = "AWS instance IP addresses"
  value       = try(module.aws_instances[0].instance_ips, {})
}

output "aws_ec2_observability_instance_profile" {
  description = "IAM instance profile attached to AWS EC2 instances for SSM and CloudWatch Agent."
  value       = local.aws_compute_enabled && local.aws_observability_enabled ? try(module.aws_observability_iam[0].instance_profile_name, "") : ""
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
  description = "Public application endpoints for the k3s ingress path."
  value = merge(
    local.gcp_k3s_public_ingress_lb_enabled ? {
      gcp = {
        public_ip  = local.coinops_public_ip
        direct_url = format("https://%s", local.coinops_public_ip)
        dns_name   = local.coinops_domain
        dns_url    = format("https://%s", local.coinops_domain)
      }
    } : {},
    local.aws_k3s_public_ingress_lb_enabled ? {
      aws = {
        public_dns = local.coinops_public_dns
        direct_url = format("https://%s", local.coinops_public_dns)
        dns_name   = local.coinops_domain
        dns_url    = format("https://%s", local.coinops_domain)
      }
    } : {}
  )
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

output "aws_k3s_api_load_balancer_dns_name" {
  description = "Internal HA endpoint for the k3s Kubernetes API in AWS."
  value       = local.aws_k3s_api_lb_enabled ? try(module.aws_k3s_api_lb[0].dns_name, "") : ""
}

output "aws_k3s_public_ingress_load_balancer_dns_name" {
  description = "Public HTTPS endpoint for Homepage and future public apps in AWS."
  value       = local.aws_k3s_public_ingress_lb_enabled ? try(module.aws_k3s_public_ingress_lb[0].dns_name, "") : ""
}

output "aws_eks_cluster_name" {
  description = "AWS EKS cluster name when deploy.kubernetes.runtime is eks."
  value       = local.aws_eks_enabled ? module.aws_eks[0].cluster_name : ""
}

output "aws_eks_cluster_endpoint" {
  description = "AWS EKS Kubernetes API endpoint."
  value       = local.aws_eks_enabled ? module.aws_eks[0].cluster_endpoint : ""
}

output "aws_eks_kubeconfig_file" {
  description = "Generated kubeconfig path for AWS EKS automation."
  value       = local.aws_eks_enabled ? local_file.aws_eks_kubeconfig[0].filename : ""
}

output "jenkins_admin_password" {
  description = "Generated Jenkins local admin password. Use terraform output -raw jenkins_admin_password."
  value       = local.jenkins_enabled ? random_password.jenkins_admin[0].result : ""
  sensitive   = true
}

output "homepage_public_url" {
  description = "Preferred public Homepage URL when a public k3s ingress load balancer is enabled."
  value       = local.gcp_k3s_public_ingress_lb_enabled || local.aws_k3s_public_ingress_lb_enabled ? "https://${local.homepage_domain}" : ""
}
