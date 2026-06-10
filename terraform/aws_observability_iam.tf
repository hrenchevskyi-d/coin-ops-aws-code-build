locals {
  aws_ec2_observability_policy_arns = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
}

module "aws_observability_iam" {
  count = local.aws_compute_enabled && local.aws_observability_enabled ? 1 : 0

  source = "./modules/cloud/aws/observability_iam"

  project_name = local.project_name
  policy_arns  = local.aws_ec2_observability_policy_arns
  tags         = local.aws_observability_tags
}
