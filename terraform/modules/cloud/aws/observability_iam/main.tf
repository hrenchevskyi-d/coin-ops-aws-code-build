resource "aws_iam_role" "ec2_observability" {
  name = "${var.project_name}-ec2-observability"

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2_observability" {
  for_each = var.policy_arns

  role       = aws_iam_role.ec2_observability.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2_observability" {
  name = "${var.project_name}-ec2-observability"
  role = aws_iam_role.ec2_observability.name

  tags = var.tags
}
