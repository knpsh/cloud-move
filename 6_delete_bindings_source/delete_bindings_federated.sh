#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./delete_bindings.sh <cloud-id>

CLOUD_ID="${1:-}"

if [[ -z "$CLOUD_ID" ]]; then
  echo "Usage: $0 <cloud-id>" >&2
  exit 1
fi

command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

INPUT_FILE="bindings/${CLOUD_ID}/federatedusers.jsonl"

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
  log "No bindings to delete"
  exit 0
fi

log "Processing ${binding_count} federated user bindings..."
log ""

while IFS= read -r line; do
  user_id=$(jq -r '.id' <<< "$line")
  role_id=$(jq -r '.role_id' <<< "$line")
  cloud_id=$(jq -r '.cloud_id // empty' <<< "$line")
  folder_id=$(jq -r '.folder_id // empty' <<< "$line")
  name_id=$(jq -r '.name_id // empty' <<< "$line")

  if [[ -n "$cloud_id" ]]; then
    log "Deleting cloud binding: ${name_id} (${user_id}) - role: ${role_id}"
    log "  Cloud: ${cloud_id}"

    if yc resource-manager cloud remove-access-binding \
      --id "${cloud_id}" \
      --role "${role_id}" \
      --user-account-id "${user_id}" 2>&1; then
      log "  ✓ Successfully deleted cloud binding"
    else
      log "  ✗ Failed to delete cloud binding"
    fi

  elif [[ -n "$folder_id" ]]; then
    log "Deleting folder binding: ${name_id} (${user_id}) - role: ${role_id}"
    log "  Folder: ${folder_id}"

    if yc resource-manager folder remove-access-binding \
      --id "${folder_id}" \
      --role "${role_id}" \
      --user-account-id "${user_id}" 2>&1; then
      log "  ✓ Successfully deleted folder binding"
    else
      log "  ✗ Failed to delete folder binding"
    fi

  else
    log "WARNING: No cloud_id or folder_id found for binding: ${user_id}"
  fi

  log ""
done < "${INPUT_FILE}"

log "Done."
log "Deleted bindings for ${binding_count} federated users."