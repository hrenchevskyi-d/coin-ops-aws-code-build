#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}"
export ANSIBLE_REMOTE_TEMP="${ANSIBLE_REMOTE_TEMP:-/tmp/ansible-remote}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/ansible-lint-cache}"

if command -v ansible-lint >/dev/null 2>&1; then
  ANSIBLE_LINT="ansible-lint"
elif [ -x "$REPO_ROOT/.venv/bin/ansible-lint" ]; then
  ANSIBLE_LINT="$REPO_ROOT/.venv/bin/ansible-lint"
else
  cat >&2 <<'EOF'
ansible-lint is required to lint ansible/.

Install it locally with one of:
  .venv/bin/python -m pip install ansible-lint
  pipx install ansible-lint

GitHub Actions installs it automatically.
EOF
  exit 127
fi

"$ANSIBLE_LINT" "$REPO_ROOT/ansible"
