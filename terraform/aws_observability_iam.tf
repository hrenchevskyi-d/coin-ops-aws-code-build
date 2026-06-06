locals {
  aws_ec2_observability_policy_arns = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
}

resource "aws_iam_role" "ec2_observability" {
  count = local.aws_compute_enabled ? 1 : 0

  name = "${local.project_name}-ec2-observability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = local.project_name
    Cloud   = "aws"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_observability" {
  for_each = local.aws_compute_enabled ? local.aws_ec2_observability_policy_arns : toset([])

  role       = aws_iam_role.ec2_observability[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2_observability" {
  count = local.aws_compute_enabled ? 1 : 0

  name = "${local.project_name}-ec2-observability"
  role = aws_iam_role.ec2_observability[0].name

  tags = {
    Project = local.project_name
    Cloud   = "aws"
  }
}
