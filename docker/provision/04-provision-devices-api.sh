#!/bin/sh
# Deploys docker/provision/www/api/devices (the tracked source of truth for
# the /api/devices endpoint) onto a running OpenWrt VM and verifies it
# responds with well-formed JSON.
#
# Why a dedicated step instead of relying only on 02-copy-www.sh: 02 already
# copies everything under docker/provision/www/ generically (including this
# file, by design — see 02's own header comment: "this loop picks up future
# additions automatically"), so on a fresh VM provisioned 01 -> 02 -> 03 in
# order, api/devices is already in place by the time 02 finishes. This step
# exists as its own numbered, documented step anyway so:
#   - the README's Provisioning section has one explicit, named step per
#     backend capability added (mirroring how 01 = Lua runtime, 02 = the
#     CGI scripts generically, 03 = the frontend), rather than silently
#     folding new endpoints into 02's existing wording;
#   - it's self-contained and idempotent: running it alone (re-copy +
#     chmod + curl-verify) is enough to (re)deploy just this endpoint onto
#     an already-provisioned VM, without needing to re-run 02.
#
# No new opkg package is needed for this endpoint (see the header comment
# in docker/provision/www/api/devices for why lua-cjson wasn't installed:
# the endpoint hand-builds its JSON with a defensive escaper instead), so
# unlike 01-install-api-packages.sh, this script has no host-download step.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/04-provision-devices-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/04-provision-devices-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/www/api/devices"

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin/api"

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/devices ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/cgi-bin/api/devices"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "chmod +x /www/cgi-bin/api/devices && ls -la /www/cgi-bin/api/devices"

echo "Verifying: curl http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/devices ..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/devices")"
echo "${BODY}"

case "${BODY}" in
  \[*\])
    echo "OK: /api/devices responded with what looks like a JSON array."
    ;;
  *)
    echo "ERROR: response does not look like a JSON array." >&2
    exit 1
    ;;
esac

echo "OK: docker/provision/www/api/devices deployed and verified."
