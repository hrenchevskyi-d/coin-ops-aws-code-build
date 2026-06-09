module "aws_observability_logs" {
  count = local.aws_compute_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_logs"

  project_name      = local.project_name
  retention_in_days = 7
  tags              = local.aws_observability_tags
}
