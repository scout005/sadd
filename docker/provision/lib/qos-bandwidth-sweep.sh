#!/bin/sh
# /usr/bin/qos-bandwidth-sweep.sh — run every 5 minutes by cron (see
# 18-provision-qos-bandwidth-api.sh). For every uci firewall rule this
# project created for QoS Priority marking (named `qospriority-<mac with
# colons stripped>`, see docker/provision/www/api/qos-priority), reads that
# device's real nft mangle_forward counter (tcp+udp summed — a single
# qos-priority uci rule with no explicit `proto` expands into TWO separate
# nft rules, one per protocol, confirmed live docker/facts.md Section
# 15/19) and accumulates it onto a persisted per-device-per-UTC-day
# running total.
#
# Why accumulate instead of trusting the raw nft counter to hold a full
# day's traffic: `nft reset` does not work on this VM (confirmed live,
# docker/facts.md Section 19 — every documented reset form left a known
# non-zero counter completely unchanged). `fw4 reload` DOES reliably zero
# every counter in the table, but only as a side effect of fully
# regenerating the whole ruleset from uci config from scratch — and fw4
# reload is called by EVERY existing write endpoint in this project
# (device-pause, qos-priority itself, device-bedtime, firewall-rules,
# etc.), not just a purpose-built reset. So the raw counter can be zeroed
# by something totally unrelated at any moment, not just at a controlled
# daily boundary. Polling every 5 minutes and adding whatever's
# accumulated since the last tick onto a persisted total survives that —
# at the cost of a real, disclosed limitation: if an unrelated fw4 reload
# happens BETWEEN two sweep ticks, whatever traffic accumulated in that
# gap is lost (the counter is already back to zero by the time this sweep
# next reads it) — an undercount, never an overcount, for that one device
# that day. Rare in practice (write actions aren't constant), and
# documented plainly rather than glossed over — see docker/README.md's
# Known Limitations and
# docs/superpowers/specs/2026-09-02-qos-bandwidth-today-design.md.
#
# Storage: /etc/qos-bandwidth/<mac-no-colons>-<YYYYMMDD>.txt, one plain
# integer (accumulated bytes) per device per UTC calendar day. A new day is
# simply a filename that doesn't exist yet (read as 0) — no hour-comparison
# arithmetic anywhere in this script, deliberately avoiding the busybox-ash
# `$(( ))` zero-padded-hour gotcha bedtime-sweep.sh had to route around
# (docker/facts.md Section 16) by not needing hour arithmetic at all. Byte
# totals ARE run through `$(( ))` below, so both operands are defensively
# stripped of any leading zeros first — this project's own arithmetic
# values should never naturally have one (shell arithmetic never prints a
# zero-padded result), but a corrupted/manually-edited state file could,
# and a leading-zero digit sequence in $(( )) risks the exact same
# octal-misinterpretation bug class bedtime-sweep.sh found, so this is
# defensive, not decorative.
#
# No top-level `set -e`, deliberately, same reasoning as devpause-sweep.sh
# and bedtime-sweep.sh: one device's read/write failing shouldn't cancel
# the sweep for every other device this tick.

STATE_DIR="/etc/qos-bandwidth"
mkdir -p "$STATE_DIR"

TODAY="$(date -u +%Y%m%d)"

strip_leading_zeros() {
  # "007" -> "7", "0" -> "0", "" -> "0". Avoids $(( )) octal
  # misinterpretation on a leading-zero digit string.
  local v
  v="$(echo "$1" | sed 's/^0*//')"
  if [ -z "$v" ]; then echo 0; else echo "$v"; fi
}

for id in $(uci show firewall | grep "\.name='qospriority-" | sed -n "s/^firewall\.\([^.]*\)\.name=.*/\1/p"); do
  MAC="$(uci -q get "firewall.${id}.src_mac")"
  if [ -z "$MAC" ]; then
    logger -t qos-bandwidth-sweep "ERROR: firewall.${id} has no src_mac; skipping"
    continue
  fi
  MAC_NOCOLON="$(echo "$MAC" | tr -d ':' | tr 'A-F' 'a-f')"
  RULE_NAME="qospriority-${MAC_NOCOLON}"

  NFT_OUTPUT="$(nft list chain inet fw4 mangle_forward 2>/dev/null)"
  NFT_STATUS=$?
  if [ "$NFT_STATUS" != "0" ]; then
    logger -t qos-bandwidth-sweep "ERROR: nft list chain inet fw4 mangle_forward failed (exit ${NFT_STATUS}); skipping ${RULE_NAME} this tick"
    continue
  fi

  # Sum both nft rule lines' bytes for this device's mark rule (tcp + udp —
  # a single uci rule with no explicit proto expands into both, confirmed
  # live docker/facts.md Section 15/19). Each matching line looks like:
  #   ... counter packets N bytes M ... comment "!fw4: qospriority-aabbccddeeff"
  BYTES_NOW="$(echo "$NFT_OUTPUT" \
    | grep "\"!fw4: ${RULE_NAME}\"" \
    | sed -n 's/.*counter packets [0-9]* bytes \([0-9]*\).*/\1/p' \
    | awk '{sum+=$1} END {print sum+0}')"
  BYTES_NOW="$(strip_leading_zeros "$BYTES_NOW")"

  STATE_FILE="${STATE_DIR}/${MAC_NOCOLON}-${TODAY}.txt"
  PREV_TOTAL="$(cat "$STATE_FILE" 2>/dev/null)"
  case "$PREV_TOTAL" in
    ''|*[!0-9]*) PREV_TOTAL=0 ;;
  esac
  PREV_TOTAL="$(strip_leading_zeros "$PREV_TOTAL")"

  NEW_TOTAL=$((PREV_TOTAL + BYTES_NOW))
  echo "$NEW_TOTAL" > "$STATE_FILE" \
    || logger -t qos-bandwidth-sweep "ERROR: failed to write ${STATE_FILE}"
done

# Zero every counter in the table for the next window — the only working
# reset mechanism on this VM (docker/facts.md Section 19). Safe to call
# even when the for-loop above ran zero times (no qos-priority devices
# marked yet) — fw4 reload is idempotent and every other sweep/endpoint in
# this project already calls it routinely.
if ! fw4 reload >/dev/null 2>&1; then
  logger -t qos-bandwidth-sweep "ERROR: fw4 reload failed after accumulating this tick's counters"
fi
