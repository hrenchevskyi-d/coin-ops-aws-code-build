locals {
  public_ingress_nlb_dimensions = {
    LoadBalancer = var.public_ingress_nlb.load_balancer_arn_suffix
    TargetGroup  = var.public_ingress_nlb.target_group_arn_suffix
  }

  public_ingress_nlb_lb_dimensions = {
    LoadBalancer = var.public_ingress_nlb.load_balancer_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_unhealthy_targets" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-unhealthy-targets"
  alarm_description   = "Public k3s ingress NLB has unhealthy targets."
  namespace           = "AWS/NetworkELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.public_ingress_nlb_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_healthy_target_count" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-healthy-target-count"
  alarm_description   = "Public k3s ingress NLB healthy target count is below the configured server count."
  namespace           = "AWS/NetworkELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.public_ingress_nlb_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.public_ingress_nlb.target_count
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_rejected_flows" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-rejected-flows"
  alarm_description   = "Public k3s ingress NLB rejected flows."
  namespace           = "AWS/NetworkELB"
  metric_name         = "RejectedFlowCount"
  dimensions          = local.public_ingress_nlb_lb_dimensions
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

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_port_allocation_errors" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-port-allocation-errors"
  alarm_description   = "Public k3s ingress NLB had port allocation errors."
  namespace           = "AWS/NetworkELB"
  metric_name         = "PortAllocationErrorCount"
  dimensions          = local.public_ingress_nlb_lb_dimensions
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

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_processed_bytes_high" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-processed-bytes-high"
  alarm_description   = "Baseline alarm: public ingress NLB processed more than ${var.traffic_thresholds.processed_bytes_per_5m} bytes in a 5 minute period."
  namespace           = "AWS/NetworkELB"
  metric_name         = "ProcessedBytes"
  dimensions          = local.public_ingress_nlb_lb_dimensions
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.traffic_thresholds.processed_bytes_per_5m
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_new_flows_high" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-new-flows-high"
  alarm_description   = "Baseline alarm: public ingress NLB saw more than ${var.traffic_thresholds.new_flows_per_5m} new flows in a 5 minute period."
  namespace           = "AWS/NetworkELB"
  metric_name         = "NewFlowCount"
  dimensions          = local.public_ingress_nlb_lb_dimensions
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.traffic_thresholds.new_flows_per_5m
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_active_flows_high" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-active-flows-high"
  alarm_description   = "Baseline alarm: public ingress NLB active flows exceeded ${var.traffic_thresholds.active_flows}."
  namespace           = "AWS/NetworkELB"
  metric_name         = "ActiveFlowCount"
  dimensions          = local.public_ingress_nlb_lb_dimensions
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.traffic_thresholds.active_flows
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_client_resets_high" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-client-resets-high"
  alarm_description   = "Baseline alarm: public ingress NLB client TCP resets exceeded ${var.traffic_thresholds.client_resets_per_5m} in a 5 minute period."
  namespace           = "AWS/NetworkELB"
  metric_name         = "TCP_Client_Reset_Count"
  dimensions          = local.public_ingress_nlb_lb_dimensions
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.traffic_thresholds.client_resets_per_5m
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_target_resets_high" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-target-resets-high"
  alarm_description   = "Baseline alarm: public ingress NLB target TCP resets exceeded ${var.traffic_thresholds.target_resets_per_5m} in a 5 minute period."
  namespace           = "AWS/NetworkELB"
  metric_name         = "TCP_Target_Reset_Count"
  dimensions          = local.public_ingress_nlb_lb_dimensions
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.traffic_thresholds.target_resets_per_5m
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "k3s_public_ingress_nlb_elb_resets" {
  alarm_name          = "${var.project_name}-k3s-public-ingress-nlb-elb-resets"
  alarm_description   = "Public ingress NLB generated TCP resets."
  namespace           = "AWS/NetworkELB"
  metric_name         = "TCP_ELB_Reset_Count"
  dimensions          = local.public_ingress_nlb_lb_dimensions
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.traffic_thresholds.elb_resets_per_5m
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}
