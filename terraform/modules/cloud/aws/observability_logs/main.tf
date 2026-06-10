resource "aws_cloudwatch_log_group" "k3s_container_logs" {
  name              = var.log_group_name
  retention_in_days = var.retention_in_days

  tags = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "log_metric_filters" {
  for_each = var.log_metric_filters

  name           = each.value.name
  log_group_name = aws_cloudwatch_log_group.k3s_container_logs.name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric_name
    namespace = each.value.namespace
    value     = try(each.value.value, "1")
  }
}
