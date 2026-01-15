#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./dump_groups.sh <target-organization-id>

ORGANIZATION_ID="${1:-}"

if [[ -z "$ORGANIZATION_ID" ]]; then
  echo "Usage: $0 <organization-id>" >&2
  exit 1
fi

command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

ROOT_DIR="groups"
OUTPUT_FILE="${ROOT_DIR}/target-groups.json"

mkdir -p "${ROOT_DIR}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Organization: ${ORGANIZATION_ID}"
log "Output file:  ${OUTPUT_FILE}"
log ""

log "Fetching groups list..."
YC_GROUPS=$(yc organization-manager group list --organization-id "${ORGANIZATION_ID}" --format json)

if [[ $(echo "$YC_GROUPS" | jq 'length') -eq 0 ]]; then
  log "No groups found"
  echo "[]" > "${OUTPUT_FILE}"
  exit 0
fi

echo "$YC_GROUPS" | jq '[.[] | {id: .id, name: .name}]' > "${OUTPUT_FILE}"

group_count=$(jq 'length' < "${OUTPUT_FILE}")
log "Saved ${group_count} groups to: ${OUTPUT_FILE}"
log ""
log "Done."