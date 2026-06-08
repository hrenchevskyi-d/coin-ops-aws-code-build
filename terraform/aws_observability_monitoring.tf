locals {
  aws_observability_enabled = local.aws_compute_enabled

  aws_observability_tags = {
    Project = local.project_name
    Cloud   = "aws"
  }

  aws_observability_alert_email       = "grenchevskiyd@gmail.com"
  aws_cloudwatch_agent_parameter_name = "/${local.project_name}/cloudwatch-agent/linux"
  aws_k3s_container_log_group_name    = "/${local.project_name}/k3s/containers"

  aws_cloudwatch_agent_config = {
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      aggregation_dimensions = [
        ["InstanceId"]
      ]
      metrics_collected = {
        mem = {
          measurement = [
            "mem_used_percent"
          ]
          metrics_collection_interval = 60
        }
        disk = {
          measurement = [
            "used_percent",
            "inodes_free",
            "inodes_used",
            "inodes_total"
          ]
          metrics_collection_interval = 60
          resources = [
            "/"
          ]
          drop_device = true
        }
        swap = {
          measurement = [
            "swap_used_percent"
          ]
          metrics_collection_interval = 60
        }
      }
    }
  }

  aws_observability_instance_ids = local.aws_compute_enabled ? {
    for name in keys(local.aws_instances_cfg) : name => module.aws_instances[0].instance_ids[name]
  } : {}

  aws_k3s_public_ingress_target_count = length(local.aws_k3s_server_names)
  aws_k3s_public_ingress_nlb_dimensions = local.aws_k3s_public_ingress_lb_enabled ? {
    LoadBalancer = module.aws_k3s_public_ingress_lb[0].arn_suffix
    TargetGroup  = module.aws_k3s_public_ingress_lb[0].target_group_arn_suffix
  } : {}
  aws_k3s_public_ingress_nlb_lb_dimensions = local.aws_k3s_public_ingress_lb_enabled ? {
    LoadBalancer = module.aws_k3s_public_ingress_lb[0].arn_suffix
  } : {}

  aws_observability_ec2_cpu_dashboard_metrics = [
    for instance_name, instance_id in local.aws_observability_instance_ids :
    ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id, { label = instance_name }]
  ]
  aws_observability_ec2_memory_dashboard_metrics = [
    for instance_name, instance_id in local.aws_observability_instance_ids :
    ["CWAgent", "mem_used_percent", "InstanceId", instance_id, { label = instance_name }]
  ]
  aws_observability_ec2_disk_dashboard_metrics = [
    for instance_name, instance_id in local.aws_observability_instance_ids :
    ["CWAgent", "disk_used_percent", "InstanceId", instance_id, { label = instance_name }]
  ]
}

resource "aws_sns_topic" "observability_alerts" {
  count = local.aws_observability_enabled ? 1 : 0

  name = "${local.project_name}-observability-alerts"
  tags = local.aws_observability_tags
}

resource "aws_sns_topic_subscription" "observability_alert_email" {
  count = local.aws_observability_enabled ? 1 : 0

  topic_arn = aws_sns_topic.observability_alerts[0].arn
  protocol  = "email"
  endpoint  = local.aws_observability_alert_email
}

resource "aws_ssm_parameter" "cloudwatch_agent_linux" {
  count = local.aws_observability_enabled ? 1 : 0

  name      = local.aws_cloudwatch_agent_parameter_name
  type      = "String"
  value     = jsonencode(local.aws_cloudwatch_agent_config)
  overwrite = true
  tags      = local.aws_observability_tags
}

