locals {
  alert_actions = [aws_sns_topic.observability_alerts.arn]

  ec2_alarm_instances = (
    length(var.ec2_alarms) == 0 || length(var.instance_ids) == 0
    ? {}
    : merge([
      for alarm_key, alarm in var.ec2_alarms : {
        for instance_name, instance_id in var.instance_ids : "${alarm_key}:${instance_name}" => {
          alarm_key     = alarm_key
          alarm         = alarm
          instance_name = instance_name
          instance_id   = instance_id
        }
        if try(alarm.enabled, true)
      }
    ]...)
  )

  nlb_target_group_dimensions = {
    LoadBalancer = var.public_ingress_nlb.load_balancer_arn_suffix
    TargetGroup  = var.public_ingress_nlb.target_group_arn_suffix
  }

  nlb_load_balancer_dimensions = {
    LoadBalancer = var.public_ingress_nlb.load_balancer_arn_suffix
  }

  nlb_alarms = {
    for alarm_key, alarm in var.nlb_alarms : alarm_key => alarm
    if var.public_ingress_nlb.enabled && try(alarm.enabled, true)
  }

  eks_cluster_dimensions = {
    ClusterName = var.eks_cluster.cluster_name
  }

  eks_node_group_dimensions = {
    ClusterName   = var.eks_cluster.cluster_name
    NodegroupName = var.eks_cluster.node_group_name
  }

  eks_alarms = {
    for alarm_key, alarm in var.eks_alarms : alarm_key => alarm
    if var.eks_cluster.enabled && try(alarm.enabled, true)
  }

  nat_gateway_dimensions = {
    NatGatewayId = var.nat_gateway.nat_gateway_id
  }

  nat_gateway_alarms = {
    for alarm_key, alarm in var.nat_gateway_alarms : alarm_key => alarm
    if var.nat_gateway.enabled && try(alarm.enabled, true)
  }

  log_metric_alarms = {
    for alarm_key, alarm in var.log_metric_alarms : alarm_key => merge(
      alarm,
      var.log_metric_definitions[alarm.metric_key]
    )
    if try(alarm.enabled, true)
  }

  container_log_metric_namespace = try(var.log_metric_definitions.container_log_events.namespace, "CoinOps/Kubernetes")
  container_log_metric_name      = try(var.log_metric_definitions.container_log_events.metric_name, "ContainerLogEvents")
  traefik_request_namespace      = try(var.log_metric_definitions.traefik_request_count.namespace, "CoinOps/Traefik")
  traefik_request_metric_name    = try(var.log_metric_definitions.traefik_request_count.metric_name, "RequestCount")
  traefik_downstream_namespace   = try(var.log_metric_definitions.traefik_downstream_5xx_count.namespace, "CoinOps/Traefik")
  traefik_downstream_metric_name = try(var.log_metric_definitions.traefik_downstream_5xx_count.metric_name, "Downstream5xxCount")
  traefik_origin_namespace       = try(var.log_metric_definitions.traefik_origin_5xx_count.namespace, "CoinOps/Traefik")
  traefik_origin_metric_name     = try(var.log_metric_definitions.traefik_origin_5xx_count.metric_name, "Origin5xxCount")

  ec2_cpu_metrics = [
    for instance_name, instance_id in var.instance_ids :
    ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id, { label = instance_name }]
  ]

  ec2_memory_metrics = [
    for instance_name, instance_id in var.instance_ids :
    ["CWAgent", "mem_used_percent", "InstanceId", instance_id, { label = instance_name }]
  ]

  ec2_disk_metrics = [
    for instance_name, instance_id in var.instance_ids :
    ["CWAgent", "disk_used_percent", "InstanceId", instance_id, { label = instance_name }]
  ]

  ec2_widgets = [
    for widget in [
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
          region  = var.aws_region
          period  = 300
          stat    = "Average"
          metrics = local.ec2_cpu_metrics
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
          region  = var.aws_region
          period  = 300
          stat    = "Average"
          metrics = local.ec2_memory_metrics
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
          region  = var.aws_region
          period  = 300
          stat    = "Maximum"
          metrics = local.ec2_disk_metrics
        }
      }
    ] : widget if length(var.instance_ids) > 0
  ]

  kubernetes_log_widgets = [
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
        region  = var.aws_region
        period  = 60
        metrics = [
          [local.traefik_request_namespace, local.traefik_request_metric_name, { label = "Requests", stat = "Sum" }],
          [local.traefik_downstream_namespace, local.traefik_downstream_metric_name, { label = "Downstream 5xx", stat = "Sum" }],
          [local.traefik_origin_namespace, local.traefik_origin_metric_name, { label = "Origin 5xx", stat = "Sum" }]
        ]
      }
    }
  ]

  public_ingress_nlb_widgets = [
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
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/NetworkELB", "HealthyHostCount", "LoadBalancer", var.public_ingress_nlb.load_balancer_arn_suffix, "TargetGroup", var.public_ingress_nlb.target_group_arn_suffix, { label = "Healthy targets", stat = "Minimum" }],
            ["AWS/NetworkELB", "UnHealthyHostCount", "LoadBalancer", var.public_ingress_nlb.load_balancer_arn_suffix, "TargetGroup", var.public_ingress_nlb.target_group_arn_suffix, { label = "Unhealthy targets", stat = "Maximum" }]
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
          region  = var.aws_region
          period  = 60
          metrics = [
            ["AWS/NetworkELB", "RejectedFlowCount", "LoadBalancer", var.public_ingress_nlb.load_balancer_arn_suffix, { label = "Rejected flows", stat = "Sum" }],
            ["AWS/NetworkELB", "PortAllocationErrorCount", "LoadBalancer", var.public_ingress_nlb.load_balancer_arn_suffix, { label = "Port allocation errors", stat = "Sum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 12
        height = 6
        properties = {
          title   = "Public ingress NLB traffic"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["AWS/NetworkELB", "ProcessedBytes", "LoadBalancer", var.public_ingress_nlb.load_balancer_arn_suffix, { label = "Processed bytes", stat = "Sum" }],
            [".", "PeakBytesPerSecond", ".", ".", { label = "Peak bytes/sec", stat = "Maximum" }],
            [".", "ProcessedPackets", ".", ".", { label = "Processed packets", stat = "Sum", yAxis = "right" }],
            [".", "PeakPacketsPerSecond", ".", ".", { label = "Peak packets/sec", stat = "Maximum", yAxis = "right" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 20
        width  = 12
        height = 6
        properties = {
          title   = "Public ingress NLB flows"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["AWS/NetworkELB", "NewFlowCount", "LoadBalancer", var.public_ingress_nlb.load_balancer_arn_suffix, { label = "New flows", stat = "Sum" }],
            [".", "ActiveFlowCount", ".", ".", { label = "Active flows", stat = "Maximum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 26
        width  = 12
        height = 6
        properties = {
          title   = "Public ingress NLB TCP resets"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["AWS/NetworkELB", "TCP_Client_Reset_Count", "LoadBalancer", var.public_ingress_nlb.load_balancer_arn_suffix, { label = "Client resets", stat = "Sum" }],
            [".", "TCP_Target_Reset_Count", ".", ".", { label = "Target resets", stat = "Sum" }],
            [".", "TCP_ELB_Reset_Count", ".", ".", { label = "NLB resets", stat = "Sum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 26
        width  = 12
        height = 6
        properties = {
          title   = "Kubernetes container logs"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            [local.container_log_metric_namespace, local.container_log_metric_name, { label = "Container log events", stat = "Sum" }],
            [local.traefik_request_namespace, local.traefik_request_metric_name, { label = "Traefik access logs", stat = "Sum", yAxis = "right" }]
          ]
        }
      }
    ] : widget if var.public_ingress_nlb.enabled
  ]

  eks_widgets = [
    for widget in [
      {
        type   = "metric"
        x      = 0
        y      = 32
        width  = 12
        height = 6
        properties = {
          title   = "EKS cluster nodes"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", var.eks_cluster.cluster_name, { label = "Node count", stat = "Average" }],
            [".", "cluster_failed_node_count", ".", ".", { label = "Failed nodes", stat = "Maximum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 32
        width  = 12
        height = 6
        properties = {
          title   = "EKS pod health"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["ContainerInsights", "pod_number_of_container_restarts", "ClusterName", var.eks_cluster.cluster_name, { label = "Container restarts", stat = "Sum" }],
            [".", "pod_status_failed", ".", ".", { label = "Failed pods", stat = "Maximum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 38
        width  = 12
        height = 6
        properties = {
          title   = "EKS node CPU and memory"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.eks_cluster.cluster_name, { label = "Node CPU %", stat = "Average" }],
            [".", "node_memory_utilization", ".", ".", { label = "Node memory %", stat = "Average", yAxis = "right" }]
          ]
        }
      }
    ] : widget if var.eks_cluster.enabled
  ]

  nat_gateway_widgets = [
    for widget in [
      {
        type   = "metric"
        x      = 0
        y      = 44
        width  = 12
        height = 6
        properties = {
          title   = "NAT Gateway traffic"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", var.nat_gateway.nat_gateway_id, { label = "Bytes out", stat = "Sum" }],
            [".", "BytesInFromDestination", ".", ".", { label = "Bytes in", stat = "Sum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 44
        width  = 12
        height = 6
        properties = {
          title   = "NAT Gateway drops and errors"
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          metrics = [
            ["AWS/NATGateway", "PacketsDropCount", "NatGatewayId", var.nat_gateway.nat_gateway_id, { label = "Dropped packets", stat = "Sum" }],
            [".", "ErrorPortAllocation", ".", ".", { label = "Port allocation errors", stat = "Sum" }]
          ]
        }
      }
    ] : widget if var.nat_gateway.enabled
  ]
}

resource "aws_sns_topic" "observability_alerts" {
  name = "${var.project_name}-observability-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "observability_alert_email" {
  count = trimspace(var.alert_email) == "" ? 0 : 1

  topic_arn = aws_sns_topic.observability_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_ssm_parameter" "cloudwatch_agent_linux" {
  name      = var.cloudwatch_agent_parameter
  type      = "String"
  value     = jsonencode(var.cloudwatch_agent_config)
  overwrite = true
  tags      = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ec2" {
  for_each = local.ec2_alarm_instances

  alarm_name          = "${var.project_name}-${each.value.instance_name}-${each.value.alarm.name_suffix}"
  alarm_description   = replace(try(each.value.alarm.description, ""), "{instance_name}", each.value.instance_name)
  namespace           = each.value.alarm.namespace
  metric_name         = each.value.alarm.metric_name
  dimensions          = { InstanceId = each.value.instance_id }
  statistic           = each.value.alarm.statistic
  period              = each.value.alarm.period
  evaluation_periods  = each.value.alarm.evaluation_periods
  threshold           = each.value.alarm.threshold
  comparison_operator = each.value.alarm.comparison_operator
  treat_missing_data  = try(each.value.alarm.treat_missing_data, "notBreaching")
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "nlb" {
  for_each = local.nlb_alarms

  alarm_name        = "${var.project_name}-${each.value.name_suffix}"
  alarm_description = try(each.value.description, "")
  namespace         = each.value.namespace
  metric_name       = each.value.metric_name
  dimensions = (
    try(each.value.dimension_scope, "load_balancer") == "target_group"
    ? local.nlb_target_group_dimensions
    : local.nlb_load_balancer_dimensions
  )
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  threshold           = try(each.value.threshold_source, "") == "target_count" ? var.public_ingress_nlb.target_count : each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = try(each.value.treat_missing_data, "notBreaching")
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "eks" {
  for_each = local.eks_alarms

  alarm_name        = "${var.project_name}-${each.value.name_suffix}"
  alarm_description = try(each.value.description, "")
  namespace         = each.value.namespace
  metric_name       = each.value.metric_name
  dimensions = (
    try(each.value.dimension_scope, "cluster") == "node_group"
    ? local.eks_node_group_dimensions
    : local.eks_cluster_dimensions
  )
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  threshold           = try(each.value.threshold_source, "") == "desired_node_count" ? var.eks_cluster.desired_nodes : each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = try(each.value.treat_missing_data, "notBreaching")
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "nat_gateway" {
  for_each = local.nat_gateway_alarms

  alarm_name          = "${var.project_name}-${each.value.name_suffix}"
  alarm_description   = try(each.value.description, "")
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = local.nat_gateway_dimensions
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = try(each.value.treat_missing_data, "notBreaching")
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "log_metric" {
  for_each = local.log_metric_alarms

  alarm_name          = "${var.project_name}-${each.value.name_suffix}"
  alarm_description   = try(each.value.description, "")
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = try(each.value.treat_missing_data, "notBreaching")
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
  tags                = var.tags
}

resource "aws_cloudwatch_dashboard" "observability" {
  count = var.dashboard_enabled ? 1 : 0

  dashboard_name = "${var.project_name}-observability"
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
            markdown = "# ${var.project_name} observability\nAWS EC2/k3s, EKS, NAT Gateway, public ingress, and Kubernetes log-derived metrics."
          }
        }
      ],
      local.ec2_widgets,
      local.kubernetes_log_widgets,
      local.public_ingress_nlb_widgets,
      local.eks_widgets,
      local.nat_gateway_widgets
    )
  })
}
