#!/bin/sh
# Creates a baseline DNS-based ad-blocklist on the VM (dnsmasq's own
# `confdir` mechanism — no new opkg package needed, confirmed live and
# documented in docker/facts.md Section 12, along with the exact `uci set`
# sequence this script uses, unmodified), then deploys
# docker/provision/www/api/adblock (the tracked source of truth for the
# /api/adblock endpoint) onto the VM and verifies it responds with real
# JSON.
#
# Like 08-provision-wifi-api.sh (and unlike 04-07, which only deploy a
# stateless endpoint file), this script also creates real, persisted VM
# state — there's no pre-existing blocklist to just read.
#
# Baseline config created (mirrors docker/facts.md Section 12's confirmed
# sequence exactly):
#   - /etc/dnsmasq.blocklist.d/blocklist.conf — one `address=/<domain>/0.0.0.0`
#     line per demo domain. The three domains are the exact ones shown in
#     sadd-website.html's screens['adblock'] "This week" mini-log (confirmed
#     live by reading the actual HTML, not assumed): doubleclick.net (312
#     blocked), adservice.google.com (210 blocked), tracker.example.com (145
#     blocked) — order preserved to match the mockup, though order has no
#     functional effect on dnsmasq.
#   - dhcp.@dnsmasq[0].confdir=/etc/dnsmasq.blocklist.d — tells dnsmasq to
#     load every file under that directory as extra config (the blocklist
#     file above).
#   - dhcp.@dnsmasq[0].logqueries=1 — makes every DNS query show up in
#     `logread`, including a distinct, greppable line for a blocked hit
#     (`... config <domain> is 0.0.0.0`, confirmed live) — this is what lets
#     the /api/adblock endpoint count real blocked lookups from the log
#     buffer rather than needing a separate counter/database.
#   - `/etc/init.d/dnsmasq restart` to apply.
#
# Idempotent AND self-healing, same pattern as 08-provision-wifi-api.sh:
# completeness is checked, not mere existence — the blocklist file's content
# is compared byte-for-byte against the expected three lines, and both uci
# options are read back and compared against their expected values. Re-running
# this script against an already fully-configured VM is a no-op for config
# creation (skips straight to the functional verify + endpoint (re)deploy). If
# the config is ever found partially/incorrectly set (e.g. left behind by a
# prior run that died partway through, or a blocklist file with stale/partial
# content), any uncommitted `dhcp` changes are reverted (`uci revert dhcp`)
# and the whole config (file + both uci options) is recreated from scratch,
# verified again, and only committed once complete (one retry, then a loud
# failure with a revert, never a silent partial commit) — same
# verify-before-commit/revert-on-failure discipline as
# 08-provision-wifi-api.sh and docker/provision/www/api/firewall-rules'
# POST handler.
#
# Beyond the uci/file readback, this script also runs a genuine functional
# check every time it runs (not just after a fresh create): a real
# `nslookup doubleclick.net 127.0.0.1` against the VM over SSH, confirmed to
# return `Address: 0.0.0.0` — proof the whole confdir/logqueries/restart
# pipeline is actually in effect, not just that uci *claims* it is.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/09-provision-adblock-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/09-provision-adblock-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/www/api/adblock"

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring baseline DNS blocklist exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" 'sh -s' <<'REMOTE_SCRIPT'
set -e

BLOCKLIST_DIR="/etc/dnsmasq.blocklist.d"
BLOCKLIST_FILE="${BLOCKLIST_DIR}/blocklist.conf"
EXPECTED_CONFDIR="/etc/dnsmasq.blocklist.d"

# Exact demo domains confirmed live against sadd-website.html's
# screens['adblock'] "This week" mini-log (docker/facts.md Section 12 /
# this script's header comment). Order matches the mockup.
EXPECTED_BLOCKLIST_CONTENT='address=/doubleclick.net/0.0.0.0
address=/adservice.google.com/0.0.0.0
address=/tracker.example.com/0.0.0.0'

