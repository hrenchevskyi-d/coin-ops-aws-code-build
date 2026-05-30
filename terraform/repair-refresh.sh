#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash repair-refresh.sh --enabled gcp plan
  bash repair-refresh.sh --enabled gcp apply

Runs refresh-only from an isolated temporary Terraform copy for state repair.
It can narrow enabled clouds, disables secret-version reads, and stubs disabled
Azure wiring so broken or partially deleted resources do not block refresh.

Use "plan" first. Use "apply" only after reviewing the refresh-only diff.
EOF
}

if [[ "${1:-}" != "--enabled" || -z "${2:-}" || -z "${3:-}" ]]; then
  usage
  exit 1
fi

ENABLED_CLOUDS_RAW="$2"
ACTION="$3"
shift 3

if [[ "${ACTION}" != "plan" && "${ACTION}" != "apply" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/coinops-repair-refresh.XXXXXX")"
TMP_TERRAFORM_DIR="${TMP_ROOT}/terraform"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TMP_TERRAFORM_DIR}"
cp -a "${TERRAFORM_DIR}/." "${TMP_TERRAFORM_DIR}/"
rm -rf "${TMP_TERRAFORM_DIR}/.terraform"

python3 - <<'PY' "${TMP_TERRAFORM_DIR}" "${ENABLED_CLOUDS_RAW}"
import json
import pathlib
import re
import shutil
import sys

terraform_dir = pathlib.Path(sys.argv[1])
enabled_clouds = [cloud.strip() for cloud in sys.argv[2].split(",") if cloud.strip()]
enabled_clouds_set = set(enabled_clouds)

if not enabled_clouds:
    raise SystemExit("At least one enabled cloud is required.")

def remove_hcl_block(content, start):
    line_start = content.rfind("\n", 0, start) + 1
    open_brace = content.find("{", start)
    if open_brace == -1:
        return content
    depth = 0
    in_string = False
    escape = False
    for pos in range(open_brace, len(content)):
        char = content[pos]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                line_end = content.find("\n", pos)
                line_end = len(content) if line_end == -1 else line_end + 1
                return content[:line_start] + content[line_end:]
    return content

def remove_required_provider(content, provider_name):
    match = re.search(rf"(?m)^\s*{re.escape(provider_name)}\s*=\s*\{{", content)
    return remove_hcl_block(content, match.start()) if match else content

def remove_provider_block(content, provider_name):
    match = re.search(rf'(?m)^provider\s+"{re.escape(provider_name)}"\s*\{{', content)
    return remove_hcl_block(content, match.start()) if match else content

clouds_path = terraform_dir / "config" / "clouds.json"
clouds_data = json.loads(clouds_path.read_text(encoding="utf-8"))
clouds_data.setdefault("clouds", {})["enabled"] = enabled_clouds
if clouds_data["clouds"].get("control_plane") not in enabled_clouds_set:
    clouds_data["clouds"]["control_plane"] = enabled_clouds[0]
if clouds_data["clouds"].get("secret_backend") not in enabled_clouds_set:
    clouds_data["clouds"]["secret_backend"] = enabled_clouds[0]
clouds_path.write_text(json.dumps(clouds_data, indent=4) + "\n", encoding="utf-8")

locals_path = terraform_dir / "locals.tf"
locals_content = locals_path.read_text(encoding="utf-8")
for name in ("gcp", "aws", "azure"):
    locals_content = re.sub(
        rf"(\s*)read_{name}_secret_backend\s*=.*",
        rf"\1read_{name}_secret_backend = false",
        locals_content,
    )
    locals_content = re.sub(
        rf"(\s*){name}_db_secrets\s*=.*",
        rf"\1{name}_db_secrets  = {{}}",
        locals_content,
    )
    locals_content = re.sub(
        rf"(\s*){name}_app_secrets\s*=.*",
        rf"\1{name}_app_secrets = {{}}",
        locals_content,
    )
locals_path.write_text(locals_content, encoding="utf-8")

if "azure" not in enabled_clouds_set:
    shutil.rmtree(terraform_dir / "modules" / "cloud" / "azure", ignore_errors=True)

    disabled_module_dir = terraform_dir / "modules" / "cloud" / "disabled"
    disabled_module_dir.mkdir(parents=True, exist_ok=True)
    (disabled_module_dir / "main.tf").write_text("", encoding="utf-8")

    (terraform_dir / "azure.tf").write_text(
        """module "azure_network" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_security_groups" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_instances" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_nat_route" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_database" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_secrets" {
  count  = 0
  source = "./modules/cloud/disabled"
}
""",
        encoding="utf-8",
    )

    providers_path = terraform_dir / "providers.tf"
    providers = providers_path.read_text(encoding="utf-8")
    providers = remove_required_provider(providers, "azurerm")
    providers = remove_provider_block(providers, "azurerm")
    providers_path.write_text(providers, encoding="utf-8")

    azurerm_refs = [
        str(path.relative_to(terraform_dir))
        for path in terraform_dir.rglob("*.tf")
        if ".terraform" not in path.parts and "azurerm" in path.read_text(encoding="utf-8", errors="ignore")
    ]
    if azurerm_refs:
        raise SystemExit("Azure provider references remain in repair copy: " + ", ".join(azurerm_refs))
PY

cat <<EOF
Prepared isolated Terraform repair copy:
  ${TMP_TERRAFORM_DIR}

Enabled clouds for repair: ${ENABLED_CLOUDS_RAW}
Secret-version data reads are disabled in the temporary copy.
EOF

cd "${TMP_TERRAFORM_DIR}"
terraform init -reconfigure

if [[ "${ACTION}" == "plan" ]]; then
  terraform plan -refresh-only "$@"
else
  terraform apply -refresh-only "$@"
fi
