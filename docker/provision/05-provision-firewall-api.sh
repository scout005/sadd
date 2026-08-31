#!/bin/sh
# Deploys docker/provision/www/api/firewall-rules (the tracked source of
# truth for the /api/firewall-rules endpoint) onto a running OpenWrt VM and
# verifies it responds with well-formed JSON.
#
# Same rationale as 04-provision-devices-api.sh for being its own
# dedicated, numbered step even though 02-copy-www.sh's generic loop would
# already pick this file up: one explicit step per backend capability, and
# a script that's independently re-runnable against an already-provisioned
# VM without needing to re-run 02.
#
# No new opkg package is needed for this endpoint either — see the header
# comment in docker/provision/www/api/firewall-rules for why (hand-built/
# hand-parsed JSON, no lua-cjson), so this script has no host-download step.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/05-provision-firewall-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/05-provision-firewall-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/www/api/firewall-rules"

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin/api"

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/firewall-rules ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03/04; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/cgi-bin/api/firewall-rules"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "chmod +x /www/cgi-bin/api/firewall-rules && ls -la /www/cgi-bin/api/firewall-rules"

echo "Verifying: curl http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/firewall-rules ..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/firewall-rules")"
echo "${BODY}"

case "${BODY}" in
  \[*\])
    echo "OK: /api/firewall-rules responded with what looks like a JSON array."
    ;;
  *)
    echo "ERROR: response does not look like a JSON array." >&2
    exit 1
    ;;
esac

echo "OK: docker/provision/www/api/firewall-rules deployed and verified."
