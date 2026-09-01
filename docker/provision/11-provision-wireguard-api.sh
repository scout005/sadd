#!/bin/sh
# Installs WireGuard support (wireguard-tools + the full 9-package transitive
# kmod dependency chain — see docker/facts.md Section 14 for exactly which
# two of opkg's own first-round error messages hide a second layer of
# missing deps) and brings up a real, persisted `wg0` interface on the VM.
#
# Mirrors 08-provision-wifi-api.sh's "create baseline config from nothing"
# shape (this VM has no WireGuard config of any kind on a fresh boot). The
# baseline-config half below (see "Baseline network.wg0 config") runs its
# whole verify/create/commit/retry sequence inside ONE remote SSH session,
# the same way 08-provision-wifi-api.sh's wireless sections and
# 10-provision-vlans-api.sh's network sections do: uci-completeness is
# checked via `uci get` against the *uncommitted staged* config (uci itself
# can read staged-but-uncommitted values, so this needs no commit to check),
# `uci commit` only happens once that check passes, and only after commit is
# the interface brought up and its kernel-level liveness independently
# verified with its own retry — genuine verify-before-commit discipline,
# not just a same-named claim. (An earlier version of this script did the
# create+commit unconditionally, then verified from the *local* shell over
# several separate SSH round-trips, which both committed before verifying
# and left the local retry loop callable-but-unguarded against a hard
# remote/SSH failure short-circuiting past it via this script's own
# top-level `set -e` — this rewrite fixes both by moving the whole sequence
# server-side, matching 08/10 exactly instead of only claiming to.)
#
# Known DRY concern (same note as 08-provision-wifi-api.sh's own header
# comment, now applying a 4th time): the idempotent verify-completeness /
# create-if-missing / revert-and-retry-once-then-fail-loudly shape below is
# duplicated near-identically in 08-provision-wifi-api.sh,
# 09-provision-adblock-api.sh, and 10-provision-vlans-api.sh, with no shared
# library between them. A `docker/provision/lib/idempotent-uci.sh` (or
# similar) helper remains a reasonable extraction candidate — still
# deliberately deferred per that note's own reasoning (each script is still
# cheap to read standalone, and each has its own self-contained deployment
# reasons to stay that way).
#
# Two easy-to-miss gotchas this script works around (both confirmed live in
# docker/facts.md Section 14, not re-derived here):
#   1. `opkg install` exiting 0 for kmod-wireguard + wireguard-tools alone is
#      NOT proof the module is usable — the crypto-lib kmods have their own
#      undeclared-until-you-try-them second dependency layer, so all 9
#      packages must be installed together in one `opkg install` invocation,
#      then `modprobe wireguard` + `lsmod` must be checked explicitly.
#   2. netifd does NOT pick up the newly-installed wireguard.sh proto
#      handler from a plain `uci commit` + `ifup`/`network reload` — only a
#      full `/etc/init.d/network restart` makes netifd re-scan
#      /lib/netifd/proto/*.sh and recognize proto=wireguard.
#
# `/etc/wireguard-privkey` is created once (via `wg genkey`) and reused
# across re-runs of this script, so the derived public key stays stable
# across idempotent re-provisioning. `wg0`'s `disabled` UCI option is
# deliberately left unset (enabled) here — a later task's endpoint is what
# flips it.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/11-provision-wireguard-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 OPENWRT_HTTP_PORT=8081 bash docker/provision/11-provision-wireguard-api.sh
set -e

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

echo "=== 11-provision-wireguard-api.sh ==="

# --- Idempotency check: is a real, working wg0 already up? ---
# grep -E (POSIX ERE alternation) rather than BRE's GNU-only `\|` extension —
# confirmed live against this VM's busybox grep both ways.
if ssh_run "ip link show wg0 2>/dev/null | grep -Eq 'state UNKNOWN|POINTOPOINT'" && \
   ssh_run "wg show wg0 >/dev/null 2>&1"; then
  echo "wg0 already up with a real WireGuard interface — skipping package install and baseline config."
