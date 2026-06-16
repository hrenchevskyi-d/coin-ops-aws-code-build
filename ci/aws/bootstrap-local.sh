#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  COINOPS_CI_GITHUB_REPO=owner/repo \
  COINOPS_CI_GITHUB_CONNECTION_ARN=arn:aws:codestar-connections:... \
    ci/aws/bootstrap-local.sh

Options:
  --skip-terraform-bootstrap  Do not run terraform/bootstrap-aws.sh first.

Required environment:
  COINOPS_CI_GITHUB_REPO
      GitHub repository id for CodePipeline source, for example owner/repo.

  COINOPS_CI_GITHUB_CONNECTION_ARN
      Existing, authorized CodeStar Connections ARN for GitHub.

Alternative connection bootstrap:
  COINOPS_CI_CREATE_CONNECTION=true
      Create or reuse a pending GitHub CodeStar connection, then print the
      connection ARN. You must authorize it in AWS before the pipeline can run.

Optional environment:
  COINOPS_CI_BRANCH                  Default: current git branch
  COINOPS_CI_PIPELINE_NAME           Default: <project>-k3s-deploy
  COINOPS_CI_ARTIFACT_BUCKET         Default: <project>-codepipeline-artifacts-<account>-<region>
  COINOPS_CI_PLAN_CODEBUILD_PROJECT_NAME
                                      Default: <pipeline-name>
  COINOPS_CI_APPLY_CODEBUILD_PROJECT_NAME
                                      Default: <pipeline-name>-apply
  COINOPS_CI_SMOKE_CODEBUILD_PROJECT_NAME
                                      Default: <pipeline-name>-smoke
  COINOPS_CI_APPROVAL_TOPIC_NAME      Default: <pipeline-name>-approvals
  COINOPS_CI_APPROVAL_NOTIFICATION_EMAIL
                                      Optional email subscription for manual approval notifications.
  COINOPS_CI_CODEBUILD_IMAGE         Default: aws/codebuild/standard:7.0
  COINOPS_CI_CODEBUILD_COMPUTE_TYPE  Default: BUILD_GENERAL1_SMALL
  COINOPS_CI_DETECT_CHANGES          Default: false
  COINOPS_SSH_PUBLIC_KEY             Optional public key passed into CodeBuild for Terraform plans.

Required seed values for fresh AWS accounts:
  TF_VAR_db_password
  TF_VAR_rabbitmq_password
  TF_VAR_ghcr_token
  TF_VAR_cloudflare_api_token

Optional seed values:
  TF_VAR_tailscale_auth_key
  TF_VAR_github_oauth_client_id
  TF_VAR_github_oauth_client_secret
EOF
}

SKIP_TERRAFORM_BOOTSTRAP=false
for arg in "$@"; do
  case "${arg}" in
    --skip-terraform-bootstrap)
      SKIP_TERRAFORM_BOOTSTRAP=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

aws_text() {
  aws "$@" --output text
}

read_config() {
  python3 - "${REPO_ROOT}" "${AWS_REGION:-${TF_VAR_aws_region:-}}" <<'PY'
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
env_region = sys.argv[2]
config_dir = repo_root / "terraform" / "config"

with (config_dir / "clouds.json").open(encoding="utf-8") as handle:
    clouds = json.load(handle)["clouds"]
with (config_dir / "general.json").open(encoding="utf-8") as handle:
    general = json.load(handle)["general"]
with (config_dir / "secrets.json").open(encoding="utf-8") as handle:
    secrets = json.load(handle)["secrets"]
with (config_dir / "cloud_mappings.json").open(encoding="utf-8") as handle:
    mappings = json.load(handle)

region_profile = general.get("region_profile", "europe-central")
region = env_region or mappings["regions"]["aws"][region_profile]["region"]
backend = clouds.get("backends", {}).get("aws", {})
secret_names = secrets.get("names", {})

values = [
    general.get("project_name", "coin-ops"),
    region,
    backend.get("bucket_prefix", "coinops-terraform-state"),
    backend.get("key", "infra/state/terraform.tfstate"),
    secret_names.get("db", "coinops-db-secrets"),
    secret_names.get("app", "coinops-app-secrets"),
]
print("\t".join(values))
PY
}

