# AWS CodeBuild k3s Runtime Runbook

This runbook manages the AWS managed CI path for the k3s-only infrastructure
flow. VM Compose is intentionally out of scope.

## Ownership Boundary

Local bootstrap creates the CI control plane:

```text
ci/aws/bootstrap-local.sh
  -> Terraform backend bootstrap via terraform/bootstrap-aws.sh
  -> S3 artifact bucket
  -> SSM SecureString seed parameters
  -> IAM roles and inline policies
  -> CloudWatch log groups
  -> CodeBuild plan/apply projects
  -> CodePipeline Source -> Plan -> ApproveApply -> Apply
```

CodeBuild runs the workload Terraform plan:

```text
ci/aws/buildspec.k3s-terraform-plan.yml
  -> source ci/aws/codebuild-worker-env.sh
  -> render terraform/backend.active.tf
  -> terraform init
  -> terraform plan
  -> upload terraform/plan.out and terraform/plan.txt
```

After manual approval, a separate CodeBuild project runs Terraform apply:

```text
ci/aws/buildspec.k3s-terraform-apply.yml
  -> source ci/aws/codebuild-worker-env.sh
  -> render terraform/backend.active.tf
  -> terraform init
  -> copy approved terraform/plan.out from the Plan artifact
  -> terraform apply plan.out
```

Terraform formatting and validation are intentionally handled earlier by GitHub
Actions. The AWS worker should not repeat `terraform fmt -check` or
`terraform validate`; it should spend AWS runtime only on the real backend plan
and approved apply path. The worker also uses `terraform init -reconfigure`
instead of `terraform init -upgrade`, so provider upgrades remain an explicit
repository change.

The main `terraform/` root does not create CodeBuild or CodePipeline. It is the
workload infrastructure that the pipeline plans and later should apply.

## Required Local Context

Run local bootstrap from an operator/admin AWS identity. Do not source
`local/generated-env.sh` before creating or updating CI resources.

Verify account and region:

```bash
aws sts get-caller-identity
aws configure get region
echo "$AWS_REGION"
echo "$AWS_DEFAULT_REGION"
```

For this environment, use:

```bash
export AWS_REGION=eu-central-1
export AWS_DEFAULT_REGION=eu-central-1
aws configure set region eu-central-1
```

## GitHub Source

Current test source:

```bash
export COINOPS_CI_GITHUB_REPO=hrenchevskyi-d/coin-ops-aws-code-build
export COINOPS_CI_BRANCH=hrenchevskyi-codebuild
```

The pipeline uses AWS CodeConnections/CodeStar Connections for GitHub access.
If no connection exists yet:

```bash
COINOPS_CI_CREATE_CONNECTION=true \
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
ci/aws/bootstrap-local.sh
```

Then authorize the pending GitHub connection in AWS Console:

```text
AWS Console -> Developer Tools -> Settings -> Connections
```

After authorization, rerun bootstrap with the connection ARN:

```bash
export COINOPS_CI_GITHUB_CONNECTION_ARN='arn:aws:codestar-connections:REGION:ACCOUNT:connection/ID'
```

## Seed Secrets

Fresh AWS accounts need Terraform to seed AWS Secrets Manager, so CI uses:

```bash
TF_VAR_seed_secret_manager=true
```

The local bootstrap writes required seed values to SSM Parameter Store as
`SecureString`, then wires those parameters into CodeBuild as secure env vars.

Required local env before bootstrap:

```bash
export TF_VAR_db_password='REPLACE_ME'
export TF_VAR_rabbitmq_password='REPLACE_ME'
export TF_VAR_ghcr_token='REPLACE_ME'
export TF_VAR_cloudflare_api_token='REPLACE_ME'
```

Optional seed values:

```bash
export TF_VAR_tailscale_auth_key='REPLACE_ME'
export TF_VAR_github_oauth_client_id='REPLACE_ME'
export TF_VAR_github_oauth_client_secret='REPLACE_ME'
```

Do not commit these values. Re-run bootstrap after changing any seed value.

## Bootstrap Or Update CI

Use this command to create or update the CI control plane:

```bash
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
COINOPS_CI_GITHUB_CONNECTION_ARN="$COINOPS_CI_GITHUB_CONNECTION_ARN" \
ci/aws/bootstrap-local.sh
```

Use this when Terraform backend bootstrap already exists and only CI resources
need updates:

```bash
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
COINOPS_CI_GITHUB_CONNECTION_ARN="$COINOPS_CI_GITHUB_CONNECTION_ARN" \
ci/aws/bootstrap-local.sh --skip-terraform-bootstrap
```

Expected output includes:

```text
Pipeline:              coin-ops-k3s-plan
Plan CodeBuild project:coin-ops-k3s-plan
Apply CodeBuild project:coin-ops-k3s-plan-apply
Artifact bucket:       coin-ops-codepipeline-artifacts-ACCOUNT-eu-central-1
Terraform state bucket:coinops-terraform-state-ACCOUNT-eu-central-1
```

## Run Plan And Apply

Start the pipeline:

```bash
aws codepipeline start-pipeline-execution \
  --region eu-central-1 \
  --name coin-ops-k3s-plan
```

Check pipeline state:

```bash
aws codepipeline get-pipeline-state \
  --region eu-central-1 \
  --name coin-ops-k3s-plan
```

