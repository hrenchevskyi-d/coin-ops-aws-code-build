resource "aws_cloudwatch_metric_alarm" "ec2_cpu_utilization" {
  for_each = var.instance_ids

  alarm_name          = "${var.project_name}-${each.key}-ec2-cpu-utilization"
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
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  for_each = var.instance_ids

  alarm_name          = "${var.project_name}-${each.key}-ec2-status-check-failed"
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
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_memory_used_percent" {
  for_each = var.instance_ids

  alarm_name          = "${var.project_name}-${each.key}-ec2-memory-used-percent"
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
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_disk_used_percent" {
  for_each = var.instance_ids

  alarm_name          = "${var.project_name}-${each.key}-ec2-disk-used-percent"
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
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]
  tags                = var.tags
}