ensure_artifact_bucket() {
  if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" >/dev/null 2>&1; then
    echo "Artifact bucket exists: ${ARTIFACT_BUCKET}"
  else
    echo "Creating artifact bucket: ${ARTIFACT_BUCKET}"
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "${ARTIFACT_BUCKET}" >/dev/null
    else
      aws s3api create-bucket \
        --bucket "${ARTIFACT_BUCKET}" \
        --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
    fi
  fi

  aws s3api put-public-access-block \
    --bucket "${ARTIFACT_BUCKET}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

  aws s3api put-bucket-encryption \
    --bucket "${ARTIFACT_BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null

  aws s3api put-bucket-versioning \
    --bucket "${ARTIFACT_BUCKET}" \
    --versioning-configuration Status=Enabled >/dev/null
}

connection_arn_by_name() {
  local connection_name="$1"
  aws codestar-connections list-connections \
    --provider-type-filter GitHub \
    --query "Connections[?ConnectionName=='${connection_name}'].ConnectionArn | [0]" \
    --output text
}

ensure_connection_arn() {
  if [[ -n "${COINOPS_CI_GITHUB_CONNECTION_ARN:-}" ]]; then
    echo "${COINOPS_CI_GITHUB_CONNECTION_ARN}"
    return
  fi

  if [[ "${COINOPS_CI_CREATE_CONNECTION:-false}" != "true" ]]; then
    cat >&2 <<EOF
COINOPS_CI_GITHUB_CONNECTION_ARN is required.

Either provide an existing authorized CodeStar Connections ARN, or run with:
  COINOPS_CI_CREATE_CONNECTION=true

EOF
    exit 1
  fi

  local existing_arn
  existing_arn="$(connection_arn_by_name "${CONNECTION_NAME}")"
  if [[ -n "${existing_arn}" && "${existing_arn}" != "None" ]]; then
    echo "${existing_arn}"
    return
  fi

  aws codestar-connections create-connection \
    --provider-type GitHub \
    --connection-name "${CONNECTION_NAME}" \
    --query ConnectionArn \
    --output text
}

write_assume_role_policy() {
  local service="$1"
  local path="$2"

  python3 - "${service}" "${path}" <<'PY'
import json
import pathlib
import sys

service = sys.argv[1]
path = pathlib.Path(sys.argv[2])
policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"Service": service},
            "Action": "sts:AssumeRole",
        }
    ],
}
path.write_text(json.dumps(policy), encoding="utf-8")
PY
}

ensure_role() {
  local role_name="$1"
  local service="$2"
  local assume_policy_path="${WORK_DIR}/${role_name}-assume-role.json"

  write_assume_role_policy "${service}" "${assume_policy_path}"

  if aws iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    echo "Updating IAM role trust policy: ${role_name}"
    aws iam update-assume-role-policy \
      --role-name "${role_name}" \
      --policy-document "file://${assume_policy_path}" >/dev/null
  else
    echo "Creating IAM role: ${role_name}"
    aws iam create-role \
      --role-name "${role_name}" \
      --assume-role-policy-document "file://${assume_policy_path}" >/dev/null
  fi
}

write_codebuild_policy() {
  local path="$1"

  python3 - "${path}" "${AWS_REGION}" "${ACCOUNT_ID}" "${ARTIFACT_BUCKET}" "${STATE_BUCKET}" "${STATE_KEY}" "${DB_SECRET_NAME}" "${APP_SECRET_NAME}" "${CODEBUILD_LOG_GROUP}" "${SEED_PARAMETER_PREFIX}" <<'PY'
import json
import pathlib
import sys

(
    path,
    region,
    account_id,
    artifact_bucket,
    state_bucket,
    state_key,
    db_secret_name,
    app_secret_name,
    log_group,
    seed_parameter_prefix,
) = sys.argv[1:]

policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "WriteLogs",
            "Effect": "Allow",
            "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
            "Resource": f"arn:aws:logs:{region}:{account_id}:log-group:{log_group}:*",
        },
        {
            "Sid": "UsePipelineArtifacts",
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"],
            "Resource": f"arn:aws:s3:::{artifact_bucket}/*",
        },
        {
            "Sid": "ListPipelineArtifacts",
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": f"arn:aws:s3:::{artifact_bucket}",
        },
        {
            "Sid": "UseTerraformState",
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
            "Resource": [
                f"arn:aws:s3:::{state_bucket}/{state_key}",
                f"arn:aws:s3:::{state_bucket}/{state_key}.tflock",
            ],
        },
        {
            "Sid": "ListTerraformStateBucket",
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": f"arn:aws:s3:::{state_bucket}",
            "Condition": {
                "StringLike": {
                    "s3:prefix": [state_key, f"{state_key}.tflock"]
                }
            },
        },
        {
            "Sid": "ReadTerraformSecrets",
            "Effect": "Allow",
            "Action": ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"],
            "Resource": [
                f"arn:aws:secretsmanager:{region}:{account_id}:secret:{db_secret_name}*",
                f"arn:aws:secretsmanager:{region}:{account_id}:secret:{app_secret_name}*",
            ],
        },
        {
            "Sid": "ReadCiSeedParameters",
            "Effect": "Allow",
            "Action": ["ssm:GetParameter", "ssm:GetParameters"],
            "Resource": f"arn:aws:ssm:{region}:{account_id}:parameter{seed_parameter_prefix}/*",
        },
        {
            "Sid": "DecryptCiSeedParameters",
            "Effect": "Allow",
            "Action": ["kms:Decrypt"],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": f"ssm.{region}.amazonaws.com"
                }
            },
        },
    ],
}
pathlib.Path(path).write_text(json.dumps(policy), encoding="utf-8")
PY
}

