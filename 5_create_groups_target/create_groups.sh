#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./create_groups.sh <target-organization-id>

ORGANIZATION_ID="${1:-}"

if [[ -z "$ORGANIZATION_ID" ]]; then
  echo "Usage: $0 <organization-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

INPUT_FILE="groups/groups.json"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: Input file not found: ${INPUT_FILE}" >&2
  exit 1
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Organization ID: ${ORGANIZATION_ID}"
log "Input file: ${INPUT_FILE}"
log ""

group_count=$(jq 'length' < "${INPUT_FILE}")

if [[ "$group_count" -eq 0 ]]; then
  log "No groups to create"
  exit 0
fi

log "Creating ${group_count} groups..."
log ""

jq -c '.[]' < "${INPUT_FILE}" | while read -r group; do
  group_name=$(jq -r '.name' <<< "$group")

  log "Creating group: ${group_name}"

  if yc organization-manager group create \
    --name "${group_name}" \
    --organization-id "${ORGANIZATION_ID}" 2>&1; then
    log "  ✓ Successfully created: ${group_name}"
  else
    log "  ✗ Failed to create: ${group_name}"
  fi

  log ""
done

log "Done."