else
  echo "Downloading WireGuard packages + full transitive kmod dependency chain on the host..."
  WORKDIR="$(mktemp -d)"
  BASE_TARGETS="https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/packages"
  BASE_PACKAGES_BASE="https://downloads.openwrt.org/releases/23.05.5/packages/x86_64/base"

  for pkg in kmod-crypto-kpp kmod-crypto-lib-chacha20 kmod-crypto-lib-chacha20poly1305 \
             kmod-crypto-lib-curve25519 kmod-crypto-lib-poly1305 kmod-udptunnel4 \
             kmod-udptunnel6 kmod-wireguard; do
    curl -sf -o "${WORKDIR}/${pkg}.ipk" "${BASE_TARGETS}/${pkg}_5.15.167-1_x86_64.ipk"
  done
  curl -sf -o "${WORKDIR}/wireguard-tools.ipk" "${BASE_PACKAGES_BASE}/wireguard-tools_1.0.20210914-2_x86_64.ipk"

  echo "Copying to the VM..."
  scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" "${WORKDIR}"/*.ipk "${SSH_TARGET}:/tmp/"

  echo "Installing (all 9 in one command — installing the crypto-lib kmods separately from"
  echo "kmod-wireguard silently leaves the module unprobeable; see docker/facts.md Section 14)..."
  ssh_run "opkg install /tmp/kmod-crypto-kpp.ipk /tmp/kmod-crypto-lib-chacha20.ipk /tmp/kmod-crypto-lib-chacha20poly1305.ipk /tmp/kmod-crypto-lib-curve25519.ipk /tmp/kmod-crypto-lib-poly1305.ipk /tmp/kmod-udptunnel4.ipk /tmp/kmod-udptunnel6.ipk /tmp/kmod-wireguard.ipk /tmp/wireguard-tools.ipk && rm -f /tmp/kmod-*.ipk /tmp/wireguard-tools.ipk"

  rm -rf "${WORKDIR}"

  echo "Verifying the kernel module actually probes (opkg exit 0 alone is not proof — see facts.md Section 14)..."
  ssh_run "modprobe wireguard && lsmod | grep -q '^wireguard '"

  echo "Restarting the network service so netifd picks up the newly-installed wireguard.sh"
  echo "proto handler (a reload/ifup alone silently leaves proto=wireguard unrecognized — see"
  echo "docker/facts.md Section 14)..."
  ssh_run "/etc/init.d/network restart"
  sleep 3
fi

# --- Baseline network.wg0 config: uci-completeness verify -> commit only on
# success -> ifup -> independent kernel-liveness verify, all in ONE remote
# SSH session (mirrors 08/10's actual shape exactly — see header comment).
# A genuine remote failure here (including the final ERROR/exit 1 branches
# below, after both layers have exhausted their one retry) makes this ssh
# call itself return non-zero, which is meant to abort this script via its
# own top-level `set -e` — same as 08/10's own outer ssh invocations, which
# aren't guarded with `|| true` either, because by that point every
# server-side retry has already been exhausted and stopping is correct.
echo "Ensuring baseline network.wg0 config exists, is committed, and wg0 is really up (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
# shellcheck disable=SC2086
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" 'sh -s' <<'REMOTE_SCRIPT'
set -e

# === Layer 1: uci-completeness, checked BEFORE commit (mirrors
# 08-provision-wifi-api.sh / 10-provision-vlans-api.sh's established
# pattern) === wg_verify_uci reads back every option wg_create_uci is
# supposed to have set and compares it against the expected value, entirely
# against uci's own staged/uncommitted view (`uci get` sees uncommitted
# changes fine) — a bare `uci get network.wg0` success only proves the
# section exists, not that it's complete, and checking it this way means no
# commit is needed just to run this check.
wg_verify_uci() {
  [ "$(uci -q get network.wg0.proto 2>/dev/null)" = "wireguard" ] || return 1
  [ -n "$(uci -q get network.wg0.private_key 2>/dev/null)" ] || return 1
  [ "$(uci -q get network.wg0.listen_port 2>/dev/null)" = "51820" ] || return 1
  [ "$(uci -q get network.wg0.addresses 2>/dev/null)" = "10.9.0.1/24" ] || return 1
  return 0
}
# Always re-sets every field via `uci set` (no delete-first) — an
# already-existing section (even one committed with a wrong value by a
# stray hand-edit) is corrected in place, same as 08/10's create_fn
# functions never deleting their section first either.
wg_create_uci() {
  umask 077
  if [ ! -f /etc/wireguard-privkey ]; then
    wg genkey > /etc/wireguard-privkey
  fi
  PRIV="$(cat /etc/wireguard-privkey)"
  uci set network.wg0=interface
  uci set network.wg0.proto=wireguard
  uci set network.wg0.private_key="$PRIV"
  uci set network.wg0.listen_port=51820
  uci set network.wg0.addresses='10.9.0.1/24'
}

