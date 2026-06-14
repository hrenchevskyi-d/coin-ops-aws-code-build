#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Bootstrapping AWS Terraform backend and operator credentials..."
bash "${REPO_ROOT}/terraform/bootstrap-aws.sh" --activate-backend

cat <<EOF

AWS local bootstrap completed.

Next verification:
  source ${REPO_ROOT}/local/generated-env.sh
  cd ${REPO_ROOT}/terraform
  terraform init -reconfigure
  terraform validate
EOF
