# Optional Headlamp tunnel; app ingress uses the normal k3s path.
resource "random_bytes" "headlamp_tunnel_secret" {
  count  = local.headlamp_tunnel_enabled ? 1 : 0
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "headlamp" {
  count      = local.headlamp_tunnel_enabled ? 1 : 0
  account_id = local.cloudflare_account_id
  name       = local.headlamp_tunnel_name
  secret     = random_bytes.headlamp_tunnel_secret[0].base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "headlamp" {
  count      = local.headlamp_tunnel_enabled ? 1 : 0
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.headlamp[0].id

  config {
    ingress_rule {
      hostname = local.headlamp_domain
      service  = try(local.headlamp_tunnel_cfg.service, "http://headlamp.headlamp.svc.cluster.local:80")
    }

    # Required catch-all: without it cloudflared may forward unknown hostnames.
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "github" {
  count      = local.headlamp_access_enabled ? 1 : 0
  account_id = local.cloudflare_account_id
  name       = local.headlamp_access_identity_provider_name
  type       = "github"

  config {
    client_id     = local.effective_github_oauth_client_id
    client_secret = local.effective_github_oauth_client_secret
  }
}

resource "cloudflare_zero_trust_access_application" "headlamp" {
  count      = local.headlamp_access_enabled ? 1 : 0
  account_id = local.cloudflare_account_id
  name       = local.headlamp_access_application_name
  domain     = local.headlamp_domain
  type       = "self_hosted"

  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "headlamp" {
  count          = local.headlamp_access_enabled ? 1 : 0
  account_id     = local.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.headlamp[0].id
  name           = local.headlamp_access_policy_name
  decision       = "allow"
  precedence     = 1

  # Empty allowed_emails means any GitHub-authenticated user can pass Access.
  dynamic "include" {
    for_each = length(local.headlamp_access_allowed_emails) > 0 ? [local.headlamp_access_allowed_emails] : []
    content {
      email = include.value
    }
  }

  dynamic "include" {
    for_each = length(local.headlamp_access_allowed_emails) == 0 ? [true] : []
    content {
      everyone = include.value
    }
  }

  require {
    login_method = [cloudflare_zero_trust_access_identity_provider.github[0].id]
  }
}
