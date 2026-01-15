#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./dump_bindings_v2.sh <cloud-id>

CLOUD_ID="${1:-}"

if [[ -z "$CLOUD_ID" ]]; then
  echo "Usage: $0 <cloud-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

ROOT_DIR="bindings/${CLOUD_ID}"
USERACCOUNTS_JSONL="${ROOT_DIR}/useraccounts.jsonl"
FEDERATEDUSERS_JSONL="${ROOT_DIR}/federatedusers.jsonl"
SERVICEACCOUNTS_JSONL="${ROOT_DIR}/serviceaccounts.jsonl"
GROUPS_JSONL="${ROOT_DIR}/groups.jsonl"

mkdir -p "${ROOT_DIR}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Cloud:       ${CLOUD_ID}"
log "Output dir:  ${ROOT_DIR}"
log ""

: > "${USERACCOUNTS_JSONL}"
: > "${FEDERATEDUSERS_JSONL}"
: > "${SERVICEACCOUNTS_JSONL}"
: > "${GROUPS_JSONL}"

process_binding() {
  local binding="$1"
  local subject_type=$(jq -r '.type' <<< "$binding")
  local subject_id=$(jq -r '.id' <<< "$binding")

  case "$subject_type" in
    userAccount)
      if user_data=$(yc iam user-account get "${subject_id}" --format json 2>/dev/null); then
        login=$(jq -r '.yandex_passport_user_account.login // empty' <<< "$user_data")
        echo "$binding" | jq -c --arg login "$login" '. + {login: $login}' >> "${USERACCOUNTS_JSONL}"
      else
        echo "$binding" | jq -c '.' >> "${USERACCOUNTS_JSONL}"
      fi
      ;;
    federatedUser)
      if user_data=$(yc iam user-account get "${subject_id}" --format json 2>/dev/null); then
        name_id=$(jq -r '.saml_user_account.name_id // empty' <<< "$user_data")
        echo "$binding" | jq -c --arg name_id "$name_id" '. + {name_id: $name_id}' >> "${FEDERATEDUSERS_JSONL}"
      else
        echo "$binding" | jq -c '.' >> "${FEDERATEDUSERS_JSONL}"
      fi
      ;;
    serviceAccount)
      echo "$binding" | jq -c '.' >> "${SERVICEACCOUNTS_JSONL}"
      ;;
    group)
      echo "$binding" | jq -c '.' >> "${GROUPS_JSONL}"
      ;;
    *)
      log "    WARNING: Unknown subject type: ${subject_type}"
      ;;
  esac
}

log "Fetching cloud access bindings..."
yc resource-manager cloud list-access-bindings --id "${CLOUD_ID}" --format json | \
  jq -c --arg cloud_id "$CLOUD_ID" '.[] | {type: .subject.type, id: .subject.id, role_id: .role_id, cloud_id: $cloud_id}' | \
  while read -r binding; do
    subject_type=$(jq -r '.type' <<< "$binding")
    subject_id=$(jq -r '.id' <<< "$binding")
    log "  Processing cloud binding: ${subject_type}/${subject_id}"
    process_binding "$binding"
  done

log ""

log "Fetching folders list..."
FOLDER_IDS=$(yc resource-manager folder list --cloud-id "${CLOUD_ID}" --format json | jq -r '.[].id')

if [[ -z "$FOLDER_IDS" ]]; then
  log "No folders found"
else
  log "Processing folder bindings..."

  while IFS= read -r folder_id; do
    log "  Folder: ${folder_id}"
    yc resource-manager folder list-access-bindings --id "${folder_id}" --format json | \
      jq -c --arg folder_id "$folder_id" '.[] | {type: .subject.type, id: .subject.id, role_id: .role_id, folder_id: $folder_id}' | \
      while read -r binding; do
        subject_type=$(jq -r '.type' <<< "$binding")
        subject_id=$(jq -r '.id' <<< "$binding")
        log "    Processing binding: ${subject_type}/${subject_id}"
        process_binding "$binding"
      done
  done <<< "$FOLDER_IDS"
fi

log ""
log "Done."
log "Output files:"
log "  - User accounts:      ${USERACCOUNTS_JSONL}"
log "  - Federated users:    ${FEDERATEDUSERS_JSONL}"
log "  - Service accounts:   ${SERVICEACCOUNTS_JSONL}"
log "  - Groups:             ${GROUPS_JSONL}"