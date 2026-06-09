resource "aws_ssm_parameter" "cloudwatch_agent_linux" {
  name      = var.parameter_name
  type      = "String"
  value     = jsonencode(var.config)
  overwrite = true
  tags      = var.tags
}
