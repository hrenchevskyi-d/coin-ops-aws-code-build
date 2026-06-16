# Provider settings come from locals built from terraform/config/*.json.
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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
  # Cloudflare validates this during init; placeholder keeps disabled plans usable.
  api_token = local.cloudflare_provider_api_token
}

provider "google" {
  project      = local.gcp_project_id
  region       = local.gcp_region
  access_token = local.gcp_enabled ? null : "disabled-provider-placeholder"
}


provider "kubernetes" {
  host                   = local.aws_eks_enabled ? module.aws_eks[0].cluster_endpoint : "https://127.0.0.1"
  cluster_ca_certificate = local.aws_eks_enabled ? base64decode(module.aws_eks[0].cluster_ca_certificate) : ""

  dynamic "exec" {
    for_each = local.aws_eks_enabled ? [1] : []
    content {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.aws_eks[0].cluster_name, "--region", local.aws_region]
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = local.aws_eks_enabled ? module.aws_eks[0].cluster_endpoint : "https://127.0.0.1"
    cluster_ca_certificate = local.aws_eks_enabled ? base64decode(module.aws_eks[0].cluster_ca_certificate) : ""

    dynamic "exec" {
      for_each = local.aws_eks_enabled ? [1] : []
      content {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", module.aws_eks[0].cluster_name, "--region", local.aws_region]
      }
    }
  }
}

