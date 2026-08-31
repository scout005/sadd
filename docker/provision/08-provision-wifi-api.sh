#!/bin/sh
# Creates a baseline /etc/config/wireless on the VM (this VM has NO wireless
# config at all on a fresh boot — no wireless hardware for OpenWrt to have
# auto-detected during first boot's `wifi detect`; confirmed live and
# documented in docker/facts.md Section 11, along with the exact `uci set`
# sequence this script uses, unmodified), then deploys
# docker/provision/www/api/wifi (the tracked source of truth for the
# /api/wifi endpoint) onto the VM and verifies it responds with real JSON.
#
# Unlike 04-07 (which only deploy a stateless endpoint file), this script
# also creates real, persisted VM state (the wireless UCI config itself) —
# there's nothing pre-existing to read the way `uci show firewall` already
# had real zones to build on for Task 3/Wave 1's firewall-rules endpoint.
# See docker/facts.md Section 11 for the full live investigation.
#
# Baseline config created (mirrors docker/facts.md Section 11's confirmed
# sequence exactly):
#   - wireless.radio0 (wifi-device, type=mac80211, disabled=1) — a phantom
#     radio; this VM has no real wireless hardware, so the radio itself
#     stays disabled. `wifi reload` against this was confirmed live to exit
#     cleanly (just informational "not supported" lines), not hang/error.
#   - wireless.default_radio0 (wifi-iface, device=radio0, network=lan,
#     mode=ap, ssid='Smith Family', encryption=psk2) — the main SSID,
#     matching sadd-website.html's screens['settings'] static demo value
#     ("Wi-Fi name & password" row's span reads exactly "Smith Family";
#     confirmed by reading the actual HTML, not assumed) so the frontend's
#     eventual real/static values agree.
#   - wireless.guest (wifi-iface, device=radio0, network=lan, mode=ap,
#     ssid='Smith Guest', encryption=psk2, disabled=1) — a second SSID for
#     the Guest Wi-Fi screen, disabled to start, matching
#     screens['settings']'s static "Guest network: Off" default (confirmed
#     the same way). `network=lan` is used rather than a dedicated guest
#     network/firewall zone deliberately: Task 1/2's scope is read-only
#     (display SSID + on/off state), for which a bare wifi-iface section is
#     enough — a real, separate guest network + firewall zone is explicitly
#     out of scope for Wave 3 per the design spec (config-level
#     demonstration only, not a functioning isolated guest network).
#
# Idempotent AND self-healing: each section is checked for COMPLETENESS, not
# mere existence — every expected field is read back with `uci get
# wireless.<section>.<option>` and compared against its expected value.
# Re-running this script against an already fully-configured VM is a no-op
# for config creation (skips straight to re-deploying the endpoint file). If
# a section exists but is missing/wrong on any field (e.g. left behind by a
# prior run that died partway through a `uci set` sequence — `set -e` would
# abort that run, but uci's uncommitted staged change for the section
# persists in /tmp/.uci/ across script invocations, so a naive existence
# check would see it and skip it FOREVER), the uncommitted wireless changes
# are reverted (`uci revert wireless`) and the section is recreated from
# scratch, verified again, and only committed once every expected field
# reads back correctly — one retry on the same run, then a loud failure with
# a revert (never a silent partial commit). Each section is committed
# individually right after it verifies, so reverting to fix a later section
# never touches an earlier section that already committed successfully.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/08-provision-wifi-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/08-provision-wifi-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/www/api/wifi"

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring baseline /etc/config/wireless exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" 'sh -s' <<'REMOTE_SCRIPT'
set -e

# === Issue 2 fix: verify-before-commit, revert-on-failure ===
# Mirrors docker/provision/www/api/firewall-rules's established pattern for
# this exact class of problem (see that file's POST handler: create, verify
# every field by readback, `uci revert firewall` and fail loudly if
# anything's wrong, only `uci commit` once verification passes) — adapted
# here to a shell-script/SSH context instead of firewall-rules' Lua CGI
# runtime, and to this script's "create if missing" shape instead of
# firewall-rules' "always create new" shape.
#
# Each wifi_verify_* function reads back every option the matching
# wifi_create_* function is supposed to have set and compares it against the
# expected value — a bare `uci get wireless.<section>` success (the old
# check) only proves the section exists, not that it's complete; a section
# that exists but is missing/wrong fields is exactly what a prior run dying
# partway through its `uci set` sequence leaves behind (uci stages changes
# in /tmp/.uci/ across process invocations, so a half-set section survives
# to the next run and would be silently skipped forever by an existence-only
# check).

wifi_verify_radio0() {
  [ "$(uci -q get wireless.radio0.type 2>/dev/null)" = "mac80211" ] || return 1
  [ "$(uci -q get wireless.radio0.disabled 2>/dev/null)" = "1" ] || return 1
  return 0
}
wifi_create_radio0() {
  uci set wireless.radio0=wifi-device
  uci set wireless.radio0.type=mac80211
  uci set wireless.radio0.disabled=1
}

