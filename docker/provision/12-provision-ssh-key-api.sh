#!/bin/sh
# Deploys docker/provision/www/api/ssh-key (the tracked source of truth for
# the /api/ssh-key endpoint) onto a running OpenWrt VM and verifies GET is
# correctly rejected with 405 (this endpoint is POST-only — a real rotation
# is NOT triggered by this script, since a plain GET-based deploy/verify
# check shouldn't itself mutate the VM's real SSH host keys).
#
# Why a dedicated step instead of relying only on 02-copy-www.sh: same
# rationale as 04-provision-devices-api.sh/05-provision-firewall-api.sh/
# 06-provision-system-info-api.sh/07-provision-logs-api.sh — 02 already
# copies everything under docker/provision/www/ generically (this file
# included), but this step exists as its own numbered, documented step
# anyway so the README's Provisioning section has one explicit, named step
# per backend capability added, and so it's self-contained/idempotent:
# running it alone (re-copy + chmod + curl-verify) is enough to (re)deploy
# just this endpoint onto an already-provisioned VM, without needing to
# re-run 02.
#
# Unlike 08-11, this endpoint needs NO baseline VM state to provision —
# dropbear is already running on every fresh OpenWrt boot with nothing new
# to create first (see docker/facts.md Section 14: the whole mechanism is
# just "delete the two host key files, restart dropbear, it regenerates
# them"), so this script's shape matches 06/07's "stateless endpoint,
# nothing to provision beyond the file itself" pattern, not 08's "create
# baseline VM state" one. No new opkg package is needed either — dropbear
# and dropbearkey are already present on a stock OpenWrt image.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/12-provision-ssh-key-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/12-provision-ssh-key-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/www/api/ssh-key"

echo "=== 12-provision-ssh-key-api.sh ==="

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin/api"

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/ssh-key ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/cgi-bin/api/ssh-key"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "chmod +x /www/cgi-bin/api/ssh-key && ls -la /www/cgi-bin/api/ssh-key"

echo "Verifying: GET http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/ssh-key is rejected with 405 (this endpoint is POST-only; a GET-based deploy check must never itself rotate the VM's real SSH host keys)..."
STATUS="$(curl -s -o /dev/null -w '%{http_code}' "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/ssh-key")"
BODY="$(curl -s "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/ssh-key")"
echo "HTTP ${STATUS}: ${BODY}"

if [ "${STATUS}" = "405" ]; then
  echo "OK: /api/ssh-key correctly rejected GET with 405."
else
  echo "ERROR: expected HTTP 405 for GET, got ${STATUS}." >&2
  exit 1
fi

echo "=== 12-provision-ssh-key-api.sh done ==="