resource "aws_cloudwatch_log_metric_filter" "traefik_request_count" {
  count = local.aws_observability_enabled ? 1 : 0

  name           = "${local.project_name}-traefik-request-count"
  log_group_name = aws_cloudwatch_log_group.k3s_container_logs[0].name
  pattern        = "{ $.kubernetes.container_name = \"traefik\" && $.log_processed.DownstreamStatus = * }"

  metric_transformation {
    name      = "RequestCount"
    namespace = "CoinOps/Traefik"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "traefik_downstream_5xx_count" {
  count = local.aws_observability_enabled ? 1 : 0

  name           = "${local.project_name}-traefik-downstream-5xx-count"
  log_group_name = aws_cloudwatch_log_group.k3s_container_logs[0].name
  pattern        = "{ $.kubernetes.container_name = \"traefik\" && $.log_processed.DownstreamStatus >= 500 && $.log_processed.DownstreamStatus < 600 }"

  metric_transformation {
    name      = "Downstream5xxCount"
    namespace = "CoinOps/Traefik"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "traefik_origin_5xx_count" {
  count = local.aws_observability_enabled ? 1 : 0

  name           = "${local.project_name}-traefik-origin-5xx-count"
  log_group_name = aws_cloudwatch_log_group.k3s_container_logs[0].name
  pattern        = "{ $.kubernetes.container_name = \"traefik\" && $.log_processed.OriginStatus >= 500 && $.log_processed.OriginStatus < 600 }"

  metric_transformation {
    name      = "Origin5xxCount"
    namespace = "CoinOps/Traefik"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "traefik_downstream_5xx" {
  count = local.aws_observability_enabled ? 1 : 0

  alarm_name          = "${local.project_name}-traefik-downstream-5xx"
  alarm_description   = "Traefik returned downstream 5xx responses."
  namespace           = "CoinOps/Traefik"
  metric_name         = "Downstream5xxCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "traefik_origin_5xx" {
  count = local.aws_observability_enabled ? 1 : 0

  alarm_name          = "${local.project_name}-traefik-origin-5xx"
  alarm_description   = "Traefik observed origin 5xx responses."
  namespace           = "CoinOps/Traefik"
  metric_name         = "Origin5xxCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_unhealthy_targets" {
  count = local.aws_k3s_public_ingress_lb_enabled ? 1 : 0

  alarm_name          = "${local.project_name}-k3s-public-ingress-nlb-unhealthy-targets"
  alarm_description   = "Public k3s ingress NLB has unhealthy targets."
  namespace           = "AWS/NetworkELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.aws_k3s_public_ingress_nlb_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_healthy_target_count" {
  count = local.aws_k3s_public_ingress_lb_enabled ? 1 : 0

  alarm_name          = "${local.project_name}-k3s-public-ingress-nlb-healthy-target-count"
  alarm_description   = "Public k3s ingress NLB healthy target count is below the configured server count."
  namespace           = "AWS/NetworkELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.aws_k3s_public_ingress_nlb_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = local.aws_k3s_public_ingress_target_count
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_rejected_flows" {
  count = local.aws_k3s_public_ingress_lb_enabled ? 1 : 0

  alarm_name          = "${local.project_name}-k3s-public-ingress-nlb-rejected-flows"
  alarm_description   = "Public k3s ingress NLB rejected flows."
  namespace           = "AWS/NetworkELB"
  metric_name         = "RejectedFlowCount_TCP"
  dimensions          = local.aws_k3s_public_ingress_nlb_lb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_port_allocation_errors" {
  count = local.aws_k3s_public_ingress_lb_enabled ? 1 : 0

  alarm_name          = "${local.project_name}-k3s-public-ingress-nlb-port-allocation-errors"
  alarm_description   = "Public k3s ingress NLB had port allocation errors."
  namespace           = "AWS/NetworkELB"
  metric_name         = "PortAllocationErrorCount"
  dimensions          = local.aws_k3s_public_ingress_nlb_lb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu_utilization" {
  for_each = local.aws_observability_enabled ? local.aws_observability_instance_ids : {}

  alarm_name          = "${local.project_name}-${each.key}-ec2-cpu-utilization"
  alarm_description   = "EC2 CPU utilization is above 85% on ${each.key}."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  for_each = local.aws_observability_enabled ? local.aws_observability_instance_ids : {}

  alarm_name          = "${local.project_name}-${each.key}-ec2-status-check-failed"
  alarm_description   = "EC2 instance or system status check failed on ${each.key}."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_memory_used_percent" {
  for_each = local.aws_observability_enabled ? local.aws_observability_instance_ids : {}

  alarm_name          = "${local.project_name}-${each.key}-ec2-memory-used-percent"
  alarm_description   = "EC2 memory usage is above 85% on ${each.key}."
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}

resource "aws_cloudwatch_dashboard" "observability" {
  count = local.aws_observability_enabled ? 1 : 0

  dashboard_name = "${local.project_name}-observability"
  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "text"
          x      = 0
          y      = 0
          width  = 24
          height = 2
          properties = {
            markdown = "# ${local.project_name} observability\nAWS EC2, CloudWatch Agent, public ingress NLB, and Traefik access-log metrics."
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 2
          width  = 12
          height = 6
          properties = {
            title   = "EC2 CPU utilization"
            view    = "timeSeries"
            stacked = false
            region  = local.aws_region
            period  = 300
            stat    = "Average"
            metrics = local.aws_observability_ec2_cpu_dashboard_metrics
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 2
          width  = 12
          height = 6
          properties = {
            title   = "EC2 memory usage"
            view    = "timeSeries"
            stacked = false
            region  = local.aws_region
            period  = 300
            stat    = "Average"
            metrics = local.aws_observability_ec2_memory_dashboard_metrics
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 8
          width  = 12
          height = 6
          properties = {
            title   = "EC2 disk usage"
            view    = "timeSeries"
            stacked = false
            region  = local.aws_region
            period  = 300
            stat    = "Maximum"
            metrics = local.aws_observability_ec2_disk_dashboard_metrics
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 8
          width  = 12
          height = 6
          properties = {
            title   = "Traefik requests and 5xx responses"
            view    = "timeSeries"
            stacked = false
            region  = local.aws_region
            period  = 60
            metrics = [
              ["CoinOps/Traefik", "RequestCount", { label = "Requests", stat = "Sum" }],
              ["CoinOps/Traefik", "Downstream5xxCount", { label = "Downstream 5xx", stat = "Sum" }],
              ["CoinOps/Traefik", "Origin5xxCount", { label = "Origin 5xx", stat = "Sum" }]
            ]
          }
        }
      ],
      [
        for widget in [
          {
            type   = "metric"
            x      = 0
            y      = 14
            width  = 12
            height = 6
            properties = {
              title   = "Public ingress NLB target health"
              view    = "timeSeries"
              stacked = false
              region  = local.aws_region
              period  = 60
              metrics = [
                ["AWS/NetworkELB", "HealthyHostCount", "LoadBalancer", try(module.aws_k3s_public_ingress_lb[0].arn_suffix, ""), "TargetGroup", try(module.aws_k3s_public_ingress_lb[0].target_group_arn_suffix, ""), { label = "Healthy targets", stat = "Minimum" }],
                ["AWS/NetworkELB", "UnHealthyHostCount", "LoadBalancer", try(module.aws_k3s_public_ingress_lb[0].arn_suffix, ""), "TargetGroup", try(module.aws_k3s_public_ingress_lb[0].target_group_arn_suffix, ""), { label = "Unhealthy targets", stat = "Maximum" }]
              ]
            }
          },
          {
            type   = "metric"
            x      = 12
            y      = 14
            width  = 12
            height = 6
            properties = {
              title   = "Public ingress NLB errors"
              view    = "timeSeries"
              stacked = false
              region  = local.aws_region
              period  = 60
              metrics = [
                ["AWS/NetworkELB", "RejectedFlowCount_TCP", "LoadBalancer", try(module.aws_k3s_public_ingress_lb[0].arn_suffix, ""), { label = "Rejected TCP flows", stat = "Sum" }],
                ["AWS/NetworkELB", "PortAllocationErrorCount", "LoadBalancer", try(module.aws_k3s_public_ingress_lb[0].arn_suffix, ""), { label = "Port allocation errors", stat = "Sum" }]
              ]
            }
          }
        ] : widget if local.aws_k3s_public_ingress_lb_enabled
      ]
    )
  })
}

resource "aws_cloudwatch_metric_alarm" "ec2_disk_used_percent" {
  for_each = local.aws_observability_enabled ? local.aws_observability_instance_ids : {}

  alarm_name          = "${local.project_name}-${each.key}-ec2-disk-used-percent"
  alarm_description   = "EC2 disk usage is above 85% on ${each.key}."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = each.value }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.observability_alerts[0].arn]
  ok_actions          = [aws_sns_topic.observability_alerts[0].arn]
  tags                = local.aws_observability_tags
}
