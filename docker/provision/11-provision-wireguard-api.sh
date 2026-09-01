#!/bin/sh
# Installs WireGuard support (wireguard-tools + the full 9-package transitive
# kmod dependency chain — see docker/facts.md Section 14 for exactly which
# two of opkg's own first-round error messages hide a second layer of
# missing deps) and brings up a real, persisted `wg0` interface on the VM.
#
# Mirrors 08-provision-wifi-api.sh's "create baseline config from nothing"
# shape (this VM has no WireGuard config of any kind on a fresh boot),
# including its idempotent verify/create/revert/retry-once discipline.
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
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/11-provision-wireguard-api.sh
set -e

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

echo "=== 11-provision-wireguard-api.sh ==="

# --- Idempotency check: is a real, working wg0 already up? ---
if ssh_run "ip link show wg0 2>/dev/null | grep -q 'state UNKNOWN\|POINTOPOINT'" && \
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

# --- Baseline network.wg0 config: create if missing, verify via readback, retry once ---
create_and_verify_wg0() {
  ssh_run "
    umask 077
    if [ ! -f /etc/wireguard-privkey ]; then
      wg genkey > /etc/wireguard-privkey
    fi
    PRIV=\$(cat /etc/wireguard-privkey)
    uci -q delete network.wg0 2>/dev/null
    uci set network.wg0=interface
    uci set network.wg0.proto=wireguard
    uci set network.wg0.private_key=\"\$PRIV\"
    uci set network.wg0.listen_port=51820
    uci set network.wg0.addresses='10.9.0.1/24'
    uci commit network
    ifup wg0
  "
  sleep 2
}

verify_wg0() {
  ssh_run "ubus call network.interface.wg0 status 2>/dev/null | grep -q '\"proto\": \"wireguard\"'" && \
  ssh_run "ip link show wg0 2>/dev/null | grep -q 'POINTOPOINT'" && \
  ssh_run "wg show wg0 2>/dev/null | grep -q 'listening port: 51820'"
}

if verify_wg0; then
  echo "network.wg0 already correctly configured and up."
else
  echo "Creating baseline network.wg0 config (attempt 1)..."
  create_and_verify_wg0
  if verify_wg0; then
    echo "network.wg0 verified up after attempt 1."
  else
    echo "Verification failed after attempt 1 — reverting and retrying once..."
    ssh_run "uci revert network; ip link del wg0 2>/dev/null || true"
    sleep 1
    create_and_verify_wg0
    if verify_wg0; then
      echo "network.wg0 verified up after retry."
    else
      echo "FATAL: network.wg0 still not verifiably up after a revert+retry. Investigate manually." >&2
      exit 1
    fi
  fi
fi

echo "Real public key: $(ssh_run "wg show wg0 public-key")"
echo "=== 11-provision-wireguard-api.sh done ==="
