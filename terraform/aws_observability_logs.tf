resource "aws_cloudwatch_log_group" "k3s_container_logs" {
  count = local.aws_compute_enabled ? 1 : 0

  name              = "/${local.project_name}/k3s/containers"
  retention_in_days = 7

  tags = {
    Project = local.project_name
    Cloud   = "aws"
  }
}
