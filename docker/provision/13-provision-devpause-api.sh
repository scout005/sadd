#!/bin/sh
# Deploys docker/provision/lib/devpause-sweep.sh (the tracked source of
# truth for the per-device pause auto-expiry sweep) onto a running OpenWrt
# VM as /usr/bin/devpause-sweep.sh, seeds a cron entry that runs it every
# minute, and verifies crond is genuinely running afterward.
#
# Deliberately NOT under docker/provision/www/ (code review finding): that
# whole subtree gets generically copied onto the VM's web-servable
# /www/cgi-bin/ by 02-copy-www.sh, and this script is a plain cron job, not
# an HTTP-servable CGI endpoint — living under www/ would make a normal
# re-run of step 2 also deposit an unrequested, unexecutable second copy at
# /www/cgi-bin/lib/devpause-sweep.sh, sitting under uhttpd's docroot for no
# reason. docker/provision/lib/ (a sibling of the numbered scripts, not of
# www/) has no such exposure.
#
# This is the baseline-state half of the Per-Device Controls feature: real
# device-pause CREATION is /cgi-bin/api/device-pause's job (a later task,
# not yet built here). This step only provisions the sweep that DELETES
# expired pauses — a `devpause-<mac>` uci firewall rule whose custom
# `paused_until` (epoch seconds) option has passed — so it's safe to run on
# its own, well ahead of the endpoint that creates those rules existing.
#
# Critical gotcha this script works around (confirmed live in
# docker/facts.md Section 13, by reading /etc/init.d/cron directly):
# `/etc/init.d/cron start`'s own start_service() does
# `[ -z "$(ls /etc/crontabs/)" ] && return 1` — if /etc/crontabs/ is empty,
# it silently no-ops (returns exit 0 from the init script anyway; procd
# reports success regardless), and crond never actually starts. So this
# script always seeds /etc/crontabs/root with a real line BEFORE calling
# `/etc/init.d/cron start`, then independently verifies with `pgrep crond`
# rather than trusting the init script's own exit code — same
# don't-trust-the-claimed-success-alone discipline as 08/10/11's own
# kernel-level verify layers.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/13-provision-devpause-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/13-provision-devpause-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/lib/devpause-sweep.sh"

echo "=== 13-provision-devpause-api.sh ==="

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/usr/bin/devpause-sweep.sh ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "${SSH_TARGET}:/usr/bin/devpause-sweep.sh"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /usr/bin/devpause-sweep.sh && ls -la /usr/bin/devpause-sweep.sh"

echo "Seeding /etc/crontabs/root with a every-minute entry (idempotent — grep -qF guards against a duplicate line on re-run)..."
ssh_run "mkdir -p /etc/crontabs && (grep -qF '/usr/bin/devpause-sweep.sh' /etc/crontabs/root 2>/dev/null || echo '* * * * * /usr/bin/devpause-sweep.sh' >> /etc/crontabs/root) && cat /etc/crontabs/root"

echo "Enabling and starting cron..."
ssh_run "/etc/init.d/cron enable && /etc/init.d/cron start"

echo "Verifying crond is actually running (the init script's own exit code is NOT proof — it silently no-ops if /etc/crontabs/ was empty when it ran; docker/facts.md Section 13). Since the crontab was seeded above before start, this ordering should avoid that trap, but verify anyway rather than trust it..."
if ssh_run "pgrep crond >/dev/null 2>&1"; then
  echo "OK: crond is running."
else
  echo "crond not running after start — retrying once with /etc/init.d/cron restart..." >&2
  ssh_run "/etc/init.d/cron restart"
  sleep 2
  if ssh_run "pgrep crond >/dev/null 2>&1"; then
    echo "OK: crond is running after restart."
  else
    echo "ERROR: crond still not running after restart. Investigate manually (check /etc/crontabs/root contents and /etc/init.d/cron)." >&2
    exit 1
  fi
fi

echo "=== 13-provision-devpause-api.sh done: devpause-sweep.sh deployed, cron seeded, crond confirmed running. ==="
