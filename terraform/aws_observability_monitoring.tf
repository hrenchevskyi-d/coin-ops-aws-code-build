locals {
  aws_observability_enabled = try(local.observability.enabled, true)
  aws_observability_tags = {
    Project = local.project_name
    Cloud   = "aws"
  }

  aws_observability_alerts_cfg = merge({
    email = ""
  }, try(local.observability.alerts, {}))

  aws_observability_logs_cfg = merge({
    container_log_group_name      = "/${local.project_name}/k3s/containers"
    retention_in_days             = 7
    container_log_silence_minutes = 15
    metric_filters                = {}
  }, try(local.observability.logs, {}))

  aws_observability_cloudwatch_agent_cfg = merge({
    parameter_name              = "/${local.project_name}/cloudwatch-agent/linux"
    metrics_collection_interval = 60
    run_as_user                 = "cwagent"
    host_metric_groups          = {}
  }, try(local.observability.cloudwatch_agent, {}))

  aws_observability_alarms_cfg = merge({
    ec2            = {}
    eks            = {}
    nat_gateway    = {}
    nlb            = {}
    traefik        = {}
    container_logs = {}
  }, try(local.observability.alarms, {}))

  aws_observability_dashboard_cfg = merge({
    enabled = true
  }, try(local.observability.dashboard, {}))

  aws_observability_log_metric_filters = {
    for key, filter in local.aws_observability_logs_cfg.metric_filters : key => merge(filter, {
      name = try(filter.name, "${local.project_name}-${filter.name_suffix}")
    })
  }

  aws_cloudwatch_agent_metrics_collected = {
    for group_name, group_cfg in local.aws_observability_cloudwatch_agent_cfg.host_metric_groups : group_name => merge(
      {
        measurement                 = try(group_cfg.measurement, [])
        metrics_collection_interval = local.aws_observability_cloudwatch_agent_cfg.metrics_collection_interval
      },
      try(group_cfg.resources, null) == null ? {} : {
        resources = group_cfg.resources
      },
      try(group_cfg.drop_device, null) == null ? {} : {
        drop_device = group_cfg.drop_device
      }
    )
    if try(group_cfg.enabled, true)
  }

  aws_cloudwatch_agent_config = {
    agent = {
      metrics_collection_interval = local.aws_observability_cloudwatch_agent_cfg.metrics_collection_interval
      run_as_user                 = local.aws_observability_cloudwatch_agent_cfg.run_as_user
    }
    metrics = {
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      aggregation_dimensions = [
        ["InstanceId"]
      ]
      metrics_collected = local.aws_cloudwatch_agent_metrics_collected
    }
  }

  aws_observability_instance_ids = local.aws_compute_enabled ? {
    for name in keys(local.aws_instances_cfg) : name => module.aws_instances[0].instance_ids[name]
  } : {}

  aws_observability_eks_cluster = {
    enabled            = local.aws_eks_enabled
    cluster_name       = local.aws_eks_enabled ? try(module.aws_eks[0].cluster_name, "") : ""
    node_group_name    = local.aws_eks_enabled ? try(module.aws_eks[0].node_group_name, "") : ""
    desired_nodes      = local.aws_eks_enabled ? try(local.aws_eks_cfg.node_group.desired_size, 0) : 0
    autoscaling_groups = local.aws_eks_enabled ? try(module.aws_eks[0].node_group_autoscaling_group_names, []) : []
  }

  aws_observability_nat_gateway = {
    enabled        = local.aws_enabled && try(module.aws_network[0].managed_nat_gateway_id, "") != ""
    nat_gateway_id = local.aws_enabled ? try(module.aws_network[0].managed_nat_gateway_id, "") : ""
  }

  aws_k3s_public_ingress_target_count = length(local.aws_k3s_server_names)
  aws_observability_public_ingress_nlb = {
    enabled                  = local.aws_k3s_public_ingress_lb_enabled
    load_balancer_arn_suffix = try(module.aws_k3s_public_ingress_lb[0].arn_suffix, "")
    target_group_arn_suffix  = try(module.aws_k3s_public_ingress_lb[0].target_group_arn_suffix, "")
    target_count             = local.aws_k3s_public_ingress_target_count
  }

  aws_observability_log_metric_alarms = merge(
    try(local.aws_observability_alarms_cfg.traefik, {}),
    {
      for key, alarm in try(local.aws_observability_alarms_cfg.container_logs, {}) : key => merge(alarm, {
        description        = replace(try(alarm.description, ""), "{silence_minutes}", tostring(local.aws_observability_logs_cfg.container_log_silence_minutes))
        evaluation_periods = try(alarm.evaluation_periods, ceil(local.aws_observability_logs_cfg.container_log_silence_minutes * 60 / try(alarm.period, 300)))
      })
    }
  )
}

module "aws_observability_monitoring" {
  count = local.aws_enabled && local.aws_observability_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_monitoring"

  project_name               = local.project_name
  aws_region                 = local.aws_region
  tags                       = local.aws_observability_tags
  alert_email                = local.aws_observability_alerts_cfg.email
  cloudwatch_agent_parameter = local.aws_observability_cloudwatch_agent_cfg.parameter_name
  cloudwatch_agent_config    = local.aws_cloudwatch_agent_config
  instance_ids               = local.aws_observability_instance_ids
  ec2_alarms                 = local.aws_observability_alarms_cfg.ec2
  eks_cluster                = local.aws_observability_eks_cluster
  eks_alarms                 = local.aws_observability_alarms_cfg.eks
  nat_gateway                = local.aws_observability_nat_gateway
  nat_gateway_alarms         = local.aws_observability_alarms_cfg.nat_gateway
  public_ingress_nlb         = local.aws_observability_public_ingress_nlb
  nlb_alarms                 = local.aws_observability_alarms_cfg.nlb
  log_metric_definitions     = try(module.aws_observability_logs[0].metric_definitions, {})
  log_metric_alarms          = local.aws_observability_log_metric_alarms
  dashboard_enabled          = local.aws_observability_dashboard_cfg.enabled
}