put_seed_parameter() {
  local env_name="$1"
  local parameter_name="$2"
  local required="$3"
  local value="${!env_name:-}"

  if [[ -z "${value}" ]]; then
    if [[ "${required}" == "true" ]]; then
      if aws ssm get-parameter --name "${parameter_name}" --with-decryption >/dev/null 2>&1; then
        echo "Keeping existing CI seed parameter: ${parameter_name}"
        return 0
      fi

      echo "${env_name} is required for CI seed_secret_manager=true." >&2
      exit 1
    fi
    return 0
  fi

  echo "Writing CI seed parameter: ${parameter_name}"
  aws ssm put-parameter \
    --name "${parameter_name}" \
    --type SecureString \
    --value "${value}" \
    --overwrite >/dev/null
}

ensure_seed_parameters() {
  put_seed_parameter TF_VAR_db_password "${SEED_PARAMETER_PREFIX}/db_password" true
  put_seed_parameter TF_VAR_rabbitmq_password "${SEED_PARAMETER_PREFIX}/rabbitmq_password" true
  put_seed_parameter TF_VAR_ghcr_token "${SEED_PARAMETER_PREFIX}/ghcr_token" true
  put_seed_parameter TF_VAR_cloudflare_api_token "${SEED_PARAMETER_PREFIX}/cloudflare_api_token" true
  put_seed_parameter TF_VAR_tailscale_auth_key "${SEED_PARAMETER_PREFIX}/tailscale_auth_key" false
  put_seed_parameter TF_VAR_github_oauth_client_id "${SEED_PARAMETER_PREFIX}/github_oauth_client_id" false
  put_seed_parameter TF_VAR_github_oauth_client_secret "${SEED_PARAMETER_PREFIX}/github_oauth_client_secret" false
}

ensure_approval_topic() {
  APPROVAL_TOPIC_ARN="$(aws sns create-topic \
    --name "${APPROVAL_TOPIC_NAME}" \
    --query TopicArn \
    --output text)"

  if [[ -n "${APPROVAL_NOTIFICATION_EMAIL:-}" ]]; then
    local existing_subscription
    existing_subscription="$(aws sns list-subscriptions-by-topic \
      --topic-arn "${APPROVAL_TOPIC_ARN}" \
      --query "Subscriptions[?Endpoint=='${APPROVAL_NOTIFICATION_EMAIL}'].SubscriptionArn | [0]" \
      --output text)"

    if [[ -z "${existing_subscription}" || "${existing_subscription}" == "None" ]]; then
      echo "Creating pending SNS email subscription for approval notifications: ${APPROVAL_NOTIFICATION_EMAIL}"
      aws sns subscribe \
        --topic-arn "${APPROVAL_TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${APPROVAL_NOTIFICATION_EMAIL}" >/dev/null
    else
      echo "SNS email subscription already exists for approval notifications: ${APPROVAL_NOTIFICATION_EMAIL}"
    fi
  fi
}

