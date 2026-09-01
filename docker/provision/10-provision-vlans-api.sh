#!/bin/sh
# Creates the 4 missing baseline VLAN `uci network` interface sections on the
# VM over SSH (this VM already has `network.lan` = 192.168.1.0/24 from a
# stock boot — see docker/facts.md Section 3 — so only the other 4 demo
# VLANs shown in sadd-website.html's screens['advnetwork'] need creating:
# Kids/192.168.2.0/24, IoT-Smart-Home/192.168.3.0/24, Guests/192.168.4.0/24,
# Quarantine/192.168.5.0/24 — confirmed by reading the actual HTML, not
# assumed), using the exact confirmed-live sequence from docker/facts.md
# Section 12 (unmodified): `proto=static`, `device=br-lan.<N>` for a
# distinct 802.1q VLAN id per network, matching `ipaddr`/`netmask`. Then
# deploys docker/provision/www/api/vlans (the tracked source of truth for
# the /api/vlans endpoint) onto the VM and verifies it responds with real
# JSON.
#
# VLAN id mapping chosen (matches each subnet's third octet, for
# readability/debuggability — e.g. `br-lan.2` carries 192.168.2.0/24):
#   kids       -> id 2 -> device br-lan.2 -> 192.168.2.1/255.255.255.0
#   iot        -> id 3 -> device br-lan.3 -> 192.168.3.1/255.255.255.0
#   guests     -> id 4 -> device br-lan.4 -> 192.168.4.1/255.255.255.0
#   quarantine -> id 5 -> device br-lan.5 -> 192.168.5.1/255.255.255.0
# (`network.lan` already owns `br-lan` itself / 192.168.1.0/24 — untouched.)
#
# Like 08/09 (and unlike 04-07, which only deploy a stateless endpoint
# file), this script also creates real, persisted VM state — real,
# kernel-verifiable 802.1q VLAN sub-interfaces, not just inert `uci`
# strings (confirmed live in docker/facts.md Section 12: `ip link show`
# after `network reload` shows a genuine `UP` `br-lan.2@br-lan` interface).
#
# Idempotent AND self-healing, same two-layer verification discipline as
# 08/09, extended with a SECOND layer 08/09 didn't need (since neither of
# them creates a real kernel-level interface, just `uci`/config-file state):
#   1. uci-completeness: each section is checked for every expected field
#      via `uci get network.<name>.<option>` (not mere existence) — a
#      section left behind incomplete by a prior run that died partway
#      through is reverted (`uci revert network`) and recreated, verified
#      again, and only committed once complete (one retry, then a loud
#      failure with a revert — never a silent partial commit), same as
#      08-provision-wifi-api.sh / 09-provision-adblock-api.sh.
#   2. kernel-liveness: after `/etc/init.d/network reload`, each device
#      (`br-lan.<N>`) is checked to genuinely show the `UP` flag in
#      `ip link show <device>` — a uci section can read back "correct" and
#      still not have a live kernel interface behind it (reload raced,
#      failed silently, etc.), so this is checked independently and is NOT
#      skipped just because layer 1 passed. If a device isn't up, the
#      section is deleted+recommitted, recreated, reloaded, and rechecked
#      once; still-not-up after that retry is a loud failure, not a silent
#      "probably fine".
#
# Re-running this script against an already-configured VM is a no-op for
# config creation (uci completeness check passes -> skip straight to the
# kernel-liveness check, which also passes since the interfaces are already
# up from the prior run -> no reload needed -> straight to endpoint
# redeploy) — confirmed live by running it twice in a row and diffing
# `uci show network` / `ip link show` (identical both times, no duplicate
# sections, no errors).
#
# ip link vs. ubus for "is this interface really up" (see also
# docker/provision/www/api/vlans's own header comment, which makes the same
# choice for the GET endpoint): both were checked live against this VM.
# `ubus call network.interface.<name> status` returns a real `"up": true`
# boolean, but nested inside a much larger multi-line JSON object — parsing
# that correctly would need real JSON parsing, and this VM has no
# lua-cjson (no outbound internet route to opkg-install it — see
# docker/provision/www/api/devices's header comment). `ip link show
# <device>` instead prints one plain-text line whose `<...>` flag list
# either contains `UP` or doesn't — confirmed live
# (`3: br-lan: <BROADCAST,MULTICAST,UP,LOWER_UP> ... state UP`), trivially
# and robustly greppable with a plain shell case/grep, no parser needed.
# Chosen for that reason: same real signal, far simpler to check correctly
# in a POSIX shell context (this script) and in Lua without a JSON library
# (the endpoint).
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/10-provision-vlans-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/10-provision-vlans-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/www/api/vlans"

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring the 4 baseline VLAN interfaces exist on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" 'sh -s' <<'REMOTE_SCRIPT'
set -e

