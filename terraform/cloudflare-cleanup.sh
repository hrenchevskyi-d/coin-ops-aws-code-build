#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}"
PRUNE_STATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prune-state)
      PRUNE_STATE=true
      shift
      ;;
    *)
      echo "Unsupported argument: $1" >&2
      exit 1
      ;;
  esac
done

read_tfvar_value() {
  local tfvars_path="$1"
  local key="$2"

  python3 - <<'PY' "${tfvars_path}" "${key}"
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
if not path.exists():
    raise SystemExit(0)
pattern = re.compile(rf'^\s*{re.escape(key)}\s*=\s*"(.*)"\s*$')
for line in path.read_text(encoding="utf-8").splitlines():
    match = pattern.match(line)
    if match:
        value = match.group(1).strip()
        if value not in {"", "CHANGE_ME", "not_serious_just_a_placeholder"}:
            print(value)
        break
PY
}

load_context() {
  eval "$(python3 - <<'PY' "${TERRAFORM_DIR}"
import json
import pathlib
import shlex
import sys

root = pathlib.Path(sys.argv[1])
general = json.loads((root / 'config' / 'general.json').read_text(encoding='utf-8')).get('general', {})
deploy = json.loads((root / 'config' / 'deploy.json').read_text(encoding='utf-8')).get('deploy', {})
dns = json.loads((root / 'config' / 'dns.json').read_text(encoding='utf-8')).get('dns', {})
project_name = general.get('project_name', 'coin-ops')
app_domain = deploy.get('app_domain', 'coinops.test')
headlamp_domain = deploy.get('headlamp', {}).get('hostname', f'headlamp.{app_domain}')
cloudflare = dns.get('cloudflare', {})
values = {
    'CF_ACCOUNT_ID': cloudflare.get('account_id', ''),
    'CF_ZONE_ID': cloudflare.get('zone_id', ''),
    'CF_HEADLAMP_DOMAIN': headlamp_domain,
    'CF_TUNNEL_NAME': f'{project_name}-headlamp',
    'CF_TUNNEL_NAME_LEGACY': 'headlamp',
    'CF_IDP_NAME': f'{project_name}-headlamp-github',
}
print(' '.join(f'{key}={shlex.quote(str(value))}' for key, value in values.items()))
PY
)"

  CF_API_TOKEN="${TF_VAR_cloudflare_api_token:-${CLOUDFLARE_API_TOKEN:-}}"
  if [[ -z "${CF_API_TOKEN}" ]]; then
    CF_API_TOKEN="$(read_tfvar_value "${TERRAFORM_DIR}/bootstrap.secrets.auto.tfvars" cloudflare_api_token)"
  fi
}

cf_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url="https://api.cloudflare.com/client/v4${path}"

  if [[ -n "${body}" ]]; then
    curl -fsS -X "${method}" "${url}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H 'Content-Type: application/json' \
      --data "${body}"
  else
    curl -fsS -X "${method}" "${url}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H 'Content-Type: application/json'
  fi
}

state_rm_prefix() {
  local prefix="$1"
  local address
  if [[ "${PRUNE_STATE}" != "true" ]]; then
    return 0
  fi
  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  while IFS= read -r address; do
    [[ -n "${address}" ]] || continue
    terraform state rm "${address}" >/dev/null 2>&1 || true
  done < <(terraform state list | grep -F "${prefix}" || true)
}

load_context

if [[ -z "${CF_API_TOKEN}" || -z "${CF_ACCOUNT_ID}" || -z "${CF_ZONE_ID}" ]]; then
  echo "Skipping Cloudflare cleanup: Cloudflare token/account_id/zone_id is incomplete."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Skipping Cloudflare cleanup: curl is not available."
  exit 0
fi

echo "Cleaning Cloudflare Tunnel, Access, and tunnel DNS resources for ${CF_HEADLAMP_DOMAIN}..."

