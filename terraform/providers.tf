# Providers are configured from merged JSON locals so switching clouds is a
# config change, not a code edit. Placeholder tokens avoid provider init failures.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = local.azure_subscription_id != "" ? local.azure_subscription_id : null
  tenant_id       = local.azure_tenant_id != "" ? local.azure_tenant_id : null
}

provider "aws" {
  region = local.aws_region
}

provider "cloudflare" {
  # The provider validates token shape during init even when Cloudflare resources
  # are disabled, so use a harmless placeholder until secrets are resolved.
  api_token = trimspace(local.effective_cloudflare_api_token != "" ? local.effective_cloudflare_api_token : "placeholder_token")
}

provider "google" {
  project = local.gcp_project_id
  region  = local.gcp_region
}
