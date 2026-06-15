#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v check-jsonschema >/dev/null 2>&1; then
  CHECK_JSONSCHEMA="check-jsonschema"
elif [ -x "$REPO_ROOT/.venv/bin/check-jsonschema" ]; then
  CHECK_JSONSCHEMA="$REPO_ROOT/.venv/bin/check-jsonschema"
else
  cat >&2 <<'EOF'
check-jsonschema is required to validate terraform/config/*.json.

Install it locally with one of:
  python3 -m pip install --user check-jsonschema
  .venv/bin/python -m pip install check-jsonschema
  pipx install check-jsonschema

GitHub Actions installs it automatically.
EOF
  exit 127
fi

validate() {
  local schema="$1"
  local document="$2"

  echo "Validating ${document#"$REPO_ROOT"/}"
  "$CHECK_JSONSCHEMA" \
    --schemafile "$REPO_ROOT/$schema" \
    "$REPO_ROOT/$document"
}

validate schemas/terraform-config/clouds.schema.json terraform/config/clouds.json
validate schemas/terraform-config/general.schema.json terraform/config/general.json
validate schemas/terraform-config/deploy.schema.json terraform/config/deploy.json
validate schemas/terraform-config/database.schema.json terraform/config/database.json
validate schemas/terraform-config/dns.schema.json terraform/config/dns.json
validate schemas/terraform-config/secrets.schema.json terraform/config/secrets.json
validate schemas/terraform-config/instances.schema.json terraform/config/instances.json
validate schemas/terraform-config/networks.schema.json terraform/config/networks.json
validate schemas/terraform-config/cloud-mappings.schema.json terraform/config/cloud_mappings.json
validate schemas/terraform-config/observability.schema.json terraform/config/observability.json
