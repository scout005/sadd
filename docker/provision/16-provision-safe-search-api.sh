#!/bin/sh
# Deploys docker/provision/www/api/safe-search (the tracked source of truth
# for the /api/safe-search endpoint) onto a running OpenWrt VM as
# /www/cgi-bin/api/safe-search and verifies it responds.
#
# No baseline VM state to provision here — same "deploy-and-verify only"
# shape as 12-provision-ssh-key-api.sh's and 14-provision-qos-priority-api.sh's
# own endpoint-deploy halves, not like 08-11's "create baseline uci config
# first" shape. This endpoint reuses the /etc/dnsmasq.blocklist.d directory
# 09-provision-adblock-api.sh already provisions (Wave 4) as the confdir
# dnsmasq loads from, but never creates that directory itself and never
# touches dhcp.@dnsmasq[0].confdir or blocklist.conf — it only ever
# creates/reads/removes its own separate file, safesearch.conf, inside that
# same shared directory (confirmed live, docker/facts.md Section 17, that
# dnsmasq's confdir genuinely loads multiple .conf files from one directory
# simultaneously, so both features' files coexist safely). Since that
# directory is already guaranteed to exist by the time this script runs in
# the normal provisioning order (step 9 before step 16), there is nothing
# for this script to pre-create — but the verify step below never assumes a
# clean/never-toggled VM, only that the endpoint responds with valid JSON.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/16-provision-safe-search-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/16-provision-safe-search-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_SRC_FILE="${SCRIPT_DIR}/www/api/safe-search"

echo "=== 16-provision-safe-search-api.sh ==="

if [ ! -f "${API_SRC_FILE}" ]; then
  echo "ERROR: ${API_SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
ssh_run "mkdir -p /www/cgi-bin/api"

echo "Copying ${API_SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/safe-search ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${API_SRC_FILE}" \
  "${SSH_TARGET}:/www/cgi-bin/api/safe-search"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /www/cgi-bin/api/safe-search && ls -la /www/cgi-bin/api/safe-search"

echo "Verifying: GET http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/safe-search responds with valid {\"enabled\":<bool>} JSON..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/safe-search")"
echo "Response: ${BODY}"

case "${BODY}" in
  '{"enabled":true}'|'{"enabled":false}')
    echo "OK: /api/safe-search responds with valid enabled state (not assumed clean — this VM may already have been toggled by a prior run)."
    ;;
  *)
    echo "ERROR: expected {\"enabled\":true} or {\"enabled\":false}, got: ${BODY}" >&2
    exit 1
    ;;
esac

echo "=== 16-provision-safe-search-api.sh done: /api/safe-search deployed and verified. ==="
