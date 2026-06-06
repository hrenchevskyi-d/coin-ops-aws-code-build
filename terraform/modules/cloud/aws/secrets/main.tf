# Secret JSON keys are consumed by ansible/roles/runtime_config.
resource "aws_secretsmanager_secret" "db_secrets" {
  name                    = var.db_secret_name
  recovery_window_in_days = 7

  tags = {
    Name = var.db_secret_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "db_secrets_data" {
  secret_id = aws_secretsmanager_secret.db_secrets.id

  secret_string = jsonencode({
    DB_PASSWORD       = var.db_password
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = var.app_secret_name
  recovery_window_in_days = 7

  tags = {
    Name = var.app_secret_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets_data" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  secret_string = jsonencode({
    GHCR_TOKEN                       = var.ghcr_token
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token
    TAILSCALE_AUTH_KEY               = var.tailscale_auth_key
    GITHUB_OAUTH_CLIENT_ID           = var.github_oauth_client_id
    GITHUB_OAUTH_CLIENT_SECRET       = var.github_oauth_client_secret
    CNPG_BACKUP_S3_ACCESS_KEY_ID     = var.cnpg_backup_s3_access_key_id
    CNPG_BACKUP_S3_SECRET_ACCESS_KEY = var.cnpg_backup_s3_secret_access_key
  })
}
