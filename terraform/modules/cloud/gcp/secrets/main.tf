# Secret Manager versions are updated from effective Terraform values. Reads
# are gated in locals.tf to avoid read-before-create during seed flows.
resource "google_secret_manager_secret" "db_secrets" {
  secret_id = var.db_secret_name

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_version" "db_secrets_data" {
  secret = google_secret_manager_secret.db_secrets.id

  secret_data = jsonencode({
    DB_PASSWORD       = var.db_password
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
}

resource "google_secret_manager_secret" "app_secrets" {
  secret_id = var.app_secret_name

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_version" "app_secrets_data" {
  secret = google_secret_manager_secret.app_secrets.id

  secret_data = jsonencode({
    GHCR_TOKEN                  = var.ghcr_token
    CLOUDFLARE_API_TOKEN        = var.cloudflare_api_token
    TAILSCALE_AUTH_KEY          = var.tailscale_auth_key
    GITHUB_OAUTH_CLIENT_ID      = var.github_oauth_client_id
    GITHUB_OAUTH_CLIENT_SECRET  = var.github_oauth_client_secret
    CNPG_BACKUP_GCS_CREDENTIALS = var.cnpg_backup_gcs_credentials
  })
}
