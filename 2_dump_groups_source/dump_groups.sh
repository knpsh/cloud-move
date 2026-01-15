#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./dump_groups.sh <source-organization-id>

ORGANIZATION_ID="${1:-}"

if [[ -z "$ORGANIZATION_ID" ]]; then
  echo "Usage: $0 <organization-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

ROOT_DIR="groups"
OUTPUT_FILE="${ROOT_DIR}/groups.json"

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

# Initialize empty array
echo "[]" > "${OUTPUT_FILE}"

echo "$YC_GROUPS" | jq -c '.[]' | while read -r group; do
  group_id=$(jq -r '.id' <<< "$group")
  group_name=$(jq -r '.name' <<< "$group")

  log "Processing group: ${group_name} (${group_id})"

  # Fetch group members
  members=$(yc organization-manager group list-members "${group_id}" --format json 2>/dev/null || echo "[]")

  # Append to the output file
  jq --argjson new_group "$(jq -n \
    --arg id "$group_id" \
    --arg name "$group_name" \
    --argjson members "$members" \
    '{id: $id, name: $name, members: $members}')" \
    '. += [$new_group]' "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"

  log "  Added to: ${OUTPUT_FILE}"
done

group_count=$(jq 'length' < "${OUTPUT_FILE}")
log ""
log "Done."
log "Saved ${group_count} groups to: ${OUTPUT_FILE}"