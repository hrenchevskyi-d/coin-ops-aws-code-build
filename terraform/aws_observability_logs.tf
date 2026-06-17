module "aws_observability_logs" {
  count = local.aws_enabled && local.aws_observability_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_logs"

  project_name       = local.project_name
  log_group_name     = local.aws_observability_logs_cfg.container_log_group_name
  retention_in_days  = local.aws_observability_logs_cfg.retention_in_days
  log_metric_filters = local.aws_observability_log_metric_filters
  tags               = local.aws_observability_tags
}