write_codepipeline_policy() {
  local path="$1"

  python3 - "${path}" "${AWS_REGION}" "${ACCOUNT_ID}" "${ARTIFACT_BUCKET}" "${GITHUB_CONNECTION_ARN}" "${PLAN_CODEBUILD_PROJECT_NAME}" "${APPLY_CODEBUILD_PROJECT_NAME}" "${SMOKE_CODEBUILD_PROJECT_NAME}" "${APPROVAL_TOPIC_ARN}" <<'PY'
import json
import pathlib
import sys

(
    path,
    region,
    account_id,
    artifact_bucket,
    connection_arn,
    plan_project_name,
    apply_project_name,
    smoke_project_name,
    approval_topic_arn,
) = sys.argv[1:]
policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "UseCodeStarConnection",
            "Effect": "Allow",
            "Action": ["codestar-connections:UseConnection"],
            "Resource": connection_arn,
        },
        {
            "Sid": "UseArtifacts",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:GetBucketVersioning",
                "s3:PutObject",
            ],
            "Resource": [
                f"arn:aws:s3:::{artifact_bucket}",
                f"arn:aws:s3:::{artifact_bucket}/*",
            ],
        },
        {
            "Sid": "RunCodeBuild",
            "Effect": "Allow",
            "Action": ["codebuild:BatchGetBuilds", "codebuild:StartBuild"],
            "Resource": [
                f"arn:aws:codebuild:{region}:{account_id}:project/{plan_project_name}",
                f"arn:aws:codebuild:{region}:{account_id}:project/{apply_project_name}",
                f"arn:aws:codebuild:{region}:{account_id}:project/{smoke_project_name}",
            ],
        },
        {
            "Sid": "PublishApprovalNotification",
            "Effect": "Allow",
            "Action": "sns:Publish",
            "Resource": approval_topic_arn,
        },
    ],
}
pathlib.Path(path).write_text(json.dumps(policy), encoding="utf-8")
PY
}

ensure_iam() {
  ensure_role "${PLAN_CODEBUILD_ROLE_NAME}" codebuild.amazonaws.com
  ensure_role "${APPLY_CODEBUILD_ROLE_NAME}" codebuild.amazonaws.com
  ensure_role "${SMOKE_CODEBUILD_ROLE_NAME}" codebuild.amazonaws.com
  ensure_role "${CODEPIPELINE_ROLE_NAME}" codepipeline.amazonaws.com

  aws iam attach-role-policy \
    --role-name "${PLAN_CODEBUILD_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess >/dev/null

  aws iam attach-role-policy \
    --role-name "${SMOKE_CODEBUILD_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess >/dev/null

  aws iam attach-role-policy \
    --role-name "${APPLY_CODEBUILD_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/PowerUserAccess >/dev/null

  aws iam attach-role-policy \
    --role-name "${APPLY_CODEBUILD_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/IAMFullAccess >/dev/null

  local plan_codebuild_policy="${WORK_DIR}/plan-codebuild-policy.json"
  local apply_codebuild_policy="${WORK_DIR}/apply-codebuild-policy.json"
  local smoke_codebuild_policy="${WORK_DIR}/smoke-codebuild-policy.json"
  local codepipeline_policy="${WORK_DIR}/codepipeline-policy.json"
  CODEBUILD_LOG_GROUP="${PLAN_CODEBUILD_LOG_GROUP}" write_codebuild_policy "${plan_codebuild_policy}"
  CODEBUILD_LOG_GROUP="${APPLY_CODEBUILD_LOG_GROUP}" write_codebuild_policy "${apply_codebuild_policy}"
  CODEBUILD_LOG_GROUP="${SMOKE_CODEBUILD_LOG_GROUP}" write_codebuild_policy "${smoke_codebuild_policy}"
  write_codepipeline_policy "${codepipeline_policy}"

  aws iam put-role-policy \
    --role-name "${PLAN_CODEBUILD_ROLE_NAME}" \
    --policy-name "${PLAN_CODEBUILD_ROLE_NAME}" \
    --policy-document "file://${plan_codebuild_policy}" >/dev/null

  aws iam put-role-policy \
    --role-name "${APPLY_CODEBUILD_ROLE_NAME}" \
    --policy-name "${APPLY_CODEBUILD_ROLE_NAME}" \
    --policy-document "file://${apply_codebuild_policy}" >/dev/null

  aws iam put-role-policy \
    --role-name "${SMOKE_CODEBUILD_ROLE_NAME}" \
    --policy-name "${SMOKE_CODEBUILD_ROLE_NAME}" \
    --policy-document "file://${smoke_codebuild_policy}" >/dev/null

  aws iam put-role-policy \
    --role-name "${CODEPIPELINE_ROLE_NAME}" \
    --policy-name "${CODEPIPELINE_ROLE_NAME}" \
    --policy-document "file://${codepipeline_policy}" >/dev/null

  PLAN_CODEBUILD_ROLE_ARN="$(aws_text iam get-role --role-name "${PLAN_CODEBUILD_ROLE_NAME}" --query Role.Arn)"
  APPLY_CODEBUILD_ROLE_ARN="$(aws_text iam get-role --role-name "${APPLY_CODEBUILD_ROLE_NAME}" --query Role.Arn)"
  SMOKE_CODEBUILD_ROLE_ARN="$(aws_text iam get-role --role-name "${SMOKE_CODEBUILD_ROLE_NAME}" --query Role.Arn)"
  CODEPIPELINE_ROLE_ARN="$(aws_text iam get-role --role-name "${CODEPIPELINE_ROLE_NAME}" --query Role.Arn)"
}

