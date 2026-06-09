resource "aws_cloudwatch_log_metric_filter" "container_log_events" {
  name           = "${var.project_name}-container-log-events"
  log_group_name = var.container_log_group_name
  pattern        = "{ $.kubernetes.container_name = * }"

  metric_transformation {
    name      = "ContainerLogEvents"
    namespace = "CoinOps/K3s"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "traefik_request_count" {
  name           = "${var.project_name}-traefik-request-count"
  log_group_name = var.container_log_group_name
  pattern        = "{ $.kubernetes.container_name = \"traefik\" && $.log_processed.DownstreamStatus = * }"

  metric_transformation {
    name      = "RequestCount"
    namespace = "CoinOps/Traefik"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "traefik_downstream_5xx_count" {
  name           = "${var.project_name}-traefik-downstream-5xx-count"
  log_group_name = var.container_log_group_name
  pattern        = "{ $.kubernetes.container_name = \"traefik\" && $.log_processed.DownstreamStatus >= 500 && $.log_processed.DownstreamStatus < 600 }"

  metric_transformation {
    name      = "Downstream5xxCount"
    namespace = "CoinOps/Traefik"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "traefik_origin_5xx_count" {
  name           = "${var.project_name}-traefik-origin-5xx-count"
  log_group_name = var.container_log_group_name
  pattern        = "{ $.kubernetes.container_name = \"traefik\" && $.log_processed.OriginStatus >= 500 && $.log_processed.OriginStatus < 600 }"

  metric_transformation {
    name      = "Origin5xxCount"
    namespace = "CoinOps/Traefik"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "traefik_downstream_5xx" {
  alarm_name          = "${var.project_name}-traefik-downstream-5xx"
  alarm_description   = "Traefik returned downstream 5xx responses."
  namespace           = "CoinOps/Traefik"
  metric_name         = "Downstream5xxCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "traefik_origin_5xx" {
  alarm_name          = "${var.project_name}-traefik-origin-5xx"
  alarm_description   = "Traefik observed origin 5xx responses."
  namespace           = "CoinOps/Traefik"
  metric_name         = "Origin5xxCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "container_logs_silent" {
  alarm_name          = "${var.project_name}-container-logs-silent"
  alarm_description   = "No Kubernetes container logs reached CloudWatch for ${var.container_log_silence_minutes} minutes."
  namespace           = "CoinOps/K3s"
  metric_name         = "ContainerLogEvents"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = ceil(var.container_log_silence_minutes / 5)
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}
