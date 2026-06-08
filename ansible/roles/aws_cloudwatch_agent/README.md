# aws_cloudwatch_agent

Installs AWS CloudWatch Agent on Debian EC2 hosts and applies the agent
configuration from an SSM Parameter Store document.

The role is included by `common` for AWS hosts only. It expects `aws_region`
and `infra_general` from `runtime_config`, and the EC2 instance profile must
allow reading the configured SSM parameter and publishing CloudWatch metrics.
