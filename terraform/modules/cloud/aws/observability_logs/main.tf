resource "aws_cloudwatch_log_group" "k3s_container_logs" {
  name              = "/${var.project_name}/k3s/containers"
  retention_in_days = var.retention_in_days

  tags = var.tags
}
