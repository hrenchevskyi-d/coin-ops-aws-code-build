#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
BACKEND_FILE="$TF_DIR/backend.active.tf"
BACKEND_TMP_DIR=""
TF_DATA_DIR="$(mktemp -d)"
export TF_DATA_DIR

cleanup() {
  if [ -n "$BACKEND_TMP_DIR" ] && [ -f "$BACKEND_TMP_DIR/backend.active.tf" ]; then
    mv "$BACKEND_TMP_DIR/backend.active.tf" "$BACKEND_FILE"
    rmdir "$BACKEND_TMP_DIR"
  fi
  if [ -n "$TF_DATA_DIR" ] && [ -d "$TF_DATA_DIR" ]; then
    rm -rf "$TF_DATA_DIR"
  fi
}

trap cleanup EXIT

if [ -f "$BACKEND_FILE" ]; then
  BACKEND_TMP_DIR="$(mktemp -d)"
  mv "$BACKEND_FILE" "$BACKEND_TMP_DIR/backend.active.tf"
fi

terraform -chdir="$TF_DIR" fmt -check -recursive
terraform -chdir="$TF_DIR" init -backend=false -reconfigure
terraform -chdir="$TF_DIR" validate
