#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./restore_bindings.sh <cloud-id>

CLOUD_ID="${1:-}"

if [[ -z "$CLOUD_ID" ]]; then
  echo "Usage: $0 <cloud-id>" >&2
  exit 1
fi

command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

INPUT_FILE="bindings/${CLOUD_ID}/federatedusers.jsonl"
SOURCE_USERS="federatedusers/users.json"
TARGET_USERS="federatedusers/target-users.json"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: Input file not found: ${INPUT_FILE}" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_USERS" ]]; then
  echo "Error: Source users file not found: ${SOURCE_USERS}" >&2
  exit 1
fi

if [[ ! -f "$TARGET_USERS" ]]; then
  echo "Error: Target users file not found: ${TARGET_USERS}" >&2
  exit 1
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

map_federated_user() {
  local source_id="$1"

  local name_id=$(jq -r --arg id "$source_id" '.[] | select(.id == $id) | .name_id' < "$SOURCE_USERS")

  if [[ -z "$name_id" || "$name_id" == "null" ]]; then
    log "    WARNING: Could not find name_id for source user ID: ${source_id}"
    return 1
  fi

  local target_id=$(jq -r --arg name_id "$name_id" '.[] | select(.name_id == $name_id) | .id' < "$TARGET_USERS")

  if [[ -z "$target_id" || "$target_id" == "null" ]]; then
    log "    WARNING: Could not find target user ID for name_id: ${name_id}"
    return 1
  fi

  echo "$target_id"
}

log "Cloud ID: ${CLOUD_ID}"
log "Input file: ${INPUT_FILE}"
log ""

binding_count=$(wc -l < "${INPUT_FILE}" | tr -d ' ')

if [[ "$binding_count" -eq 0 ]]; then
  log "No bindings to restore"
  exit 0
fi

log "Restoring ${binding_count} federated user bindings..."
log ""

while IFS= read -r line; do
  source_user_id=$(jq -r '.id' <<< "$line")
  role_id=$(jq -r '.role_id' <<< "$line")
  cloud_id=$(jq -r '.cloud_id // empty' <<< "$line")
  folder_id=$(jq -r '.folder_id // empty' <<< "$line")
  name_id=$(jq -r '.name_id // empty' <<< "$line")

  log "Processing binding: ${name_id} (${source_user_id}) - role: ${role_id}"

  if ! target_user_id=$(map_federated_user "$source_user_id"); then
    log "  ✗ Skipping - could not map user"
    log ""
    continue
  fi

  log "  Mapped to target user: ${target_user_id}"

  if [[ -n "$cloud_id" ]]; then
    log "  Restoring cloud binding: ${cloud_id}"

    if yc resource-manager cloud add-access-binding \
      --id "${cloud_id}" \
      --role "${role_id}" \
      --user-account-id "${target_user_id}" 2>&1; then
      log "  ✓ Successfully restored cloud binding"
    else
      log "  ✗ Failed to restore cloud binding"
    fi

  elif [[ -n "$folder_id" ]]; then
    log "  Restoring folder binding: ${folder_id}"

    if yc resource-manager folder add-access-binding \
      --id "${folder_id}" \
      --role "${role_id}" \
      --user-account-id "${target_user_id}" 2>&1; then
      log "  ✓ Successfully restored folder binding"
    else
      log "  ✗ Failed to restore folder binding"
    fi

  else
    log "  WARNING: No cloud_id or folder_id found for binding"
  fi

  log ""
done < "${INPUT_FILE}"

log "Done."
log "Restored bindings for ${binding_count} federated users."