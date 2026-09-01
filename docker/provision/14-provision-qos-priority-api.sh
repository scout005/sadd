#!/bin/sh
# Deploys docker/provision/www/api/qos-priority (the tracked source of
# truth for the /api/qos-priority endpoint) onto a running OpenWrt VM as
# /www/cgi-bin/api/qos-priority and verifies it responds.
#
# No baseline VM state to provision here — like 12/13's own /api/ssh-key and
# /api/device-pause endpoints, not like 08-11's "create baseline uci config
# first" shape, and not like 11's own WireGuard SERVER bring-up. This
# endpoint reads/writes plain uci `firewall` rule sections that already
# exist as a concept on a fresh VM (same as device-pause's own rules) — there
# is nothing to pre-create before the endpoint file itself can work, so this
# script is deploy-and-verify only, matching 13-provision-devpause-api.sh's
# own endpoint-deploy half (its cron/sweep half has no counterpart here:
# qos-priority marking rules aren't time-limited, so there's no sweep to
# provision).
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/14-provision-qos-priority-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/14-provision-qos-priority-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_SRC_FILE="${SCRIPT_DIR}/www/api/qos-priority"

echo "=== 14-provision-qos-priority-api.sh ==="

if [ ! -f "${API_SRC_FILE}" ]; then
  echo "ERROR: ${API_SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
ssh_run "mkdir -p /www/cgi-bin/api"

echo "Copying ${API_SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/qos-priority ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${API_SRC_FILE}" \
  "${SSH_TARGET}:/www/cgi-bin/api/qos-priority"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /www/cgi-bin/api/qos-priority && ls -la /www/cgi-bin/api/qos-priority"

echo "Verifying: GET http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/qos-priority responds with a JSON array..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/qos-priority")"
echo "Response: ${BODY}"

case "${BODY}" in
  \[*\])
    echo "OK: /api/qos-priority responds with a JSON array."
    ;;
  *)
    echo "ERROR: expected a JSON array (e.g. [] or [{...}]), got: ${BODY}" >&2
    exit 1
    ;;
esac

echo "=== 14-provision-qos-priority-api.sh done: /api/qos-priority deployed and verified. ==="