# === Layer 1: uci-completeness (mirrors 08/09's established pattern) ===
# Each vlan_verify_* function reads back every option the matching
# vlan_create_* function is supposed to have set and compares it against
# the expected value — a bare `uci get network.<name>` success only proves
# the section exists, not that it's complete.

vlan_verify_kids() {
  [ "$(uci -q get network.kids.proto 2>/dev/null)" = "static" ] || return 1
  [ "$(uci -q get network.kids.device 2>/dev/null)" = "br-lan.2" ] || return 1
  [ "$(uci -q get network.kids.ipaddr 2>/dev/null)" = "192.168.2.1" ] || return 1
  [ "$(uci -q get network.kids.netmask 2>/dev/null)" = "255.255.255.0" ] || return 1
  return 0
}
vlan_create_kids() {
  uci set network.kids=interface
  uci set network.kids.proto=static
  uci set network.kids.device=br-lan.2
  uci set network.kids.ipaddr=192.168.2.1
  uci set network.kids.netmask=255.255.255.0
}

vlan_verify_iot() {
  [ "$(uci -q get network.iot.proto 2>/dev/null)" = "static" ] || return 1
  [ "$(uci -q get network.iot.device 2>/dev/null)" = "br-lan.3" ] || return 1
  [ "$(uci -q get network.iot.ipaddr 2>/dev/null)" = "192.168.3.1" ] || return 1
  [ "$(uci -q get network.iot.netmask 2>/dev/null)" = "255.255.255.0" ] || return 1
  return 0
}
vlan_create_iot() {
  uci set network.iot=interface
  uci set network.iot.proto=static
  uci set network.iot.device=br-lan.3
  uci set network.iot.ipaddr=192.168.3.1
  uci set network.iot.netmask=255.255.255.0
}

vlan_verify_guests() {
  [ "$(uci -q get network.guests.proto 2>/dev/null)" = "static" ] || return 1
  [ "$(uci -q get network.guests.device 2>/dev/null)" = "br-lan.4" ] || return 1
  [ "$(uci -q get network.guests.ipaddr 2>/dev/null)" = "192.168.4.1" ] || return 1
  [ "$(uci -q get network.guests.netmask 2>/dev/null)" = "255.255.255.0" ] || return 1
  return 0
}
vlan_create_guests() {
  uci set network.guests=interface
  uci set network.guests.proto=static
  uci set network.guests.device=br-lan.4
  uci set network.guests.ipaddr=192.168.4.1
  uci set network.guests.netmask=255.255.255.0
}

vlan_verify_quarantine() {
  [ "$(uci -q get network.quarantine.proto 2>/dev/null)" = "static" ] || return 1
  [ "$(uci -q get network.quarantine.device 2>/dev/null)" = "br-lan.5" ] || return 1
  [ "$(uci -q get network.quarantine.ipaddr 2>/dev/null)" = "192.168.5.1" ] || return 1
  [ "$(uci -q get network.quarantine.netmask 2>/dev/null)" = "255.255.255.0" ] || return 1
  return 0
}
vlan_create_quarantine() {
  uci set network.quarantine=interface
  uci set network.quarantine.proto=static
  uci set network.quarantine.device=br-lan.5
  uci set network.quarantine.ipaddr=192.168.5.1
  uci set network.quarantine.netmask=255.255.255.0
}

# $1 = section name, $2 = verify function, $3 = create function.
# Commits per-section (not once at the end), same rationale as
# 08-provision-wifi-api.sh: reverting to fix one broken section can never
# undo an earlier section that already verified and committed successfully.
# Sets the global CONFIG_CHANGED=1 whenever a section actually had to be
# (re)created, so the caller knows whether a `network reload` is needed.
CONFIG_CHANGED=0
ensure_network_section() {
  section="$1"; verify_fn="$2"; create_fn="$3"

  if "$verify_fn"; then
    echo "network.${section} already exists and is complete, skipping (idempotent)."
    return 0
  fi

  if uci get "network.${section}" >/dev/null 2>&1; then
    echo "network.${section} exists but is INCOMPLETE (likely left behind by a prior run that failed partway through) - reverting uncommitted network changes and recreating..."
  else
    echo "Creating network.${section}..."
  fi
  uci revert network
  "$create_fn" || true

  if "$verify_fn"; then
    uci commit network
    CONFIG_CHANGED=1
    echo "network.${section} created, verified, and committed."
    return 0
  fi

  echo "network.${section} did not verify after the first attempt - reverting and retrying once..." >&2
  uci revert network
  "$create_fn" || true

  if "$verify_fn"; then
    uci commit network
    CONFIG_CHANGED=1
    echo "network.${section} created, verified, and committed on retry."
    return 0
  fi

  echo "ERROR: failed to create a complete network.${section} section after retry. Reverting uncommitted changes and aborting." >&2
  uci revert network
  exit 1
}

