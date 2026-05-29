# DNS Automation via Cloudflare.
# The root app domain belongs to one primary cloud only.
# Non-primary cloud deployments are intentionally tested by direct public IP.

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

  gcp_has_ui   = local.gcp_compute_enabled && contains(keys(local.gcp_instances_base), "app-1")
  aws_has_ui   = local.aws_compute_enabled && contains(keys(local.aws_instances_base), "app-1")
  azure_has_ui = local.azure_compute_enabled && contains(keys(local.azure_instances_base), "app-1")

  ui_public_ips = {
    gcp   = local.gcp_has_ui ? try(module.gcp_instances[0].instance_ips["app-1"].public_ip, "") : ""
    aws   = local.aws_has_ui ? try(module.aws_instances[0].instance_ips["app-1"].public_ip, "") : ""
    azure = local.azure_has_ui ? try(module.azure_instances[0].instance_ips["app-1"].public_ip, "") : ""
  }

  cloud_has_ui = {
    gcp   = local.gcp_has_ui
    aws   = local.aws_has_ui
    azure = local.azure_has_ui
  }

  dns_has_api_token      = nonsensitive(local.effective_cloudflare_api_token) != ""
  dns_enabled            = (local.gcp_enabled || local.aws_enabled || local.azure_enabled) && local.dns_has_api_token && local.cloudflare_zone_id != ""
  dns_primary_has_ui     = lookup(local.cloud_has_ui, local.dns_primary_cloud, false)
  coinops_public_ip      = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
  headlamp_private_ip    = local.gcp_k3s_ingress_lb_enabled ? try(module.gcp_k3s_ingress_lb[0].ip_address, "") : ""
  headlamp_tunnel_target = local.headlamp_tunnel_enabled ? "${cloudflare_zero_trust_tunnel_cloudflared.headlamp[0].id}.cfargotunnel.com" : ""
  homepage_public_ip     = local.gcp_k3s_public_ingress_lb_enabled ? try(module.gcp_k3s_public_ingress_lb[0].ip_address, "") : ""
  # DNS is intentionally tied to the k3s ingress path; app images are not built here.
  cloudflare_dns_records = {
    root_a = {
      enabled         = local.dns_enabled && local.gcp_k3s_public_ingress_lb_enabled
      name            = local.coinops_dns_name
      content         = local.coinops_public_ip
      type            = "A"
      proxied         = local.dns_proxied
      ttl             = local.dns_ttl
      allow_overwrite = true
    }
    www_cname = {
      enabled         = local.dns_enabled && local.dns_primary_has_ui
      name            = "www"
      content         = local.app_domain
      type            = "CNAME"
      proxied         = local.dns_proxied
      ttl             = local.dns_ttl
      allow_overwrite = true
    }
    headlamp_private_a = {
      enabled         = local.dns_enabled && local.gcp_k3s_ingress_lb_enabled && !local.headlamp_tunnel_enabled
      name            = local.headlamp_dns_name
      content         = local.headlamp_private_ip
      type            = "A"
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
    homepage_public_a = {
      enabled         = local.dns_enabled && local.gcp_k3s_public_ingress_lb_enabled
      name            = local.homepage_dns_name
      content         = local.homepage_public_ip
      type            = "A"
      proxied         = false
      ttl             = local.dns_ttl
      allow_overwrite = true
    }
  }
}

module "cloudflare_dns_records" {
  count   = local.dns_enabled ? 1 : 0
  source  = "./modules/cloudflare/records"
  zone_id = local.cloudflare_zone_id
  records = local.cloudflare_dns_records
}
