#!/bin/sh
# /usr/bin/devpause-sweep.sh — run every minute by cron (see
# 13-provision-devpause-api.sh). Finds any uci firewall rule this project
# created for a per-device "pause internet" action (named `devpause-<mac
# with colons stripped>`, carrying a custom `paused_until` uci option — an
# epoch-seconds timestamp; uci tolerates arbitrary option names on a rule
# section, and fw4 silently ignores ones it doesn't recognize, confirmed live)
# whose paused_until has passed, and removes it — real auto-expiry.
#
# Real device-pause creation is /cgi-bin/api/device-pause's job (a later
# task, not yet built); this script only ever DELETES expired ones, never
# creates them.
#
# Positional-addressing gotcha this script works around (code review
# finding): this VM's uci firewall rules are anonymous sections addressed
# positionally (firewall.@rule[N] — confirmed live in docker/facts.md
# Section 13/14, the same shape device-pause creation uses: `uci add
# firewall rule` + `uci set firewall.@rule[-1]...`). Deleting a
# lower-indexed @rule[N] immediately renumbers every higher-indexed section
# by one in the live staged uci state — so collecting every expired
# section's id up front in ONE snapshot, then deleting them all in that
# same order, is unsafe whenever >=2 pauses expire in the same tick: every
# id after the first delete in that pass would end up addressing whatever
# section shifted into that vacated slot, not the rule actually intended.
# To avoid that, find_one_expired_id() below does a completely FRESH `uci
# show firewall` scan every single time it's called, and the main loop
# calls it again immediately after each delete, repeating until a fresh
# scan finds nothing left to expire — never acting on a stale batch of
# ids. (Even the old batched version could only ever skip a genuinely
# expired rule until the next tick, never delete a wrong non-expired one —
# paused_until is always re-read fresh right before the delete decision —
# but "removes it" wasn't reliably true within one pass for >=2 same-tick
# expirations before this fix.)
#
# No top-level `set -e` here, deliberately: this script's own per-item
# failure handling is already defensive by design (the numeric `-le` test
# runs under `2>/dev/null` so a garbage/missing paused_until value is
# treated as "not expired" rather than aborting the whole sweep, and one
# section's delete failing shouldn't stop the loop from still trying the
# rest) — a bare `set -e` would undermine exactly that, turning one bad
# section into a silently-cancelled sweep for every other section this
# tick. `uci commit`/`fw4 reload` failures are instead explicitly logged
# below rather than silently swallowed.

NOW=$(date +%s)
CHANGED=0

# find_one_expired_id: fresh `uci show firewall` scan on every call.
# Prints the section id of the first still-expired devpause-* rule found
# (POSIX sed/grep only — busybox ash, not bash/gawk, matching every other
# script in this directory's tooling assumptions) and returns 0, or prints
# nothing and returns 1 if none are currently expired.
find_one_expired_id() {
  for id in $(uci show firewall | grep "\.name='devpause-" | sed -n "s/^firewall\.\([^.]*\)\.name=.*/\1/p"); do
    paused_until=$(uci -q get "firewall.${id}.paused_until")
    if [ -n "$paused_until" ] && [ "$paused_until" -le "$NOW" ] 2>/dev/null; then
      echo "$id"
      return 0
    fi
  done
  return 1
}

id=$(find_one_expired_id)
while [ -n "$id" ]; do
  paused_until=$(uci -q get "firewall.${id}.paused_until")
  logger -t devpause-sweep "removing expired pause: firewall.${id} (paused_until=${paused_until}, now=${NOW})"
  uci -q delete "firewall.${id}"
  CHANGED=1
  id=$(find_one_expired_id)
done

if [ "$CHANGED" = "1" ]; then
  if uci commit firewall; then
    if ! fw4 reload >/dev/null 2>&1; then
      logger -t devpause-sweep "ERROR: fw4 reload failed after removing expired pause(s) — uci config no longer lists them but nftables state may not reflect that yet"
    fi
  else
    logger -t devpause-sweep "ERROR: uci commit firewall failed after removing expired pause(s) — changes may not be persisted"
  fi
fi
