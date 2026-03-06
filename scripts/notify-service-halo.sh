#!/usr/bin/env bash
# Icinga2 service notification — sends a ticket to HaloITSM
# Called by Icinga2 notification command; sources config/secrets via lib.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ─── Parse Icinga2 notification macro arguments ───────────────────────────────
HOST_NAME=""
TYPE=""
SERVICE_NAME=""
SERVICE_STATE=""
SERVICE_OUTPUT=""

while getopts "H:t:v:w:x:" option; do
  case "${option}" in
    H) HOST_NAME="${OPTARG}" ;;
    t) TYPE="${OPTARG}" ;;
    v) SERVICE_NAME="${OPTARG}" ;;
    w) SERVICE_STATE="${OPTARG}" ;;
    x) SERVICE_OUTPUT="${OPTARG}" ;;
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
HOST_SERVICES_URL="${ICINGA2_WEB_URL}/icingadb/host/services?name=${HOST_NAME}"

JSON_STRING="$(cat <<EOF
{
  "service_id": "${HOST_NAME}-${SERVICE_NAME}",
  "service_name": "${SERVICE_NAME}",
  "service_state": "${SERVICE_STATE}",
  "service_output": "${SERVICE_OUTPUT}",
  "service_text": "Host: ${HOST_NAME}\r\n<h2>Service status: ${SERVICE_STATE}\r\n</h2><h4>Service <a href=\"${HOST_SERVICES_URL}\" target=\"_blank\">${SERVICE_NAME}</a> is ${SERVICE_STATE}\r\n</h4><h4>Output info: ${SERVICE_OUTPUT}\r\n</h4><h4>Host: ${HOST_NAME} Incident status</h4>",
  "type": "${TYPE}"
}
EOF
)"

# ─── Send notification ────────────────────────────────────────────────────────
echo "${JSON_STRING}" | logger -t halo-service-notification-log-1
echo "Sending service notification ${SERVICE_NAME} on ${HOST_NAME} is ${SERVICE_STATE} Output info: ${SERVICE_OUTPUT}" \
    | logger -t halo-service-notification-log-2

SEND=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "${HALO_USER}:${HALO_PASS}" \
    -d "${JSON_STRING}" \
    "${HALO_URL}")

echo "Sent service notification for ${SERVICE_NAME} on ${HOST_NAME}: ${SEND}" \
    | logger -t halo-service-notification-log-3
