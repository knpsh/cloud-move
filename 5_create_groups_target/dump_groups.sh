
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./dump_groups.sh <target-organization-id>

ORGANIZATION_ID="${1:-}"

if [[ -z "$ORGANIZATION_ID" ]]; then
  echo "Usage: $0 <organization-id>" >&2
  exit 1
fi

# Requirements: yc, jq
command -v yc >/dev/null 2>&1 || { echo "yc CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (install jq)" >&2; exit 1; }

ROOT_DIR="groups"

mkdir -p "${ROOT_DIR}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Organization: ${ORGANIZATION_ID}"
log "Output dir:   ${ROOT_DIR}"
log ""

log "Fetching groups list..."
YC_GROUPS=$(yc organization-manager group list --organization-id "${ORGANIZATION_ID}" --format json)

if [[ $(echo "$YC_GROUPS" | jq 'length') -eq 0 ]]; then
  log "No groups found"
  exit 0
fi

echo "$YC_GROUPS" | jq -c '.[]' | while read -r group; do
  group_id=$(jq -r '.id' <<< "$group")
  group_name=$(jq -r '.name' <<< "$group")

  log "Processing group: ${group_name} (${group_id})"

  # Fetch group members
  members=$(yc organization-manager group list-members "${group_id}" --format json 2>/dev/null || echo "[]")

  # Create output JSON with name and members
  jq -n \
    --arg name "$group_name" \
    --argjson members "$members" \
    '{name: $name, members: $members}' > "${ROOT_DIR}/${group_id}.json"

  log "  Saved to: ${ROOT_DIR}/${group_id}.json"
done

log ""
log "Done."
log "Output directory: ${ROOT_DIR}"