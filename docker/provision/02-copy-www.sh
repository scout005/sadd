#!/bin/sh
# Copies docker/provision/www/ (the tracked source of truth for the VM's
# /api/* endpoints) onto a running OpenWrt VM, and makes any CGI scripts
# executable afterward.
#
# Target directory: /www/cgi-bin/, NOT /www/. `uci show uhttpd` on this VM
# confirms `uhttpd.main.home='/www'` (the docroot) and
# `uhttpd.main.cgi_prefix='/cgi-bin'` (uhttpd's built-in CGI dispatch
# prefix under that docroot) — so a CGI script must live under
# /www/cgi-bin/, not directly under /www/. docker/provision/www/ mirrors
# the *contents* of that cgi-bin directory (currently just api/ping), so
# it is copied to /www/cgi-bin/ specifically, confirmed working live:
# `curl -s http://localhost:8081/cgi-bin/api/ping` → {"ok":true}.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/02-copy-www.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/02-copy-www.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/www"

if [ ! -d "${SRC_DIR}" ]; then
  echo "ERROR: ${SRC_DIR} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin"

echo "Copying ${SRC_DIR}/* -> root@${OPENWRT_HOST}:/www/cgi-bin/ ..."
# -O forces the legacy SCP protocol: this VM has no /usr/libexec/sftp-server,
# so a plain `scp` (which defaults to SFTP on modern OpenSSH clients) fails
# with "ash: /usr/libexec/sftp-server: not found" — confirmed live.
# `scp -r SRC_DIR/. DEST/` ("copy the *contents* of SRC_DIR") errors out
# against this VM's legacy scp with "unexpected filename: ." — confirmed
# live — so each top-level entry under www/ is copied individually
# instead (currently just "api", but this loop picks up future additions
# automatically).
for entry in "${SRC_DIR}"/*; do
  # shellcheck disable=SC2086
  scp -O -r ${SSH_OPTS} -P "${OPENWRT_PORT}" \
    "${entry}" \
    "root@${OPENWRT_HOST}:/www/cgi-bin/"
done

echo "Making CGI scripts under /www/cgi-bin/api executable..."
# Explicit chmod is required, not just defensive: this repo currently has
# core.filemode=false (confirmed via `git config core.filemode`), so git
# does not track/restore the executable bit on checkout — a fresh clone's
# copy of docker/provision/www/api/ping is not guaranteed to be +x on disk
# regardless of what scp does with it, so it must be set here every time.
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "find /www/cgi-bin/api -type f -exec chmod +x {} + && ls -la /www/cgi-bin/api"

echo "OK: docker/provision/www/ copied onto the VM."
