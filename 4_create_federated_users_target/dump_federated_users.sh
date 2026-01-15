#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./dump_federated_users.sh <federation-id>

FEDERATION_ID="${1:-}"

if [[ -z "$FEDERATION_ID" ]]; then
  echo "Usage: $0 <federation-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

ROOT_DIR="federatedusers"
OUTPUT_FILE="${ROOT_DIR}/target-users.json"

mkdir -p "${ROOT_DIR}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Federation ID: ${FEDERATION_ID}"
log "Output file:   ${OUTPUT_FILE}"
log ""

log "Fetching federated users..."
USERS=$(yc organization-manager federation saml list-user-accounts --id "${FEDERATION_ID}" --format json)

if [[ $(echo "$USERS" | jq 'length') -eq 0 ]]; then
  log "No federated users found"
  echo "[]" > "${OUTPUT_FILE}"
  exit 0
fi

# Extract only id and name_id fields
echo "$USERS" | jq '[.[] | {id: .id, name_id: .saml_user_account.name_id}]' > "${OUTPUT_FILE}"

user_count=$(echo "$USERS" | jq 'length')
log "Saved ${user_count} federated users to: ${OUTPUT_FILE}"
log ""
log "Done."