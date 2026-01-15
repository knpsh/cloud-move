#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./revert_deletion_groups.sh <source-cloud-id>

CLOUD_ID="${1:-}"

if [[ -z "$CLOUD_ID" ]]; then
  echo "Usage: $0 <cloud-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

INPUT_FILE="bindings/${CLOUD_ID}/groups.jsonl"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: Input file not found: ${INPUT_FILE}" >&2
  exit 1
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Cloud ID: ${CLOUD_ID}"
log "Input file: ${INPUT_FILE}"
log ""

binding_count=$(wc -l < "${INPUT_FILE}" | tr -d ' ')

if [[ "$binding_count" -eq 0 ]]; then
  log "No bindings to restore"
  exit 0
fi

log "Restoring ${binding_count} group bindings..."
log ""

while IFS= read -r line; do
  group_id=$(jq -r '.id' <<< "$line")
  role_id=$(jq -r '.role_id' <<< "$line")
  cloud_id=$(jq -r '.cloud_id // empty' <<< "$line")
  folder_id=$(jq -r '.folder_id // empty' <<< "$line")

  if [[ -n "$cloud_id" ]]; then
    log "Restoring cloud binding: group ${group_id} - role: ${role_id}"
    log "  Cloud: ${cloud_id}"

    if yc resource-manager cloud add-access-binding \
      --id "${cloud_id}" \
      --role "${role_id}" \
      --subject group:"${group_id}" 2>&1; then
      log "  ✓ Successfully restored cloud binding"
    else
      log "  ✗ Failed to restore cloud binding"
    fi

  elif [[ -n "$folder_id" ]]; then
    log "Restoring folder binding: group ${group_id} - role: ${role_id}"
    log "  Folder: ${folder_id}"

    if yc resource-manager folder add-access-binding \
      --id "${folder_id}" \
      --role "${role_id}" \
      --subject group:"${group_id}" 2>&1; then
      log "  ✓ Successfully restored folder binding"
    else
      log "  ✗ Failed to restore folder binding"
    fi

  else
    log "WARNING: No cloud_id or folder_id found for binding: ${group_id}"
  fi

  log ""
done < "${INPUT_FILE}"

log "Done."
log "Restored bindings for ${binding_count} groups."