#!/bin/sh
# Installs a Lua interpreter on the OpenWrt VM so uhttpd's built-in CGI
# support can run the /api/* endpoints under docker/provision/www/.
#
# IMPORTANT — this script runs on the HOST, not on the VM. It is NOT meant
# to be piped into `ssh ... 'sh -s'`. Why: this VM's br-lan has no WAN
# interface (documented in docker/README.md's "Known limitations" section),
# so the guest has no outbound internet route at all — `opkg update` and
# `opkg install <name>` genuinely cannot reach downloads.openwrt.org from
# inside the VM (confirmed live: both fail with "Unknown package", because
# there is no cached package list to resolve the name against, because
# `opkg update` itself fails with "Network unreachable" for every feed).
# This is true for every opkg package name, not just Lua-related ones.
#
# The packages *do* exist upstream (confirmed against the real 23.05.5
# x86_64 Packages index) — they just can't be fetched from inside the
# guest. So this script fetches the two small .ipk files from the host
# (which does have internet), copies them onto the VM over scp, and runs
# `opkg install` there against the local files — which works fully
# offline once the files are present.
#
# Package choice: `uhttpd-mod-lua` also exists upstream, but it wires Lua
# in as a native uhttpd runtime module (uhttpd.main.lua_prefix / a single
# lua_handler entry point) rather than plain per-file CGI scripts, and it
# does not pull in the `lua` package (the /usr/bin/lua interpreter/CLI) —
# only liblua5.1.5, the shared library. The actual deliverable here
# (docker/provision/www/api/ping, a `#!/usr/bin/lua` CGI script placed
# under uhttpd's existing cgi_prefix) needs the plain `lua` interpreter
# binary, so that's what this script installs, per the plan's own Step 4
# design (a `#!/usr/bin/lua` shebang script, not a mod_lua handler).
#
# lua-cjson was checked and is available upstream too, but is skipped: a
# single hand-built `{"ok":true}` string doesn't need a real JSON library.
# Revisit if a later endpoint needs to encode a real Lua table to JSON.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/01-install-api-packages.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/01-install-api-packages.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_VERSION="23.05.5"
ARCH="x86_64"
BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/packages/${ARCH}/base"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# name:sha256, pinned against the real 23.05.5/x86_64 base feed index so a
# corrupted or unexpectedly-changed download is caught instead of installed.
LIBLUA_FILE="liblua5.1.5_5.1.5-11_x86_64.ipk"
LIBLUA_SHA256="c877a1e82995671ad4c45b638a86ce39e32b4cc1116cc5bef6c6aa7bdf37a78a"
LUA_FILE="lua_5.1.5-11_x86_64.ipk"
LUA_SHA256="9b6c3893ea730262600b5d3e3673fd5a9faae0dc6835d130d964fa349b086314"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

verify_sha256() {
  file="$1"
  expected="$2"
  actual="$(sha256sum "${file}" | cut -d' ' -f1)"
  if [ "${actual}" != "${expected}" ]; then
    echo "ERROR: sha256 mismatch for ${file}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

echo "Downloading Lua packages for OpenWrt ${OPENWRT_VERSION}/${ARCH} (host has internet; the VM does not)..."
curl -fsL -o "${WORK_DIR}/${LIBLUA_FILE}" "${BASE_URL}/${LIBLUA_FILE}"
curl -fsL -o "${WORK_DIR}/${LUA_FILE}" "${BASE_URL}/${LUA_FILE}"

echo "Verifying sha256 checksums..."
verify_sha256 "${WORK_DIR}/${LIBLUA_FILE}" "${LIBLUA_SHA256}"
verify_sha256 "${WORK_DIR}/${LUA_FILE}" "${LUA_SHA256}"

echo "Copying .ipk files onto the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# -O forces the legacy SCP protocol: this VM has no /usr/libexec/sftp-server,
# so a plain `scp` (which defaults to the SFTP protocol on modern OpenSSH
# clients) fails with "ash: /usr/libexec/sftp-server: not found" — confirmed
# live. -O is required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${WORK_DIR}/${LIBLUA_FILE}" "${WORK_DIR}/${LUA_FILE}" \
  "root@${OPENWRT_HOST}:/tmp/"

echo "Installing on the VM via local opkg install (no network needed on the VM side)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "opkg install /tmp/${LIBLUA_FILE} /tmp/${LUA_FILE} && rm -f /tmp/${LIBLUA_FILE} /tmp/${LUA_FILE} && lua -v"

echo "OK: Lua interpreter installed on the VM."