# === verify-before-commit, revert-on-failure (mirrors 08-provision-wifi-api.sh) ===
# Checks COMPLETENESS, not mere existence: the blocklist file's content is
# compared byte-for-byte against the expected three lines (a file that
# exists but is missing a domain, or was left over from an earlier/partial
# run, must NOT be treated as "already done"), and both uci options are read
# back and compared against their expected values.
adblock_verify_config() {
  [ -f "${BLOCKLIST_FILE}" ] || return 1
  actual_content="$(cat "${BLOCKLIST_FILE}" 2>/dev/null)"
  [ "${actual_content}" = "${EXPECTED_BLOCKLIST_CONTENT}" ] || return 1

  [ "$(uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null)" = "${EXPECTED_CONFDIR}" ] || return 1
  [ "$(uci -q get dhcp.@dnsmasq[0].logqueries 2>/dev/null)" = "1" ] || return 1

  return 0
}
adblock_create_config() {
  mkdir -p "${BLOCKLIST_DIR}"
  printf '%s\n' "${EXPECTED_BLOCKLIST_CONTENT}" > "${BLOCKLIST_FILE}"
  uci set dhcp.@dnsmasq[0].confdir="${BLOCKLIST_DIR}"
  uci set dhcp.@dnsmasq[0].logqueries=1
}

CONFIG_CHANGED=0

if adblock_verify_config; then
  echo "dnsmasq blocklist config already exists and is complete, skipping (idempotent)."
else
  if [ -f "${BLOCKLIST_FILE}" ] || uci -q get dhcp.@dnsmasq[0].confdir >/dev/null 2>&1; then
    echo "dnsmasq blocklist config exists but is INCOMPLETE (missing domain(s), stale content, or a prior run that failed partway through) - reverting uncommitted dhcp changes and recreating..."
  else
    echo "Creating dnsmasq blocklist config..."
  fi
  uci revert dhcp
  adblock_create_config

  if adblock_verify_config; then
    uci commit dhcp
    CONFIG_CHANGED=1
    echo "dnsmasq blocklist config created, verified, and committed."
  else
    echo "dnsmasq blocklist config did not verify after the first attempt - reverting and retrying once..." >&2
    uci revert dhcp
    adblock_create_config

    if adblock_verify_config; then
      uci commit dhcp
      CONFIG_CHANGED=1
      echo "dnsmasq blocklist config created, verified, and committed on retry."
    else
      echo "ERROR: failed to create a complete dnsmasq blocklist config after retry. Reverting uncommitted changes and aborting." >&2
      uci revert dhcp
      exit 1
    fi
  fi
fi

if [ "${CONFIG_CHANGED}" = "1" ]; then
  echo "Restarting dnsmasq to apply the new confdir/logqueries..."
  /etc/init.d/dnsmasq restart
  sleep 2
fi

echo "dnsmasq blocklist config present and verified. Current state:"
uci get dhcp.@dnsmasq[0].confdir
uci get dhcp.@dnsmasq[0].logqueries
cat "${BLOCKLIST_FILE}"

# === Functional check, every run (not just after a fresh create) ===
# Real proof the whole confdir/logqueries/restart pipeline is actually in
# effect, not just that uci *claims* it is — same "don't just trust an
# existence/config check" rigor as the rest of this script.
echo "Confirming a real blocked lookup resolves to 0.0.0.0..."
# busybox nslookup exits non-zero here even on a successful blocked lookup
# (it also issues an AAAA query, which this address=/domain/ line doesn't
# cover, and that half legitimately reports REFUSED - confirmed live) - so
# `|| true` keeps `set -e` from aborting before the real check below, which
# looks at the actual printed Address line, not the exit code.
NSLOOKUP_OUT="$(nslookup doubleclick.net 127.0.0.1 2>&1)" || true
echo "${NSLOOKUP_OUT}"
case "${NSLOOKUP_OUT}" in
  *"Address: 0.0.0.0"*)
    echo "OK: doubleclick.net resolves to 0.0.0.0 via this VM's dnsmasq (real DNS blocking confirmed)."
    ;;
  *)
    echo "ERROR: doubleclick.net did not resolve to 0.0.0.0 - dnsmasq blocklist is not actually in effect." >&2
    exit 1
    ;;
esac
REMOTE_SCRIPT

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" "mkdir -p /www/cgi-bin/api"

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/adblock ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "root@${OPENWRT_HOST}:/www/cgi-bin/api/adblock"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "root@${OPENWRT_HOST}" \
  "chmod +x /www/cgi-bin/api/adblock && ls -la /www/cgi-bin/api/adblock"

echo "Verifying: curl http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/adblock ..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/adblock")"
echo "${BODY}"

case "${BODY}" in
  \{*\})
    echo "OK: /api/adblock responded with what looks like a JSON object."
    ;;
  *)
    echo "ERROR: response does not look like a JSON object." >&2
    exit 1
    ;;
esac

echo "OK: docker/provision/www/api/adblock deployed and verified, DNS blocklist baseline present."