ensure_network_section kids vlan_verify_kids vlan_create_kids
ensure_network_section iot vlan_verify_iot vlan_create_iot
ensure_network_section guests vlan_verify_guests vlan_create_guests
ensure_network_section quarantine vlan_verify_quarantine vlan_create_quarantine

echo "uci network config present and verified. Current state:"
uci show network

if [ "${CONFIG_CHANGED}" = "1" ]; then
  echo "Reloading network to bring up the new VLAN sub-interfaces..."
  /etc/init.d/network reload
  sleep 3
fi

# === Layer 2: kernel-liveness (independent of layer 1 - a uci section can
# read back "correct" and still have no live kernel interface behind it if
# the reload raced or silently failed) ===
# Checks the `UP` flag in `ip link show <device>`'s flag list (see header
# comment for why this was chosen over parsing ubus's nested JSON).
device_is_up() {
  dev="$1"
  link_out="$(ip link show "${dev}" 2>/dev/null)" || return 1
  # Extract just the comma-separated flag list between '<' and '>' on the
  # first line (e.g. "BROADCAST,MULTICAST,UP,LOWER_UP") and check it
  # contains the exact "UP" flag token, not just any substring match
  # against the whole line (which would also match "LOWER_UP" harmlessly,
  # but being precise here costs nothing).
  flags="$(printf '%s\n' "${link_out}" | head -n1 | sed -n 's/.*<\(.*\)>.*/\1/p')"
  case ",${flags}," in
    *,UP,*) return 0 ;;
    *) return 1 ;;
  esac
}

verify_all_devices_up() {
  ok=0
  device_is_up "br-lan.2" || ok=1
  device_is_up "br-lan.3" || ok=1
  device_is_up "br-lan.4" || ok=1
  device_is_up "br-lan.5" || ok=1
  return "${ok}"
}

recreate_and_reload() {
  echo "Re-verifying/recreating VLAN uci sections before a second reload attempt..."
  uci revert network
  vlan_create_kids || true
  vlan_create_iot || true
  vlan_create_guests || true
  vlan_create_quarantine || true
  if vlan_verify_kids && vlan_verify_iot && vlan_verify_guests && vlan_verify_quarantine; then
    uci commit network
  else
    uci revert network
    echo "ERROR: could not re-establish complete VLAN uci sections on retry." >&2
    exit 1
  fi
  /etc/init.d/network reload
  sleep 3
}

if verify_all_devices_up; then
  echo "OK: br-lan.2/3/4/5 all show a real, UP kernel interface."
else
  echo "One or more br-lan.N kernel interfaces are not UP after reload - retrying once (revert+recreate+reload)..." >&2
  ip link show br-lan.2 2>&1 || true
  ip link show br-lan.3 2>&1 || true
  ip link show br-lan.4 2>&1 || true
  ip link show br-lan.5 2>&1 || true
  recreate_and_reload
  if verify_all_devices_up; then
    echo "OK: br-lan.2/3/4/5 all show a real, UP kernel interface after retry."
  else
    echo "ERROR: br-lan.2/3/4/5 did not all come up even after a revert+recreate+reload retry." >&2
    ip link show br-lan.2 2>&1 || true
    ip link show br-lan.3 2>&1 || true
    ip link show br-lan.4 2>&1 || true
    ip link show br-lan.5 2>&1 || true
    exit 1
  fi
fi

echo "Real kernel VLAN interfaces (br-lan.2@br-lan etc.), for the record:"
ip link show | grep 'br-lan\.' || true
REMOTE_SCRIPT

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin/api"

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/vlans ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/cgi-bin/api/vlans"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "chmod +x /www/cgi-bin/api/vlans && ls -la /www/cgi-bin/api/vlans"

echo "Verifying: curl http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/vlans ..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/vlans")"
echo "${BODY}"

case "${BODY}" in
  \[*\])
    echo "OK: /api/vlans responded with what looks like a JSON array."
    ;;
  *)
    echo "ERROR: response does not look like a JSON array." >&2
    exit 1
    ;;
esac

NAME_COUNT="$(printf '%s' "${BODY}" | grep -o '"name"' | wc -l | tr -d ' ')"
if [ "${NAME_COUNT}" != "5" ]; then
  echo "ERROR: expected exactly 5 entries in /api/vlans response, got ${NAME_COUNT}." >&2
  exit 1
fi
echo "OK: /api/vlans returned exactly 5 entries."

echo "OK: docker/provision/www/api/vlans deployed and verified, 4 VLAN interfaces (kids/iot/guests/quarantine) present alongside the pre-existing lan."
