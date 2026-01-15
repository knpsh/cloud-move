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

INPUT_DIR="groups"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Error: Input directory not found: ${INPUT_DIR}" >&2
  exit 1
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Organization ID: ${ORGANIZATION_ID}"
log "Input directory: ${INPUT_DIR}"
log ""

group_files=$(find "${INPUT_DIR}" -name "*.json" -type f)

if [[ -z "$group_files" ]]; then
  log "No group files found"
  exit 0
fi

group_count=$(echo "$group_files" | wc -l)
log "Creating ${group_count} groups..."
log ""

echo "$group_files" | while read -r group_file; do
  group_name=$(jq -r '.name' < "$group_file")

  log "Creating group: ${group_name}"
  log "  From file: ${group_file}"

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