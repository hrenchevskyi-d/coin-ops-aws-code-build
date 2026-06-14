#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

verify_tools() {
  local missing=0
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "Missing required tool: ${tool}" >&2
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    return 1
  fi
}

render_backend() {
  local backend_path="${REPO_ROOT}/terraform/backend.active.tf"
  local template_path="${REPO_ROOT}/terraform/backends/backend.aws.tf.tmpl"
  local backend_key
  local bucket_prefix
  local region
  local bucket

  read -r backend_key bucket_prefix region < <(
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
with (config_dir / "cloud_mappings.json").open(encoding="utf-8") as handle:
    mappings = json.load(handle)

backend = clouds.get("backends", {}).get("aws", {})
region_profile = general.get("region_profile")
region = env_region or mappings["regions"]["aws"][region_profile]["region"]

print(
    backend.get("key", "infra/state/terraform.tfstate"),
    backend.get("bucket_prefix", "coinops-terraform-state"),
    region,
)
PY
  )

  bucket="${COINOPS_TF_STATE_BUCKET:-${TF_BACKEND_BUCKET:-}}"
  if [[ -z "${bucket}" ]]; then
    verify_tools aws
    local account_id
    account_id="$(aws sts get-caller-identity --query Account --output text)"
    bucket="${bucket_prefix}-${account_id}-${region}"
  fi

  python3 - "${template_path}" "${backend_path}" "${bucket}" "${backend_key}" "${region}" <<'PY'
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1])
backend_path = pathlib.Path(sys.argv[2])
bucket = sys.argv[3]
key = sys.argv[4]
region = sys.argv[5]

content = template_path.read_text(encoding="utf-8")
content = content.replace("__AWS_STATE_BUCKET__", bucket)
content = content.replace("__AWS_STATE_KEY__", key)
content = content.replace("__AWS_STATE_REGION__", region)
backend_path.write_text(content, encoding="utf-8")
PY

  echo "Rendered ${backend_path} for AWS S3 backend."
}

if [[ "${1:-}" == "verify-tools" ]]; then
  shift
  verify_tools "$@"
  exit 0
fi

if [[ "${1:-}" == "render-backend" ]]; then
  render_backend
  exit 0
fi

export REPO_ROOT
export TF_IN_AUTOMATION="${TF_IN_AUTOMATION:-true}"
export TF_INPUT="${TF_INPUT:-false}"
export K8S_CLOUD="${K8S_CLOUD:-aws}"
export K8S_CLUSTER="${K8S_CLUSTER:-${K8S_CLOUD}}"
export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-${REPO_ROOT}/ansible.cfg}"
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}"
export ANSIBLE_REMOTE_TEMP="${ANSIBLE_REMOTE_TEMP:-/tmp/ansible-remote}"

mkdir -p "${ANSIBLE_LOCAL_TEMP}" "${ANSIBLE_REMOTE_TEMP}"

if [[ -z "${AWS_REGION:-}" && -n "${TF_VAR_aws_region:-}" ]]; then
  export AWS_REGION="${TF_VAR_aws_region}"
fi

if [[ -n "${AWS_REGION:-}" && -z "${TF_VAR_aws_region:-}" ]]; then
  export TF_VAR_aws_region="${AWS_REGION}"
fi

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "AWS_REGION is not set; Terraform will fall back to terraform/config/*.json defaults." >&2
fi
