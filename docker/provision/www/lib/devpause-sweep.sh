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

NOW=$(date +%s)
CHANGED=0

# Find every uci firewall rule section this project created for a per-device
# pause (name starts with "devpause-"), extract just its section id, using
# only POSIX sed/grep (busybox ash, not bash/gawk — matches every other
# script in this directory's tooling assumptions).
for id in $(uci show firewall | grep "\.name='devpause-" | sed -n "s/^firewall\.\([^.]*\)\.name=.*/\1/p"); do
  paused_until=$(uci -q get "firewall.${id}.paused_until")
  if [ -n "$paused_until" ] && [ "$paused_until" -le "$NOW" ] 2>/dev/null; then
    logger -t devpause-sweep "removing expired pause: firewall.${id} (paused_until=${paused_until}, now=${NOW})"
    uci -q delete "firewall.${id}"
    CHANGED=1
  fi
done

if [ "$CHANGED" = "1" ]; then
  uci commit firewall
  fw4 reload >/dev/null 2>&1
fi
