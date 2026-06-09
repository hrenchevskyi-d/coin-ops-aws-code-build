locals {
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
            ["CoinOps/K3s", "ContainerLogEvents", { label = "Container log events", stat = "Sum" }],
            ["CoinOps/Traefik", "RequestCount", { label = "Traefik access logs", stat = "Sum", yAxis = "right" }]
          ]
        }
      }
    ] : widget if var.public_ingress_nlb.enabled
  ]
}

resource "aws_cloudwatch_dashboard" "observability" {
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
            markdown = "# ${var.project_name} observability\nAWS EC2, CloudWatch Agent, public ingress NLB, and Traefik access-log metrics."
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
            region  = var.aws_region
            period  = 60
            metrics = [
              ["CoinOps/Traefik", "RequestCount", { label = "Requests", stat = "Sum" }],
              ["CoinOps/Traefik", "Downstream5xxCount", { label = "Downstream 5xx", stat = "Sum" }],
              ["CoinOps/Traefik", "Origin5xxCount", { label = "Origin 5xx", stat = "Sum" }]
            ]
          }
        }
      ],
      local.public_ingress_nlb_widgets
    )
  })
}