ensure_log_group() {
  local log_group="$1"

  if ! aws logs describe-log-groups \
    --log-group-name-prefix "${log_group}" \
    --query "logGroups[?logGroupName=='${log_group}'].logGroupName | [0]" \
    --output text | grep -qx "${log_group}"; then
    echo "Creating CloudWatch log group: ${log_group}"
    aws logs create-log-group --log-group-name "${log_group}" >/dev/null
  fi

  aws logs put-retention-policy \
    --log-group-name "${log_group}" \
    --retention-in-days "${COINOPS_CI_LOG_RETENTION_DAYS:-7}" >/dev/null
}

write_codebuild_project_json() {
  local path="$1"
  local project_name="$2"
  local role_arn="$3"
  local buildspec="$4"
  local log_group="$5"
  local purpose="$6"

  python3 - "${path}" "${PROJECT_NAME}" "${project_name}" "${role_arn}" "${CODEBUILD_IMAGE}" "${CODEBUILD_COMPUTE_TYPE}" "${AWS_REGION}" "${STATE_BUCKET}" "${COINOPS_SSH_PUBLIC_KEY:-}" "${log_group}" "${SEED_PARAMETER_PREFIX}" "${buildspec}" "${purpose}" <<'PY'
import json
import pathlib
import sys

(
    path,
    project_tag,
    project_name,
    role_arn,
    image,
    compute_type,
    region,
    state_bucket,
    ssh_public_key,
    log_group,
    seed_parameter_prefix,
    buildspec,
    purpose,
) = sys.argv[1:]

env_vars = [
    {"name": "AWS_REGION", "value": region, "type": "PLAINTEXT"},
    {"name": "K8S_CLOUD", "value": "aws", "type": "PLAINTEXT"},
    {"name": "K8S_CLUSTER", "value": "aws", "type": "PLAINTEXT"},
    {"name": "COINOPS_TF_STATE_BUCKET", "value": state_bucket, "type": "PLAINTEXT"},
    {"name": "TF_VAR_seed_secret_manager", "value": "true", "type": "PLAINTEXT"},
    {"name": "TF_VAR_db_password", "value": f"{seed_parameter_prefix}/db_password", "type": "PARAMETER_STORE"},
    {"name": "TF_VAR_rabbitmq_password", "value": f"{seed_parameter_prefix}/rabbitmq_password", "type": "PARAMETER_STORE"},
    {"name": "TF_VAR_ghcr_token", "value": f"{seed_parameter_prefix}/ghcr_token", "type": "PARAMETER_STORE"},
    {"name": "TF_VAR_cloudflare_api_token", "value": f"{seed_parameter_prefix}/cloudflare_api_token", "type": "PARAMETER_STORE"},
]
if ssh_public_key:
    env_vars.append({
        "name": "COINOPS_SSH_PUBLIC_KEY",
        "value": ssh_public_key,
        "type": "PLAINTEXT",
    })

project = {
    "name": project_name,
    "description": f"Terraform {purpose} build for the Coin-Ops AWS k3s path.",
    "serviceRole": role_arn,
    "artifacts": {"type": "CODEPIPELINE"},
    "environment": {
        "type": "LINUX_CONTAINER",
        "image": image,
        "computeType": compute_type,
        "imagePullCredentialsType": "CODEBUILD",
        "environmentVariables": env_vars,
    },
    "source": {
        "type": "CODEPIPELINE",
        "buildspec": buildspec,
    },
    "logsConfig": {
        "cloudWatchLogs": {
            "status": "ENABLED",
            "groupName": log_group,
            "streamName": f"terraform-{purpose}",
        }
    },
    "tags": [
        {"key": "Project", "value": project_tag},
        {"key": "Purpose", "value": f"terraform-{purpose}"},
    ],
}
pathlib.Path(path).write_text(json.dumps(project), encoding="utf-8")
PY
}

