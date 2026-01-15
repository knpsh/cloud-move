#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./create_users.sh <target-federation-id>

FEDERATION_ID="${1:-}"

if [[ -z "$FEDERATION_ID" ]]; then
  echo "Usage: $0 <federation-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

INPUT_FILE="federatedusers/users.json"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: Input file not found: ${INPUT_FILE}" >&2
  exit 1
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Federation ID: ${FEDERATION_ID}"
log "Input file:    ${INPUT_FILE}"
log ""

user_count=$(jq 'length' < "${INPUT_FILE}")

if [[ "$user_count" -eq 0 ]]; then
  log "No users to create"
  exit 0
fi

log "Creating ${user_count} federated users..."
log ""

jq -c '.[]' < "${INPUT_FILE}" | while read -r user; do
  name_id=$(jq -r '.name_id' <<< "$user")

  log "Creating user: ${name_id}"

  if yc organization-manager federation saml add-user-accounts \
    --id "${FEDERATION_ID}" \
    --name-ids "${name_id}" 2>&1; then
    log "  ✓ Successfully created: ${name_id}"
  else
    log "  ✗ Failed to create: ${name_id}"
  fi

  log ""
done

log "Done."