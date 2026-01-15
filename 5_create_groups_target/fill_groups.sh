#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./fill_groups.sh <organization-id>

ORGANIZATION_ID="${1:-}"

if [[ -z "$ORGANIZATION_ID" ]]; then
  echo "Usage: $0 <organization-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

INPUT_DIR="groups"
SOURCE_USERS="federatedusers/users.json"
TARGET_USERS="federatedusers/target-users.json"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Error: Input directory not found: ${INPUT_DIR}" >&2
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

# Function to map federated user ID from source to target
map_federated_user() {
  local source_id="$1"

  # Get name_id from source users
  local name_id=$(jq -r --arg id "$source_id" '.[] | select(.id == $id) | .name_id' < "$SOURCE_USERS")

  if [[ -z "$name_id" || "$name_id" == "null" ]]; then
    log "    WARNING: Could not find name_id for source user ID: ${source_id}"
    return 1
  fi

  # Get target ID from target users
  local target_id=$(jq -r --arg name_id "$name_id" '.[] | select(.name_id == $name_id) | .id' < "$TARGET_USERS")

  if [[ -z "$target_id" || "$target_id" == "null" ]]; then
    log "    WARNING: Could not find target user ID for name_id: ${name_id}"
    return 1
  fi

  echo "$target_id"
}

log "Organization ID: ${ORGANIZATION_ID}"
log "Input directory: ${INPUT_DIR}"
log ""

group_files=$(find "${INPUT_DIR}" -name "*.json" -type f)

if [[ -z "$group_files" ]]; then
  log "No group files found"
  exit 0
fi

group_count=$(echo "$group_files" | wc -l)
log "Processing ${group_count} groups..."
log ""

echo "$group_files" | while read -r group_file; do
  group_name=$(jq -r '.name' < "$group_file")
  member_count=$(jq '.members | length' < "$group_file")

  log "Processing group: ${group_name}"
  log "  File: ${group_file}"
  log "  Members: ${member_count}"

  if [[ "$member_count" -eq 0 ]]; then
    log "  No members to add"
    log ""
    continue
  fi

  jq -c '.members[]' < "$group_file" | while read -r member; do
    subject_id=$(jq -r '.subject_id' <<< "$member")
    subject_type=$(jq -r '.subject_type' <<< "$member")

    log "  Processing member: ${subject_type}/${subject_id}"

    target_subject_id=""

    case "$subject_type" in
      serviceAccount|userAccount)
        target_subject_id="$subject_id"
        ;;
      federatedUser)
        if target_subject_id=$(map_federated_user "$subject_id"); then
          log "    Mapped to target user: ${target_subject_id}"
        else
          log "    ✗ Skipping - could not map federated user"
          continue
        fi
        ;;
      *)
        log "    WARNING: Unknown subject type: ${subject_type}"
        continue
        ;;
    esac

    if [[ -n "$target_subject_id" ]]; then
      if yc organization-manager group add-members \
        --name "${group_name}" \
        --organization-id "${ORGANIZATION_ID}" \
        --subject-id "${target_subject_id}" 2>&1; then
        log "    ✓ Successfully added member"
      else
        log "    ✗ Failed to add member"
      fi
    fi
  done

  log ""
done

log "Done."