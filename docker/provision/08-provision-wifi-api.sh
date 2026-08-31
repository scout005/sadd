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
# Idempotent: each section is checked for existence (`uci get
# wireless.<section> 2>/dev/null`) before being created, so re-running this
# script against an already-configured VM is a no-op for config creation
# (skips straight to re-deploying the endpoint file) rather than failing or
# duplicating sections.
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
touch /etc/config/wireless

if uci get wireless.radio0 >/dev/null 2>&1; then
  echo "wireless.radio0 already exists, skipping (idempotent)."
else
  echo "Creating wireless.radio0 (wifi-device)..."
  uci set wireless.radio0=wifi-device
  uci set wireless.radio0.type=mac80211
  uci set wireless.radio0.disabled=1
fi

if uci get wireless.default_radio0 >/dev/null 2>&1; then
  echo "wireless.default_radio0 already exists, skipping (idempotent)."
else
  echo "Creating wireless.default_radio0 (wifi-iface, main SSID)..."
  uci set wireless.default_radio0=wifi-iface
  uci set wireless.default_radio0.device=radio0
  uci set wireless.default_radio0.network=lan
  uci set wireless.default_radio0.mode=ap
  uci set wireless.default_radio0.ssid='Smith Family'
  uci set wireless.default_radio0.encryption=psk2
fi

if uci get wireless.guest >/dev/null 2>&1; then
  echo "wireless.guest already exists, skipping (idempotent)."
else
  echo "Creating wireless.guest (wifi-iface, guest SSID, disabled)..."
  uci set wireless.guest=wifi-iface
  uci set wireless.guest.device=radio0
  uci set wireless.guest.network=lan
  uci set wireless.guest.mode=ap
  uci set wireless.guest.ssid='Smith Guest'
  uci set wireless.guest.encryption=psk2
  uci set wireless.guest.disabled=1
fi

uci commit wireless
echo "wireless config committed. Current state:"
uci show wireless
REMOTE_SCRIPT

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
