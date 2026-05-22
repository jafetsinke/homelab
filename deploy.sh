#!/usr/bin/env bash
# Rebuild the Ubuntu golden template (Packer) and apply OpenTofu infra.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> packer init + build (recreate template)"
cd "$ROOT/packer"
packer init .
packer build -force .

echo "==> tofu apply"
cd "$ROOT/opentofu"
tofu apply -auto-approve
