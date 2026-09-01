#!/bin/sh
# /usr/bin/bedtime-sweep.sh — run every 5 minutes by cron (see
# 15-provision-bedtime-api.sh). Finds every uci firewall rule this project
# created for a per-device Bedtime schedule (named `bedtime-<mac with colons
# stripped>`) and sets its OWN `enabled` uci option to match whether the
# current UTC hour falls in the fixed 21:00-07:00 window — NOT any
# particular real-world local time. This VM has no configured timezone
# (confirmed live, docker/facts.md Section 16: `date` shows UTC, `uci get
# system.@system[0].zonename` returns "Entry not found") — there is no
# concept of "the family's own time" anywhere in this environment or the
# mockup to read a real local schedule from, so a fixed UTC window is the
# honest, disclosed approximation this feature uses, not a bug.
#
# `uci firewall` rule sections support a genuine `enabled` option, distinct
# from the section's existence, that fw4 honors to skip emitting the rule
# entirely without deleting it — confirmed live before this script was
# written (docker/facts.md Section 16): `enabled='0'` + `fw4 reload` makes
# the rule genuinely absent from `nft list ruleset`; `enabled='1'` brings the
# exact same rule back. This is what lets a Bedtime-configured device's rule
# PERSIST across day and night (recording "Bedtime is set up for this
# device") while only actually blocking during the scheduled window.
#
# Real device-pause creation (a separate feature, Wave 5) and real
# device-bedtime creation (this wave's /cgi-bin/api/device-bedtime, a
# different task in this same plan) are what create these rules in the
# first place — this script only ever adjusts an existing rule's `enabled`
# flag, never creates or deletes a rule itself. Safe to run standalone
# before any bedtime rule exists yet (the for-loop below simply iterates
# zero times).
#
# Known shell gotcha this script deliberately avoids (confirmed live before
# writing this script): `date -u +%H` is zero-padded (e.g. "08", "09"),
# which breaks arithmetic expansion (`$((HOUR))`) via octal
# misinterpretation on this VM's busybox ash — and ash does NOT support the
# usual `10#$HOUR` base-prefix workaround either (confirmed live: "ash:
# arithmetic syntax error"). This script therefore NEVER wraps $HOUR in
# `$(( ))` — POSIX `test`/`[`'s `-ge`/`-lt` numeric comparisons parse a
# zero-padded string correctly with no such reinterpretation, confirmed
# live against both "08" and "09".
#
# No top-level `set -e`, deliberately, same reasoning as devpause-sweep.sh:
# one section's uci get/set failing shouldn't cancel the sweep for every
# other section this tick. uci commit/fw4 reload failures are explicitly
# logged rather than silently swallowed.

HOUR="$(date -u +%H)"
if [ "$HOUR" -ge 21 ] || [ "$HOUR" -lt 7 ]; then
  WANT=1
else
  WANT=0
fi

CHANGED=0
for id in $(uci show firewall | grep "\.name='bedtime-" | sed -n "s/^firewall\.\([^.]*\)\.name=.*/\1/p"); do
  current=$(uci -q get "firewall.${id}.enabled")
  if [ "$current" != "$WANT" ]; then
    # uci set's own exit status is checked here (code review finding) — unlike the
    # unconditional CHANGED=1 this replaced, a failed set (stuck lock, bad id, read-only
    # overlay) is now explicitly logged rather than silently claimed as a transition that
    # didn't actually happen. Self-heals either way on the next tick (current will still
    # differ from WANT), but the log line should tell the truth about what happened this
    # tick — same discipline the uci commit/fw4 reload checks below already apply.
    if uci set "firewall.${id}.enabled=${WANT}"; then
      logger -t bedtime-sweep "firewall.${id}: enabled ${current:-<unset>} -> ${WANT} (UTC hour ${HOUR})"
      CHANGED=1
    else
      logger -t bedtime-sweep "ERROR: uci set failed for firewall.${id} (enabled -> ${WANT}); will retry next tick"
    fi
  fi
done

if [ "$CHANGED" = "1" ]; then
  if uci commit firewall; then
    if ! fw4 reload >/dev/null 2>&1; then
      logger -t bedtime-sweep "ERROR: fw4 reload failed after updating bedtime rule enabled state"
    fi
  else
    logger -t bedtime-sweep "ERROR: uci commit firewall failed after updating bedtime rule enabled state"
  fi
fi
