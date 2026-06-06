# aws_ssm_agent

Installs the AWS Systems Manager Agent on Debian EC2 hosts from the regional
AWS public S3 package URL, then enables and starts `amazon-ssm-agent`.

The role is included by `common` for AWS hosts only. It expects `aws_region`
from `runtime_config`.