if wg_verify_uci; then
  echo "network.wg0 uci config already exists and is complete, skipping (idempotent)."
else
  if uci get network.wg0 >/dev/null 2>&1; then
    echo "network.wg0 exists but is INCOMPLETE (likely left behind by a prior run that failed partway through) - reverting uncommitted network changes and recreating..."
  else
    echo "Creating network.wg0 uci config..."
  fi
  uci revert network
  wg_create_uci || true

  if wg_verify_uci; then
    uci commit network
    echo "network.wg0 uci config created, verified, and committed."
  else
    echo "network.wg0 uci config did not verify after the first attempt - reverting and retrying once..." >&2
    uci revert network
    wg_create_uci || true

    if wg_verify_uci; then
      uci commit network
      echo "network.wg0 uci config created, verified, and committed on retry."
    else
      echo "ERROR: failed to create a complete network.wg0 uci config after retry. Reverting uncommitted changes and aborting." >&2
      uci revert network
      exit 1
    fi
  fi
fi

echo "uci network.wg0 config present and verified. Current state:"
uci show network.wg0

# === Layer 2: kernel-liveness, independent of layer 1 (a uci section can
# read back "correct" and still have no live kernel interface behind it if
# ifup raced or failed silently) — same two-layer split
# 10-provision-vlans-api.sh uses for its own br-lan.N devices. ===
wg_is_live() {
  ubus call network.interface.wg0 status 2>/dev/null | grep -q '"proto": "wireguard"' || return 1
  ip link show wg0 2>/dev/null | grep -q 'POINTOPOINT' || return 1
  wg show wg0 2>/dev/null | grep -q 'listening port: 51820' || return 1
  return 0
}

ifup wg0
sleep 2

if wg_is_live; then
  echo "OK: wg0 shows a real, up kernel interface with the expected proto/port."
else
  echo "wg0 kernel interface not live after ifup - retrying once (ifdown, drop any leftover link, ifup again)..." >&2
  ifdown wg0 2>/dev/null || true
  ip link delete wg0 2>/dev/null || true
  ifup wg0
  sleep 2
  if wg_is_live; then
    echo "OK: wg0 came up after retry."
  else
    echo "ERROR: wg0 still not showing a live kernel interface after a retry. Investigate manually." >&2
    exit 1
  fi
fi

echo "Real public key: $(wg show wg0 public-key)"
REMOTE_SCRIPT

# --- Deploy the /api/wireguard endpoint ---
echo "Deploying /api/wireguard..."
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "$(dirname "$0")/www/api/wireguard" \
  "${SSH_TARGET}:/www/cgi-bin/api/wireguard"
ssh_run "chmod +x /www/cgi-bin/api/wireguard"

# curl (not wget, which is all this VM has — see 08/09/10's own verify
# blocks) runs on the HOST against the mapped HTTP port, same as every
# other endpoint's deploy script.
echo "Verifying: curl http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/wireguard ..."
BODY="$(curl -sf "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/wireguard")"
echo "${BODY}"

case "${BODY}" in
  \{*\})
    echo "OK: /api/wireguard responded with what looks like a JSON object."
    ;;
  *)
    echo "ERROR: response does not look like a JSON object." >&2
    exit 1
    ;;
esac

echo "=== 11-provision-wireguard-api.sh done ==="
