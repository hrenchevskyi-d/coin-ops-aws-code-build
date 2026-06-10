moved {
  from = module.aws_observability_alerting[0].aws_sns_topic.observability_alerts
  to   = module.aws_observability_monitoring[0].aws_sns_topic.observability_alerts
}

moved {
  from = module.aws_observability_alerting[0].aws_sns_topic_subscription.observability_alert_email
  to   = module.aws_observability_monitoring[0].aws_sns_topic_subscription.observability_alert_email[0]
}

moved {
  from = module.aws_observability_agent_config[0].aws_ssm_parameter.cloudwatch_agent_linux
  to   = module.aws_observability_monitoring[0].aws_ssm_parameter.cloudwatch_agent_linux
}

moved {
  from = module.aws_observability_log_metrics[0].aws_cloudwatch_log_metric_filter.container_log_events
  to   = module.aws_observability_logs[0].aws_cloudwatch_log_metric_filter.log_metric_filters["container_log_events"]
}

moved {
  from = module.aws_observability_log_metrics[0].aws_cloudwatch_log_metric_filter.traefik_request_count
  to   = module.aws_observability_logs[0].aws_cloudwatch_log_metric_filter.log_metric_filters["traefik_request_count"]
}

moved {
  from = module.aws_observability_log_metrics[0].aws_cloudwatch_log_metric_filter.traefik_downstream_5xx_count
  to   = module.aws_observability_logs[0].aws_cloudwatch_log_metric_filter.log_metric_filters["traefik_downstream_5xx_count"]
}

moved {
  from = module.aws_observability_log_metrics[0].aws_cloudwatch_log_metric_filter.traefik_origin_5xx_count
  to   = module.aws_observability_logs[0].aws_cloudwatch_log_metric_filter.log_metric_filters["traefik_origin_5xx_count"]
}

moved {
  from = module.aws_observability_log_metrics[0].aws_cloudwatch_metric_alarm.traefik_downstream_5xx
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.log_metric["downstream_5xx"]
}

moved {
  from = module.aws_observability_log_metrics[0].aws_cloudwatch_metric_alarm.traefik_origin_5xx
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.log_metric["origin_5xx"]
}

moved {
  from = module.aws_observability_log_metrics[0].aws_cloudwatch_metric_alarm.container_logs_silent
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.log_metric["silent"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_unhealthy_targets
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["unhealthy_targets"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_healthy_target_count
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["healthy_target_count"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_rejected_flows
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["rejected_flows"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_port_allocation_errors
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["port_allocation_errors"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_processed_bytes_high
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["processed_bytes_high"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_new_flows_high
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["new_flows_high"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_active_flows_high
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["active_flows_high"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_client_resets_high
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["client_resets_high"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_target_resets_high
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["target_resets_high"]
}

moved {
  from = module.aws_observability_nlb_alarms[0].aws_cloudwatch_metric_alarm.k3s_public_ingress_nlb_elb_resets
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.nlb["elb_resets"]
}

moved {
  from = module.aws_observability_dashboard[0].aws_cloudwatch_dashboard.observability
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_dashboard.observability[0]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_cpu_utilization["jump-host"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["cpu_utilization:jump-host"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_cpu_utilization["k3s-server-1"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["cpu_utilization:k3s-server-1"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_cpu_utilization["k3s-server-2"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["cpu_utilization:k3s-server-2"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_cpu_utilization["k3s-server-3"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["cpu_utilization:k3s-server-3"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_status_check_failed["jump-host"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["status_check_failed:jump-host"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_status_check_failed["k3s-server-1"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["status_check_failed:k3s-server-1"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_status_check_failed["k3s-server-2"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["status_check_failed:k3s-server-2"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_status_check_failed["k3s-server-3"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["status_check_failed:k3s-server-3"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_memory_used_percent["jump-host"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["memory_used_percent:jump-host"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_memory_used_percent["k3s-server-1"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["memory_used_percent:k3s-server-1"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_memory_used_percent["k3s-server-2"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["memory_used_percent:k3s-server-2"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_memory_used_percent["k3s-server-3"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["memory_used_percent:k3s-server-3"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_disk_used_percent["jump-host"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["disk_used_percent:jump-host"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_disk_used_percent["k3s-server-1"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["disk_used_percent:k3s-server-1"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_disk_used_percent["k3s-server-2"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["disk_used_percent:k3s-server-2"]
}

moved {
  from = module.aws_observability_ec2_alarms[0].aws_cloudwatch_metric_alarm.ec2_disk_used_percent["k3s-server-3"]
  to   = module.aws_observability_monitoring[0].aws_cloudwatch_metric_alarm.ec2["disk_used_percent:k3s-server-3"]
}
