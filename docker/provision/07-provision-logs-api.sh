#!/bin/sh
# Deploys docker/provision/www/api/logs (the tracked source of truth for
# the /api/logs endpoint) onto a running OpenWrt VM and verifies it
# responds with a well-formed JSON array.
#
# Why a dedicated step instead of relying only on 02-copy-www.sh: same
# rationale as 04-provision-devices-api.sh/05-provision-firewall-api.sh/
# 06-provision-system-info-api.sh — 02 already copies everything under
# docker/provision/www/ generically (this file included), but this step
# exists as its own numbered, documented step anyway so the README's
# Provisioning section has one explicit, named step per backend capability
# added, and so it's self-contained/idempotent: running it alone (re-copy +
# chmod + curl-verify) is enough to (re)deploy just this endpoint onto an
# already-provisioned VM, without needing to re-run 02.
#
# No new opkg package is needed for this endpoint (see the header comment in
# docker/provision/www/api/logs for why lua-cjson wasn't installed and why a
# real log-format parser wasn't written either: it shells out to `logread
# -l 30` — already present on a stock OpenWrt image — and splits each line's
# known-shaped asctime datetime prefix from its message with a single
# anchored string pattern, then hand-builds its own JSON response with a
# defensive escaper), so unlike 01-install-api-packages.sh, this script has
# no host-download step.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/07-provision-logs-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/07-provision-logs-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/www/api/logs"

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin/api"

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/logs ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/cgi-bin/api/logs"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "chmod +x /www/cgi-bin/api/logs && ls -la /www/cgi-bin/api/logs"

echo "Verifying: curl http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/logs ..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/logs")"
echo "${BODY}"

case "${BODY}" in
  \[*\])
    echo "OK: /api/logs responded with what looks like a JSON array."
    ;;
  *)
    echo "ERROR: response does not look like a JSON array." >&2
    exit 1
    ;;
esac

echo "OK: docker/provision/www/api/logs deployed and verified."
