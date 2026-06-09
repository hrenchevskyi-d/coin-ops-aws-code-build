resource "aws_sns_topic" "observability_alerts" {
  name = "${var.project_name}-observability-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "observability_alert_email" {
  topic_arn = aws_sns_topic.observability_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
