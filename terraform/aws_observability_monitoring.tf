locals {
  aws_observability_tags = {
    Project = local.project_name
    Cloud   = "aws"
  }

  aws_observability_alert_email       = "grenchevskiyd@gmail.com"
  aws_cloudwatch_agent_parameter_name = "/${local.project_name}/cloudwatch-agent/linux"

  aws_observability_container_log_silence_minutes = 15
  aws_observability_nlb_traffic_thresholds = {
    processed_bytes_per_5m = 10485760
    new_flows_per_5m       = 300
    active_flows           = 50
    client_resets_per_5m   = 500
    target_resets_per_5m   = 300
    elb_resets_per_5m      = 20
  }

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
  aws_observability_public_ingress_nlb = {
    enabled                  = local.aws_k3s_public_ingress_lb_enabled
    load_balancer_arn_suffix = try(module.aws_k3s_public_ingress_lb[0].arn_suffix, "")
    target_group_arn_suffix  = try(module.aws_k3s_public_ingress_lb[0].target_group_arn_suffix, "")
    target_count             = local.aws_k3s_public_ingress_target_count
  }
}

module "aws_observability_alerting" {
  count = local.aws_compute_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_alerting"

  project_name = local.project_name
  tags         = local.aws_observability_tags
  alert_email  = local.aws_observability_alert_email
}

module "aws_observability_agent_config" {
  count = local.aws_compute_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_agent_config"

  parameter_name = local.aws_cloudwatch_agent_parameter_name
  config         = local.aws_cloudwatch_agent_config
  tags           = local.aws_observability_tags
}

module "aws_observability_log_metrics" {
  count = local.aws_compute_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_log_metrics"

  project_name                  = local.project_name
  container_log_group_name      = module.aws_observability_logs[0].log_group_name
  alert_topic_arn               = module.aws_observability_alerting[0].topic_arn
  container_log_silence_minutes = local.aws_observability_container_log_silence_minutes
  tags                          = local.aws_observability_tags
}

module "aws_observability_ec2_alarms" {
  count = local.aws_compute_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_ec2_alarms"

  project_name    = local.project_name
  instance_ids    = local.aws_observability_instance_ids
  alert_topic_arn = module.aws_observability_alerting[0].topic_arn
  tags            = local.aws_observability_tags
}

module "aws_observability_nlb_alarms" {
  count = local.aws_compute_enabled && local.aws_observability_public_ingress_nlb.enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_nlb_alarms"

  project_name = local.project_name
  public_ingress_nlb = {
    load_balancer_arn_suffix = local.aws_observability_public_ingress_nlb.load_balancer_arn_suffix
    target_group_arn_suffix  = local.aws_observability_public_ingress_nlb.target_group_arn_suffix
    target_count             = local.aws_observability_public_ingress_nlb.target_count
  }
  alert_topic_arn    = module.aws_observability_alerting[0].topic_arn
  traffic_thresholds = local.aws_observability_nlb_traffic_thresholds
  tags               = local.aws_observability_tags
}

module "aws_observability_dashboard" {
  count = local.aws_compute_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_dashboard"

  project_name       = local.project_name
  aws_region         = local.aws_region
  instance_ids       = local.aws_observability_instance_ids
  public_ingress_nlb = local.aws_observability_public_ingress_nlb
}