ensure_codebuild_project() {
  local project_name="$1"
  local role_arn="$2"
  local buildspec="$3"
  local log_group="$4"
  local purpose="$5"
  local project_json="${WORK_DIR}/${project_name}-codebuild-project.json"
  write_codebuild_project_json "${project_json}" "${project_name}" "${role_arn}" "${buildspec}" "${log_group}" "${purpose}"

  local existing
  existing="$(aws codebuild batch-get-projects \
    --names "${project_name}" \
    --query 'projects[0].name' \
    --output text)"

  if [[ "${existing}" == "${project_name}" ]]; then
    echo "Updating CodeBuild project: ${project_name}"
    aws codebuild update-project --cli-input-json "file://${project_json}" >/dev/null
  else
    echo "Creating CodeBuild project: ${project_name}"
    aws codebuild create-project --cli-input-json "file://${project_json}" >/dev/null
  fi
}

write_pipeline_json() {
  local path="$1"

  python3 - "${path}" "${PIPELINE_NAME}" "${CODEPIPELINE_ROLE_ARN}" "${ARTIFACT_BUCKET}" "${GITHUB_CONNECTION_ARN}" "${GITHUB_REPO}" "${PIPELINE_BRANCH}" "${DETECT_CHANGES}" "${PLAN_CODEBUILD_PROJECT_NAME}" "${APPLY_CODEBUILD_PROJECT_NAME}" "${SMOKE_CODEBUILD_PROJECT_NAME}" "${APPROVAL_TOPIC_ARN}" <<'PY'
import json
import pathlib
import sys

(
    path,
    pipeline_name,
    role_arn,
    artifact_bucket,
    connection_arn,
    github_repo,
    branch,
    detect_changes,
    plan_codebuild_project,
    apply_codebuild_project,
    smoke_codebuild_project,
    approval_topic_arn,
) = sys.argv[1:]

pipeline = {
    "pipeline": {
        "name": pipeline_name,
        "roleArn": role_arn,
        "artifactStore": {"type": "S3", "location": artifact_bucket},
        "executionMode": "QUEUED",
        "stages": [
            {
                "name": "Source",
                "actions": [
                    {
                        "name": "Source",
                        "actionTypeId": {
                            "category": "Source",
                            "owner": "AWS",
                            "provider": "CodeStarSourceConnection",
                            "version": "1",
                        },
                        "outputArtifacts": [{"name": "source_output"}],
                        "configuration": {
                            "ConnectionArn": connection_arn,
                            "FullRepositoryId": github_repo,
                            "BranchName": branch,
                            "DetectChanges": detect_changes,
                        },
                        "runOrder": 1,
                    }
                ],
            },
            {
                "name": "Plan",
                "actions": [
                    {
                        "name": "TerraformPlan",
                        "actionTypeId": {
                            "category": "Build",
                            "owner": "AWS",
                            "provider": "CodeBuild",
                            "version": "1",
                        },
                        "inputArtifacts": [{"name": "source_output"}],
                        "outputArtifacts": [{"name": "plan_output"}],
                        "configuration": {"ProjectName": plan_codebuild_project},
                        "runOrder": 1,
                    }
                ],
            },
            {
                "name": "ApproveApply",
                "actions": [
                    {
                        "name": "ApproveTerraformApply",
                        "actionTypeId": {
                            "category": "Approval",
                            "owner": "AWS",
                            "provider": "Manual",
                            "version": "1",
                        },
                        "configuration": {
                            "CustomData": "Review terraform/plan.txt from the Plan artifact before approving apply.",
                            "NotificationArn": approval_topic_arn,
                        },
                        "runOrder": 1,
                    }
                ],
            },
            {
                "name": "Apply",
                "actions": [
                    {
                        "name": "TerraformApply",
                        "actionTypeId": {
                            "category": "Build",
                            "owner": "AWS",
                            "provider": "CodeBuild",
                            "version": "1",
                        },
                        "inputArtifacts": [
                            {"name": "source_output"},
                            {"name": "plan_output"},
                        ],
                        "configuration": {
                            "ProjectName": apply_codebuild_project,
                            "PrimarySource": "source_output",
                        },
                        "runOrder": 1,
                    }
                ],
            },
            {
                "name": "Smoke",
                "actions": [
                    {
                        "name": "PostApplySmoke",
                        "actionTypeId": {
                            "category": "Build",
                            "owner": "AWS",
                            "provider": "CodeBuild",
                            "version": "1",
                        },
                        "inputArtifacts": [{"name": "source_output"}],
                        "outputArtifacts": [{"name": "smoke_output"}],
                        "configuration": {"ProjectName": smoke_codebuild_project},
                        "runOrder": 1,
                    }
                ],
            },
        ],
    }
}
pathlib.Path(path).write_text(json.dumps(pipeline), encoding="utf-8")
PY
}