apps_json="$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/access/apps?per_page=1000")"
idps_json="$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/access/identity_providers")"
tunnels_json="$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?is_deleted=false&per_page=1000")"
dns_json="$(cf_api GET "/zones/${CF_ZONE_ID}/dns_records?name=${CF_HEADLAMP_DOMAIN}&per_page=100")"

# Delete Access apps and all policies under the matching Headlamp domain.
while IFS= read -r app_id; do
  [[ -n "${app_id}" ]] || continue
  policies_json="$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/access/apps/${app_id}/policies")"
  while IFS= read -r policy_id; do
    [[ -n "${policy_id}" ]] || continue
    echo "Deleting Cloudflare Access policy ${policy_id}..."
    cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/access/apps/${app_id}/policies/${policy_id}" >/dev/null || true
  done < <(python3 - <<'PY' "${policies_json}"
import json, sys
for item in json.loads(sys.argv[1]).get('result', []):
    if item.get('id'):
        print(item['id'])
PY
)
  echo "Deleting Cloudflare Access app ${app_id}..."
  cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/access/apps/${app_id}" >/dev/null || true
done < <(python3 - <<'PY' "${apps_json}" "${CF_HEADLAMP_DOMAIN}"
import json, sys
apps = json.loads(sys.argv[1]).get('result', [])
domain = sys.argv[2]
for item in apps:
    if item.get('domain') == domain and item.get('id'):
        print(item['id'])
PY
)

# Delete the project-specific GitHub identity provider if present.
while IFS= read -r idp_id; do
  [[ -n "${idp_id}" ]] || continue
  echo "Deleting Cloudflare Access identity provider ${idp_id}..."
  cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/access/identity_providers/${idp_id}" >/dev/null || true
done < <(python3 - <<'PY' "${idps_json}" "${CF_IDP_NAME}"
import json, sys
idps = json.loads(sys.argv[1]).get('result', [])
name = sys.argv[2]
for item in idps:
    if item.get('name') == name and item.get('id'):
        print(item['id'])
PY
)

# Delete current and legacy Headlamp tunnels by name.
while IFS= read -r tunnel_id; do
  [[ -n "${tunnel_id}" ]] || continue
  echo "Deleting Cloudflare Tunnel ${tunnel_id}..."
  cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}" >/dev/null || true
done < <(python3 - <<'PY' "${tunnels_json}" "${CF_TUNNEL_NAME}" "${CF_TUNNEL_NAME_LEGACY}"
import json, sys
items = json.loads(sys.argv[1]).get('result', [])
names = {sys.argv[2], sys.argv[3]}
for item in items:
    if item.get('name') in names and item.get('id'):
        print(item['id'])
PY
)

# Delete tunnel CNAME records for the Headlamp hostname.
while IFS= read -r dns_record_id; do
  [[ -n "${dns_record_id}" ]] || continue
  echo "Deleting Cloudflare DNS record ${dns_record_id} for ${CF_HEADLAMP_DOMAIN}..."
  cf_api DELETE "/zones/${CF_ZONE_ID}/dns_records/${dns_record_id}" >/dev/null || true
done < <(python3 - <<'PY' "${dns_json}"
import json, sys
items = json.loads(sys.argv[1]).get('result', [])
for item in items:
    if item.get('type') == 'CNAME' and item.get('content', '').endswith('.cfargotunnel.com') and item.get('id'):
        print(item['id'])
PY
)

state_rm_prefix 'cloudflare_zero_trust_access_policy.headlamp'
state_rm_prefix 'cloudflare_zero_trust_access_application.headlamp'
state_rm_prefix 'cloudflare_zero_trust_access_identity_provider.github'
state_rm_prefix 'cloudflare_zero_trust_tunnel_cloudflared_config.headlamp'
state_rm_prefix 'cloudflare_zero_trust_tunnel_cloudflared.headlamp'
state_rm_prefix 'random_bytes.headlamp_tunnel_secret'
state_rm_prefix 'module.cloudflare_dns_records'
