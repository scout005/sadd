#!/bin/sh
# Deploys docker/provision/www/api/blocked-sites (the tracked source of
# truth for the /api/blocked-sites endpoint) onto a running OpenWrt VM as
# /www/cgi-bin/api/blocked-sites and verifies it responds.
#
# No baseline VM state to provision here — same "deploy-and-verify only"
# shape as 12-provision-ssh-key-api.sh's, 14-provision-qos-priority-api.sh's,
# and 16-provision-safe-search-api.sh's own endpoint-deploy halves. This
# endpoint reuses the /etc/dnsmasq.blocklist.d directory
# 09-provision-adblock-api.sh already provisions (Wave 4) as the confdir
# dnsmasq loads from, but never creates that directory itself and never
# touches dhcp.@dnsmasq[0].confdir, blocklist.conf (Ad Blocking's own file),
# or safesearch.conf (Safe Search's own file, Task 1 of this wave) — it only
# ever creates/reads its own separate custom-<domain>.conf files, one per
# added domain, inside that same shared directory (confirmed live,
# docker/facts.md Section 17, that dnsmasq's confdir genuinely loads
# multiple .conf files from one directory simultaneously, so all three
# features' files coexist safely). Since that directory is already
# guaranteed to exist by the time this script runs in the normal
# provisioning order (step 9 before step 17), there is nothing for this
# script to pre-create — but the verify step below never assumes a
# never-used VM, only that the endpoint responds with a valid JSON array.
#
# This is a SEPARATE script from 16-provision-safe-search-api.sh even though
# both endpoints share the same /etc/dnsmasq.blocklist.d directory — every
# prior wave has kept one provisioning script per endpoint, and this wave
# keeps that convention.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/17-provision-blocked-sites-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/17-provision-blocked-sites-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API_SRC_FILE="${SCRIPT_DIR}/www/api/blocked-sites"

echo "=== 17-provision-blocked-sites-api.sh ==="

if [ ! -f "${API_SRC_FILE}" ]; then
  echo "ERROR: ${API_SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
ssh_run "mkdir -p /www/cgi-bin/api"

echo "Copying ${API_SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/blocked-sites ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${API_SRC_FILE}" \
  "${SSH_TARGET}:/www/cgi-bin/api/blocked-sites"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /www/cgi-bin/api/blocked-sites && ls -la /www/cgi-bin/api/blocked-sites"

echo "Verifying: GET http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/blocked-sites responds with a JSON array..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/blocked-sites")"
echo "Response: ${BODY}"

case "${BODY}" in
  '['*']')
    echo "OK: /api/blocked-sites responds with a valid JSON array (not assumed empty — this VM may already have domains added by a prior run)."
    ;;
  *)
    echo "ERROR: expected a JSON array (e.g. [] or [{\"domain\":\"example.com\"}]), got: ${BODY}" >&2
    exit 1
    ;;
esac

echo "=== 17-provision-blocked-sites-api.sh done: /api/blocked-sites deployed and verified. ==="
