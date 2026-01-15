!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./restore_bindings_groups.sh <cloud-id> <target-organization-id>

CLOUD_ID="${1:-}"
ORGANIZATION_ID="${2:-}"

if [[ -z "$CLOUD_ID" ]] || [[ -z "$ORGANIZATION_ID" ]]; then
  echo "Usage: $0 <cloud-id> <organization-id>" >&2
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

# Function to map group name to target group ID
map_group() {
  local group_name="$1"

  if [[ -z "$group_name" || "$group_name" == "null" ]]; then
    log "    WARNING: Group name is empty"
    return 1
  fi

  # Get target group ID by name
  local target_group_data=$(yc organization-manager group get \
    --name "${group_name}" \
    --organization-id "${ORGANIZATION_ID}" \
    --format json 2>/dev/null)

  if [[ -z "$target_group_data" ]]; then
    log "    WARNING: Could not find group with name: ${group_name}"
    return 1
  fi

  local target_group_id=$(jq -r '.id' <<< "$target_group_data")

  if [[ -z "$target_group_id" || "$target_group_id" == "null" ]]; then
    log "    WARNING: Could not extract ID for group: ${group_name}"
    return 1
  fi

  echo "$target_group_id"
}

log "Cloud ID: ${CLOUD_ID}"
log "Organization ID: ${ORGANIZATION_ID}"
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
  source_group_id=$(jq -r '.id' <<< "$line")
  group_name=$(jq -r '.name // empty' <<< "$line")
  role_id=$(jq -r '.role_id' <<< "$line")
  cloud_id=$(jq -r '.cloud_id // empty' <<< "$line")
  folder_id=$(jq -r '.folder_id // empty' <<< "$line")

  log "Processing binding: ${group_name} (${source_group_id}) - role: ${role_id}"

  # Map source group to target group by name
  if ! target_group_id=$(map_group "$group_name"); then
    log "  ✗ Skipping - could not map group"
    log ""
    continue
  fi

  log "  Mapped to target group: ${target_group_id}"

  if [[ -n "$cloud_id" ]]; then
    log "  Restoring cloud binding: ${cloud_id}"

    if yc resource-manager cloud add-access-binding \
      --id "${cloud_id}" \
      --role "${role_id}" \
      --subject group:"${target_group_id}" 2>&1; then
      log "  ✓ Successfully restored cloud binding"
    else
      log "  ✗ Failed to restore cloud binding"
    fi

  elif [[ -n "$folder_id" ]]; then
    log "  Restoring folder binding: ${folder_id}"

    if yc resource-manager folder add-access-binding \
      --id "${folder_id}" \
      --role "${role_id}" \
      --subject group:"${target_group_id}" 2>&1; then
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
log "Restored bindings for ${binding_count} groups."