Check latest CodeBuild build:

```bash
aws codebuild list-builds-for-project \
  --region eu-central-1 \
  --project-name coin-ops-k3s-plan \
  --sort-order DESCENDING \
  --max-items 1
```

After the Plan stage succeeds, CodePipeline stops at:

```text
ApproveApply -> ApproveTerraformApply
```

Before approving, inspect `terraform/plan.txt` from the Plan artifact or the
Plan CodeBuild logs. Approving this stage allows the separate apply worker to run
`terraform apply` against the exact binary plan artifact from the Plan stage.
Reject the approval if the plan is not expected.

## Read Logs

Get the latest build id:

```bash
BUILD_ID="$(
  aws codebuild list-builds-for-project \
    --region eu-central-1 \
    --project-name coin-ops-k3s-plan \
    --sort-order DESCENDING \
    --max-items 1 \
    --query 'ids[0]' \
    --output text
)"
echo "$BUILD_ID"
```

Read CloudWatch logs:

```bash
BUILD_UUID="${BUILD_ID#coin-ops-k3s-plan:}"

aws logs get-log-events \
  --region eu-central-1 \
  --log-group-name /aws/codebuild/coin-ops-k3s-plan \
  --log-stream-name "terraform-plan/${BUILD_UUID}" \
  --query 'events[].message' \
  --output text
```

The plan also appears in logs because the buildspec runs Terraform through
`tee terraform/plan.txt`.

Read apply logs by switching the project and log group:

```bash
APPLY_BUILD_ID="$(
  aws codebuild list-builds-for-project \
    --region eu-central-1 \
    --project-name coin-ops-k3s-plan-apply \
    --sort-order DESCENDING \
    --max-items 1 \
    --query 'ids[0]' \
    --output text
)"
APPLY_BUILD_UUID="${APPLY_BUILD_ID#coin-ops-k3s-plan-apply:}"

aws logs get-log-events \
  --region eu-central-1 \
  --log-group-name /aws/codebuild/coin-ops-k3s-plan-apply \
  --log-stream-name "terraform-apply/${APPLY_BUILD_UUID}" \
  --query 'events[].message' \
  --output text
```

## Read Plan Artifacts

The pipeline stores artifacts in:

```text
s3://coin-ops-codepipeline-artifacts-ACCOUNT-eu-central-1/
```

List artifacts:

```bash
aws s3 ls \
  s3://coin-ops-codepipeline-artifacts-231648037082-eu-central-1/ \
  --region eu-central-1 \
  --recursive
```

Download and inspect the plan artifact:

```bash
aws s3 cp \
  s3://coin-ops-codepipeline-artifacts-231648037082-eu-central-1/PATH/TO/ARTIFACT \
  /tmp/coinops-plan-artifact.zip \
  --region eu-central-1

rm -rf /tmp/coinops-plan-artifact
unzip /tmp/coinops-plan-artifact.zip -d /tmp/coinops-plan-artifact
less /tmp/coinops-plan-artifact/terraform/plan.txt
```

`terraform/plan.out` is the binary plan. `terraform/plan.txt` is for review.

## Common Failures

Pipeline not found:

```text
PipelineNotFoundException
```

Check region. The pipeline is in `eu-central-1`:

```bash
aws codepipeline list-pipelines --region eu-central-1
```

GitHub source fails:

```text
Connection is pending
```

Authorize the connection in AWS Console, then rerun the pipeline.

Install phase fails on Terraform:

```text
Missing required tool: terraform
```

The worker should install Terraform via `codebuild-worker-env.sh`. Confirm the
pipeline is using the latest pushed branch and buildspec.

Terraform init fails on backend:

```text
use_lockfile is not expected here
```

The worker is using an old Terraform version. Current default is `1.15.2`.

Terraform plan fails reading AWS Secrets Manager:

```text
couldn't find resource coinops-db-secrets|AWSCURRENT
```

Re-run bootstrap with required `TF_VAR_*` seed values. CodeBuild must receive
`TF_VAR_seed_secret_manager=true`.

Terraform plan fails on Azure CLI:

```text
exec: "az": executable file not found
```

The worker exports dummy `ARM_*` values and `ARM_USE_CLI=false` for the disabled
Azure provider. Confirm the latest `codebuild-worker-env.sh` is in the source
branch.

## Update Procedure

After changing any file under `ci/aws/`:

```bash
git add ci/aws
git commit -m 'ci: describe change'
git push origin hrenchevskyi-codebuild
git push personal hrenchevskyi-codebuild
```

If `bootstrap-local.sh` changed, rerun bootstrap so AWS resources are updated.

If only a buildspec or `codebuild-worker-env.sh` changed, pushing the branch is
enough for the next pipeline execution.

## Current Limitations

- It does not run Ansible or k3s playbooks.
- Optional seed parameters are written when present, but only required seed
  values are currently wired into CodeBuild.
- The apply worker is separated from the plan worker, but its IAM role is still
  intentionally broad (`PowerUserAccess` plus `IAMFullAccess`) because the
  Terraform root can create networking, compute, load balancing, database,
  secrets, IAM, S3, and CloudWatch resources. Tighten this after the final AWS
  resource set is stable.
- Apply consumes the approved `plan.out`; it does not create a new unapproved
  plan.