ensure_pipeline() {
  local pipeline_json="${WORK_DIR}/pipeline.json"
  write_pipeline_json "${pipeline_json}"

  if aws codepipeline get-pipeline --name "${PIPELINE_NAME}" >/dev/null 2>&1; then
    echo "Updating CodePipeline: ${PIPELINE_NAME}"
    aws codepipeline update-pipeline --cli-input-json "file://${pipeline_json}" >/dev/null
  else
    echo "Creating CodePipeline: ${PIPELINE_NAME}"
    aws codepipeline create-pipeline --cli-input-json "file://${pipeline_json}" >/dev/null
  fi
}

require_tool aws
require_tool python3

if [[ "${SKIP_TERRAFORM_BOOTSTRAP}" == "false" ]]; then
  echo "Bootstrapping AWS Terraform backend and operator credentials..."
  bash "${REPO_ROOT}/terraform/bootstrap-aws.sh" --activate-backend
fi

read -r PROJECT_NAME AWS_REGION STATE_BUCKET_PREFIX STATE_KEY DB_SECRET_NAME APP_SECRET_NAME < <(read_config)
export AWS_REGION

ACCOUNT_ID="$(aws_text sts get-caller-identity --query Account)"
STATE_BUCKET="${COINOPS_TF_STATE_BUCKET:-${STATE_BUCKET_PREFIX}-${ACCOUNT_ID}-${AWS_REGION}}"
PIPELINE_NAME="${COINOPS_CI_PIPELINE_NAME:-${PROJECT_NAME}-k3s-deploy}"
PLAN_CODEBUILD_PROJECT_NAME="${COINOPS_CI_PLAN_CODEBUILD_PROJECT_NAME:-${COINOPS_CI_CODEBUILD_PROJECT_NAME:-${PIPELINE_NAME}}}"
APPLY_CODEBUILD_PROJECT_NAME="${COINOPS_CI_APPLY_CODEBUILD_PROJECT_NAME:-${PIPELINE_NAME}-apply}"
SMOKE_CODEBUILD_PROJECT_NAME="${COINOPS_CI_SMOKE_CODEBUILD_PROJECT_NAME:-${PIPELINE_NAME}-smoke}"
ARTIFACT_BUCKET="${COINOPS_CI_ARTIFACT_BUCKET:-${PROJECT_NAME}-codepipeline-artifacts-${ACCOUNT_ID}-${AWS_REGION}}"
PIPELINE_BRANCH="${COINOPS_CI_BRANCH:-$(git -C "${REPO_ROOT}" branch --show-current 2>/dev/null || echo hrenchevskyi-codebuild)}"
GITHUB_REPO="${COINOPS_CI_GITHUB_REPO:-}"
CONNECTION_NAME="${COINOPS_CI_GITHUB_CONNECTION_NAME:-${PROJECT_NAME}-github}"
DETECT_CHANGES="${COINOPS_CI_DETECT_CHANGES:-false}"
APPROVAL_TOPIC_NAME="${COINOPS_CI_APPROVAL_TOPIC_NAME:-${PIPELINE_NAME}-approvals}"
APPROVAL_NOTIFICATION_EMAIL="${COINOPS_CI_APPROVAL_NOTIFICATION_EMAIL:-}"
CODEBUILD_IMAGE="${COINOPS_CI_CODEBUILD_IMAGE:-aws/codebuild/standard:7.0}"
CODEBUILD_COMPUTE_TYPE="${COINOPS_CI_CODEBUILD_COMPUTE_TYPE:-BUILD_GENERAL1_SMALL}"
PLAN_CODEBUILD_ROLE_NAME="${COINOPS_CI_PLAN_CODEBUILD_ROLE_NAME:-${COINOPS_CI_CODEBUILD_ROLE_NAME:-${PIPELINE_NAME}-codebuild}}"
APPLY_CODEBUILD_ROLE_NAME="${COINOPS_CI_APPLY_CODEBUILD_ROLE_NAME:-${PIPELINE_NAME}-apply-codebuild}"
SMOKE_CODEBUILD_ROLE_NAME="${COINOPS_CI_SMOKE_CODEBUILD_ROLE_NAME:-${PIPELINE_NAME}-smoke-codebuild}"
CODEPIPELINE_ROLE_NAME="${COINOPS_CI_CODEPIPELINE_ROLE_NAME:-${PIPELINE_NAME}-codepipeline}"
PLAN_CODEBUILD_LOG_GROUP="${COINOPS_CI_PLAN_CODEBUILD_LOG_GROUP:-${COINOPS_CI_CODEBUILD_LOG_GROUP:-/aws/codebuild/${PLAN_CODEBUILD_PROJECT_NAME}}}"
APPLY_CODEBUILD_LOG_GROUP="${COINOPS_CI_APPLY_CODEBUILD_LOG_GROUP:-/aws/codebuild/${APPLY_CODEBUILD_PROJECT_NAME}}"
SMOKE_CODEBUILD_LOG_GROUP="${COINOPS_CI_SMOKE_CODEBUILD_LOG_GROUP:-/aws/codebuild/${SMOKE_CODEBUILD_PROJECT_NAME}}"
SEED_PARAMETER_PREFIX="${COINOPS_CI_SEED_PARAMETER_PREFIX:-/${PROJECT_NAME}/ci/terraform}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [[ -z "${GITHUB_REPO}" ]]; then
  echo "COINOPS_CI_GITHUB_REPO is required, for example owner/repository." >&2
  exit 1