wifi_verify_default_radio0() {
  [ "$(uci -q get wireless.default_radio0.device 2>/dev/null)" = "radio0" ] || return 1
  [ "$(uci -q get wireless.default_radio0.network 2>/dev/null)" = "lan" ] || return 1
  [ "$(uci -q get wireless.default_radio0.mode 2>/dev/null)" = "ap" ] || return 1
  [ "$(uci -q get wireless.default_radio0.ssid 2>/dev/null)" = "Smith Family" ] || return 1
  [ "$(uci -q get wireless.default_radio0.encryption 2>/dev/null)" = "psk2" ] || return 1
  return 0
}
wifi_create_default_radio0() {
  uci set wireless.default_radio0=wifi-iface
  uci set wireless.default_radio0.device=radio0
  uci set wireless.default_radio0.network=lan
  uci set wireless.default_radio0.mode=ap
  uci set wireless.default_radio0.ssid='Smith Family'
  uci set wireless.default_radio0.encryption=psk2
}

wifi_verify_guest() {
  [ "$(uci -q get wireless.guest.device 2>/dev/null)" = "radio0" ] || return 1
  [ "$(uci -q get wireless.guest.network 2>/dev/null)" = "lan" ] || return 1
  [ "$(uci -q get wireless.guest.mode 2>/dev/null)" = "ap" ] || return 1
  [ "$(uci -q get wireless.guest.ssid 2>/dev/null)" = "Smith Guest" ] || return 1
  [ "$(uci -q get wireless.guest.encryption 2>/dev/null)" = "psk2" ] || return 1
  [ "$(uci -q get wireless.guest.disabled 2>/dev/null)" = "1" ] || return 1
  return 0
}
wifi_create_guest() {
  uci set wireless.guest=wifi-iface
  uci set wireless.guest.device=radio0
  uci set wireless.guest.network=lan
  uci set wireless.guest.mode=ap
  uci set wireless.guest.ssid='Smith Guest'
  uci set wireless.guest.encryption=psk2
  uci set wireless.guest.disabled=1
}

# $1 = section name (for messages/uci path), $2 = verify function, $3 = create function.
# Commits per-section (not once at the end) so that reverting to fix one
# broken section can never undo an earlier section that already verified and
# committed successfully. `"$create_fn" || true` (rather than calling it
# bare) keeps a mid-creation `uci set` failure from letting `set -e` kill the
# whole script before the retry/revert logic below ever runs — any partial
# effect is still caught by the readback in `"$verify_fn"` immediately after.
ensure_wireless_section() {
  section="$1"; verify_fn="$2"; create_fn="$3"

  if "$verify_fn"; then
    echo "wireless.${section} already exists and is complete, skipping (idempotent)."
    return 0
  fi

  if uci get "wireless.${section}" >/dev/null 2>&1; then
    echo "wireless.${section} exists but is INCOMPLETE (likely left behind by a prior run that failed partway through) - reverting uncommitted wireless changes and recreating..."
  else
    echo "Creating wireless.${section}..."
  fi
  uci revert wireless
  "$create_fn" || true

  if "$verify_fn"; then
    uci commit wireless
    echo "wireless.${section} created, verified, and committed."
    return 0
  fi

  echo "wireless.${section} did not verify after the first attempt - reverting and retrying once..." >&2
  uci revert wireless
  "$create_fn" || true

  if "$verify_fn"; then
    uci commit wireless
    echo "wireless.${section} created, verified, and committed on retry."
    return 0
  fi

  echo "ERROR: failed to create a complete wireless.${section} section after retry. Reverting uncommitted changes and aborting." >&2
  uci revert wireless
  exit 1
}

touch /etc/config/wireless

ensure_wireless_section radio0 wifi_verify_radio0 wifi_create_radio0
ensure_wireless_section default_radio0 wifi_verify_default_radio0 wifi_create_default_radio0
ensure_wireless_section guest wifi_verify_guest wifi_create_guest

echo "wireless config present and verified. Current state:"
uci show wireless
REMOTE_SCRIPT

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin/api"

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/wifi ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/cgi-bin/api/wifi"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "chmod +x /www/cgi-bin/api/wifi && ls -la /www/cgi-bin/api/wifi"

echo "Verifying: curl http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/wifi ..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/wifi")"
echo "${BODY}"

case "${BODY}" in
  \{*\})
    echo "OK: /api/wifi responded with what looks like a JSON object."
    ;;
  *)
    echo "ERROR: response does not look like a JSON object." >&2
    exit 1
    ;;
esac

echo "OK: docker/provision/www/api/wifi deployed and verified, wireless baseline config present."
