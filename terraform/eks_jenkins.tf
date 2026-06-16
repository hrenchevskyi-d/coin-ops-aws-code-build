resource "random_password" "jenkins_admin" {
  count   = local.jenkins_enabled ? 1 : 0
  length  = 24
  special = false
}

resource "helm_release" "jenkins" {
  count = local.jenkins_enabled ? 1 : 0

  name             = try(local.jenkins_cfg.release_name, "jenkins")
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = trimspace(try(local.jenkins_cfg.chart_version, "")) != "" ? local.jenkins_cfg.chart_version : null
  namespace        = try(local.jenkins_cfg.namespace, "jenkins")
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [
    templatefile("${path.module}/helm/jenkins/values.yaml.tftpl", {
      controller_tag       = try(local.jenkins_cfg.controller_tag, "2.555.3-jdk21")
      storage_class        = try(local.jenkins_cfg.storage_class, "gp2")
      storage_size         = try(local.jenkins_cfg.storage_size, "8Gi")
      service_account_name = try(local.jenkins_cfg.release_name, "jenkins")
      casc_config = templatefile("${path.module}/helm/jenkins/casc.yaml.tftpl", {
        namespace            = try(local.jenkins_cfg.namespace, "jenkins")
        release_name         = try(local.jenkins_cfg.release_name, "jenkins")
        public_url           = try(local.jenkins_cfg.public_url, "http://localhost:8080/")
        job_name             = try(local.jenkins_cfg.job_name, "coinops-eks-deploy")
        repository_url       = try(local.jenkins_cfg.repository_url, "")
        branch               = try(local.jenkins_cfg.branch, "main")
        admin_password       = jsonencode(random_password.jenkins_admin[0].result)
        github_username      = jsonencode(try(local.deploy.ghcr_username, ""))
        github_token         = jsonencode(nonsensitive(local.effective_ghcr_token))
        db_password          = jsonencode(nonsensitive(local.effective_db_password))
        cloudflare_api_token = jsonencode(nonsensitive(local.effective_cloudflare_api_token))
        headlamp_tunnel_token = jsonencode(
          local.headlamp_tunnel_enabled ? cloudflare_zero_trust_tunnel_cloudflared.headlamp[0].tunnel_token : ""
        )
        ansible_runtime_json = jsonencode(jsonencode({
          aws = {
            kubernetes_runtime      = "eks"
            eks_cluster_name        = module.aws_eks[0].cluster_name
            eks_kubeconfig_path     = "$${K8S_KUBECONFIG_PATH}"
            eks_pod_cidr            = local.aws_vpc_cidr
            eks_service_ipv4_cidr   = try(local.aws_eks_cfg.service_ipv4_cidr, "10.43.0.0/16")
            headlamp_tunnel_enabled = local.headlamp_tunnel_enabled
            headlamp_tunnel_token   = local.headlamp_tunnel_enabled ? cloudflare_zero_trust_tunnel_cloudflared.headlamp[0].tunnel_token : ""
            headlamp_public_host    = local.headlamp_domain
            coinops_tunnel_enabled  = local.coinops_tunnel_enabled
            coinops_public_host     = local.coinops_domain
            homepage_public_host    = local.homepage_domain
            database = {
              host    = ""
              port    = local.db_port
              name    = local.db_name
              user    = local.db_username
              managed = false
            }
            cnpg_backup = {
              provider         = "s3"
              enabled          = local.aws_cnpg_backup_enabled
              bucket           = local.aws_cnpg_backup_bucket_name
              destination_path = local.aws_cnpg_backup_destination
              schedule         = local.cnpg_backup_schedule
              retention_policy = local.cnpg_backup_retention
              region           = local.aws_region
            }
          }
        }))
        cnpg_backup_s3_access_key_id     = jsonencode(nonsensitive(local.effective_cnpg_backup_s3_access_key_id))
        cnpg_backup_s3_secret_access_key = jsonencode(nonsensitive(local.effective_cnpg_backup_s3_secret_access_key))
      })
    })
  ]

  depends_on = [module.aws_eks]
}

resource "kubernetes_cluster_role_binding" "jenkins_cluster_admin" {
  count = local.jenkins_enabled ? 1 : 0

  metadata {
    name = "${try(local.jenkins_cfg.release_name, "jenkins")}-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = try(local.jenkins_cfg.release_name, "jenkins")
    namespace = try(local.jenkins_cfg.namespace, "jenkins")
  }

  depends_on = [helm_release.jenkins]
}
