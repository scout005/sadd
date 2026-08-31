#!/bin/sh
# Copies sadd-website.html (repo root) onto a running OpenWrt VM as
# /www/index.html, so the VM's own uhttpd serves the frontend prototype at
# http://<host>:<port>/ instead of OpenWrt's stock landing page.
#
# Target: /www/index.html. `uci show uhttpd` on this VM confirms
# `uhttpd.main.home='/www'` (the docroot) — so a file placed directly under
# /www/, named index.html, becomes uhttpd's default document for `/`. This
# sits alongside the existing /www/cgi-bin/ directory (untouched by this
# script) and overwrites OpenWrt's stock /www/index.html (the one that
# redirects to cgi-bin/luci/) — intentional and acceptable for this
# dev/test VM; LuCI itself is unaffected and still reachable directly at
# /cgi-bin/luci/, just no longer the auto-landing page at /.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/03-copy-frontend.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/03-copy-frontend.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/../../sadd-website.html"

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/index.html ..."
# -O forces the legacy SCP protocol: this VM has no /usr/libexec/sftp-server,
# so a plain `scp` (which defaults to SFTP on modern OpenSSH clients) fails
# with "ash: /usr/libexec/sftp-server: not found" — confirmed live in
# docker/provision/01-install-api-packages.sh and 02-copy-www.sh; -O is
# required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/index.html"

echo "OK: sadd-website.html copied onto the VM as /www/index.html."
