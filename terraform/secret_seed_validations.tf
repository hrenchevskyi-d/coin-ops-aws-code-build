resource "terraform_data" "validate_seed_secret_inputs" {
  count = local.seed_secret_manager ? 1 : 0

  input = true

  lifecycle {
    precondition {
      condition = (
        !local.cloudflare_access_enabled
        || (
          trimspace(nonsensitive(var.github_oauth_client_id)) != ""
          && trimspace(nonsensitive(var.github_oauth_client_secret)) != ""
        )
      )
      error_message = "Cloudflare Access is enabled, so github_oauth_client_id and github_oauth_client_secret must be set when seed_secret_manager=true."
    }
  }
}
