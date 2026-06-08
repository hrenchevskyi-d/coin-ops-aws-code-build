# k3s_cloudwatch_logs

Deploys `aws-for-fluent-bit` as a DaemonSet in k3s and ships
`/var/log/containers/*.log` to CloudWatch Logs.

The role is AWS-only by default and writes to
`/<project_name>/k3s/containers`. Terraform creates the log group with a
14-day retention period; Fluent Bit can also create it if it is missing.
