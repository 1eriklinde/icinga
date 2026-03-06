#!/usr/bin/env bash
# Icinga2 host notification — sends a ticket to HaloITSM
# Called by Icinga2 notification command; sources config/secrets via lib.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ─── Parse Icinga2 notification macro arguments ───────────────────────────────
HOST_NAME=""
HOST_STATE=""
HOST_OUTPUT=""
TYPE=""

while getopts "H:l:m:t:" option; do
  case "${option}" in
    H) HOST_NAME="${OPTARG}" ;;
    l) HOST_STATE="${OPTARG}" ;;
    m) HOST_OUTPUT="${OPTARG}" ;;
    t) TYPE="${OPTARG}" ;;
    *) ;;
  esac
done

# ─── Validate required config ─────────────────────────────────────────────────
: "${HALO_URL:?HALO_URL is not set in config.env}"
: "${HALO_USER:?HALO_USER is not set in secrets.env}"
: "${HALO_PASS:?HALO_PASS is not set in secrets.env}"
: "${ICINGA2_WEB_URL:?ICINGA2_WEB_URL is not set in config.env}"

# ─── Jitter to avoid thundering-herd on mass state changes ───────────────────
MIN_JITTER_MS=200
MAX_JITTER_MS=60000
_jitter_ms=$(( MIN_JITTER_MS + RANDOM % (MAX_JITTER_MS - MIN_JITTER_MS + 1) ))
_jitter_sec=$(awk "BEGIN {printf \"%.3f\", ${_jitter_ms}/1000}")
sleep "${_jitter_sec}"

# ─── Build JSON payload ───────────────────────────────────────────────────────
HOST_URL="${ICINGA2_WEB_URL}/icingadb/host?name=${HOST_NAME}"

JSON_STRING="$(cat <<EOF
{
  "host_id": "${HOST_NAME}",
  "host_name": "${HOST_NAME}",
  "host_state": "${HOST_STATE}",
  "host_output": "${HOST_OUTPUT}",
  "host_text": "Host: ${HOST_NAME}\r\n<h2>Host status: ${HOST_STATE}\n\n</h2><h4>Host <a href=\"${HOST_URL}\" target=\"_blank\">${HOST_NAME}</a> is ${HOST_STATE}\r\n</h4><h4>Output info: ${HOST_OUTPUT}\r\n</h4><h4>Host: ${HOST_NAME} Incident status</h4>",
  "type": "${TYPE}"
}
EOF
)"

# ─── Send notification ────────────────────────────────────────────────────────
echo "${JSON_STRING}" | logger -t halo-host-notification-log-1
echo "Sending host notification ${HOST_NAME} is ${HOST_STATE} Output info: ${HOST_OUTPUT}" \
    | logger -t halo-host-notification-log-2

SEND=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "${HALO_USER}:${HALO_PASS}" \
    -d "${JSON_STRING}" \
    "${HALO_URL}")

echo "Sent host notification for ${HOST_NAME}: ${SEND}" \
    | logger -t halo-host-notification-log-3
