#!/usr/bin/env bash
# generate_inventory.sh
# Generates ansible/inventory.ini from current Terraform outputs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/ansible/inventory.ini"

echo "Fetching Terraform outputs..."
PUBLIC_IP=$(terraform -chdir="${SCRIPT_DIR}" output -raw pfsense_public_ip)

cat >"${INVENTORY}" <<EOF
[pfsense]
pfsense-fw ansible_host=${PUBLIC_IP}
EOF

echo "Inventory written to ${INVENTORY}"
echo "  pfsense-fw  →  ${PUBLIC_IP}"