fi

GITHUB_CONNECTION_ARN="$(ensure_connection_arn)"

ensure_artifact_bucket
ensure_log_group "${PLAN_CODEBUILD_LOG_GROUP}"
ensure_log_group "${APPLY_CODEBUILD_LOG_GROUP}"
ensure_log_group "${SMOKE_CODEBUILD_LOG_GROUP}"
ensure_seed_parameters
ensure_approval_topic
ensure_iam

# IAM role propagation is eventually consistent.
sleep "${COINOPS_CI_IAM_PROPAGATION_SLEEP_SECONDS:-10}"

ensure_codebuild_project "${PLAN_CODEBUILD_PROJECT_NAME}" "${PLAN_CODEBUILD_ROLE_ARN}" "ci/aws/buildspec.k3s-terraform-plan.yml" "${PLAN_CODEBUILD_LOG_GROUP}" "plan"
ensure_codebuild_project "${APPLY_CODEBUILD_PROJECT_NAME}" "${APPLY_CODEBUILD_ROLE_ARN}" "ci/aws/buildspec.k3s-terraform-apply.yml" "${APPLY_CODEBUILD_LOG_GROUP}" "apply"
ensure_codebuild_project "${SMOKE_CODEBUILD_PROJECT_NAME}" "${SMOKE_CODEBUILD_ROLE_ARN}" "ci/aws/buildspec.k3s-terraform-smoke.yml" "${SMOKE_CODEBUILD_LOG_GROUP}" "smoke"
ensure_pipeline

cat <<EOF

AWS CodeBuild deploy pipeline bootstrap completed.

Pipeline:              ${PIPELINE_NAME}
Plan CodeBuild project:${PLAN_CODEBUILD_PROJECT_NAME}
Apply CodeBuild project:${APPLY_CODEBUILD_PROJECT_NAME}
Smoke CodeBuild project:${SMOKE_CODEBUILD_PROJECT_NAME}
Approval SNS topic:    ${APPROVAL_TOPIC_ARN}
Artifact bucket:       ${ARTIFACT_BUCKET}
Terraform state bucket:${STATE_BUCKET}
GitHub repository:     ${GITHUB_REPO}
GitHub branch:         ${PIPELINE_BRANCH}
GitHub connection ARN: ${GITHUB_CONNECTION_ARN}

Next verification:
  aws codepipeline start-pipeline-execution --name ${PIPELINE_NAME}
  aws codepipeline get-pipeline-state --name ${PIPELINE_NAME}
EOF
