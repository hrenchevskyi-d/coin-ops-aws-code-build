locals {
  effective_health_check_port = var.health_check_port > 0 ? var.health_check_port : var.port
  target_security_group_rule_enabled = (
    var.enable_target_security_group_rule
    && length(var.allowed_target_cidrs) > 0
  )
}

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = tostring(local.effective_health_check_port)
  }

  preserve_client_ip = false

  tags = var.tags
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = var.target_instance_ids

  target_group_arn = aws_lb_target_group.this.arn
  target_id        = each.value
  port             = var.port
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_security_group_rule" "target_from_nlb" {
  count = local.target_security_group_rule_enabled ? 1 : 0

  type              = "ingress"
  security_group_id = var.target_security_group_id
  protocol          = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_blocks       = var.allowed_target_cidrs
  description       = "Allow ${var.name} NLB traffic to k3s targets"
}
