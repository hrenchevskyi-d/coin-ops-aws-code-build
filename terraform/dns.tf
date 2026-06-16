# Cloudflare DNS. The root app domain points at one primary cloud.

locals {
  dns_primary_cloud       = try(local.dns.primary_cloud, local.control_plane_cloud)
  dns_ttl                 = try(local.cloudflare_config.ttl, 60)
  dns_proxied             = try(local.cloudflare_config.proxied, false)
  coinops_domain          = try(local.deploy.coinops.hostname, local.app_domain)
  headlamp_domain         = try(local.deploy.headlamp.hostname, "headlamp.${local.app_domain}")
  homepage_domain_for_dns = try(local.deploy.homepage.hostname, "home.${local.app_domain}")
  coinops_dns_name        = local.coinops_domain == local.app_domain ? "@" : trimsuffix(local.coinops_domain, ".${local.app_domain}")
  headlamp_dns_name       = local.headlamp_domain == local.app_domain ? "@" : trimsuffix(local.headlamp_domain, ".${local.app_domain}")
  homepage_dns_name       = local.homepage_domain_for_dns == local.app_domain ? "@" : trimsuffix(local.homepage_domain_for_dns, ".${local.app_domain}")

  dns_has_api_token  = nonsensitive(local.effective_cloudflare_api_token) != ""
  dns_enabled        = (local.gcp_enabled || local.aws_enabled || local.azure_enabled) && local.dns_has_api_token && local.cloudflare_zone_id != ""
  coinops_public_ip  = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
  coinops_public_dns = local.aws_k3s_public_ingress_lb_enabled ? try(module.aws_k3s_public_ingress_lb[0].dns_name, "") : ""
  aws_eks_public_ingress_ips = (
    local.aws_eks_public_ingress_enabled
    ? [for name in local.aws_eks_public_ingress_subnet_names : aws_eip.aws_eks_public_ingress[name].public_ip]
    : []
  )
  headlamp_private_ip    = local.gcp_k3s_ingress_lb_enabled ? try(module.gcp_k3s_ingress_lb[0].ip_address, "") : ""
  headlamp_tunnel_target = local.headlamp_tunnel_enabled ? "${cloudflare_zero_trust_tunnel_cloudflared.headlamp[0].id}.cfargotunnel.com" : ""
  homepage_public_ip     = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
  homepage_public_dns    = local.aws_k3s_public_ingress_lb_enabled ? try(module.aws_k3s_public_ingress_lb[0].dns_name, "") : ""
  dns_primary_is_gcp     = local.dns_primary_cloud == "gcp"
  dns_primary_is_aws     = local.dns_primary_cloud == "aws"
  dns_primary_has_public_ingress = (
    (local.dns_primary_is_gcp && local.gcp_k3s_public_ingress_lb_enabled)
    || (local.dns_primary_is_aws && local.aws_k3s_public_ingress_lb_enabled)
    || (local.dns_primary_is_aws && local.aws_eks_public_ingress_enabled)
  )
  public_ingress_a_record_ips = (
    local.dns_primary_is_aws && local.aws_eks_public_ingress_enabled
    ? local.aws_eks_public_ingress_ips
    : (
      local.dns_primary_is_gcp && local.gcp_k3s_public_ingress_lb_enabled
      ? [local.coinops_public_ip]
      : []
    )
  )
  coinops_dns_content = (
    local.dns_primary_is_aws
    ? local.coinops_public_dns
    : local.coinops_public_ip
  )
  coinops_dns_type = local.dns_primary_is_aws ? "CNAME" : "A"
  homepage_dns_content = (
    local.dns_primary_is_aws
    ? local.homepage_public_dns
    : local.homepage_public_ip
  )
  homepage_dns_type = local.dns_primary_is_aws ? "CNAME" : "A"
  headlamp_ingress_content = (
    local.dns_primary_is_aws
    ? local.coinops_public_dns
    : local.headlamp_private_ip
  )
  headlamp_ingress_type = local.dns_primary_is_aws ? "CNAME" : "A"
  # DNS points at public ingress; images are handled outside Terraform.
  cloudflare_dns_records = merge(
    {
      root_cname = {
        enabled         = local.dns_enabled && local.dns_primary_is_aws && local.aws_k3s_public_ingress_lb_enabled
        name            = local.coinops_dns_name
        content         = local.coinops_dns_content
        type            = local.coinops_dns_type
        proxied         = local.dns_proxied
        ttl             = local.dns_ttl
        allow_overwrite = true
      }
      www_cname = {
        enabled         = local.dns_enabled && local.dns_primary_is_aws && local.aws_k3s_public_ingress_lb_enabled
        name            = "www"
        content         = local.app_domain
        type            = "CNAME"
        proxied         = local.dns_proxied
        ttl             = local.dns_ttl
        allow_overwrite = true
      }
      headlamp_private_a = {
        enabled         = local.dns_enabled && !local.headlamp_tunnel_enabled && ((local.dns_primary_is_gcp && local.gcp_k3s_ingress_lb_enabled) || (local.dns_primary_is_aws && local.aws_k3s_public_ingress_lb_enabled))
        name            = local.headlamp_dns_name
        content         = local.headlamp_ingress_content
        type            = local.headlamp_ingress_type
        proxied         = false
        ttl             = local.dns_ttl
        allow_overwrite = true
      }
      headlamp_tunnel_cname = {
        enabled         = local.dns_enabled && local.headlamp_tunnel_enabled
        name            = local.headlamp_dns_name
        content         = local.headlamp_tunnel_target
        type            = "CNAME"
        proxied         = true
        ttl             = 1
        allow_overwrite = true
      }
      homepage_public_cname = {
        enabled         = local.dns_enabled && local.dns_primary_is_aws && local.aws_k3s_public_ingress_lb_enabled
        name            = local.homepage_dns_name
        content         = local.homepage_dns_content
        type            = local.homepage_dns_type
        proxied         = false
        ttl             = local.dns_ttl
        allow_overwrite = true
      }
    },
    {
      for idx, ip in local.public_ingress_a_record_ips : (idx == 0 ? "root_a" : "root_a_${idx}") => {
        enabled         = local.dns_enabled && local.dns_primary_has_public_ingress
        name            = local.coinops_dns_name
        content         = ip
        type            = "A"
        proxied         = local.dns_proxied
        ttl             = local.dns_ttl
        allow_overwrite = true
      }
    },
    {
      for idx, ip in local.public_ingress_a_record_ips : (idx == 0 ? "www_cname" : "www_a_${idx}") => {
        enabled         = local.dns_enabled && local.dns_primary_has_public_ingress
        name            = "www"
        content         = ip
        type            = "A"
        proxied         = local.dns_proxied
        ttl             = local.dns_ttl
        allow_overwrite = true
      }
    },
    {
      for idx, ip in local.public_ingress_a_record_ips : (idx == 0 ? "homepage_public_a" : "homepage_a_${idx}") => {
        enabled         = local.dns_enabled && local.dns_primary_has_public_ingress
        name            = local.homepage_dns_name
        content         = ip
        type            = "A"
        proxied         = false
        ttl             = local.dns_ttl
        allow_overwrite = true
      }
    }
  )
}

module "cloudflare_dns_records" {
  count   = local.dns_enabled ? 1 : 0
  source  = "./modules/cloudflare/records"
  zone_id = local.cloudflare_zone_id
  records = local.cloudflare_dns_records
}
