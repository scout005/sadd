#!/bin/sh
# Deploys docker/provision/lib/bedtime-sweep.sh (the tracked source of
# truth for the per-device Bedtime enforcement sweep) onto a running OpenWrt
# VM as /usr/bin/bedtime-sweep.sh, seeds a cron entry that runs it every 5
# minutes, and verifies crond is genuinely running afterward.
#
# Deliberately NOT under docker/provision/www/ (same reasoning as
# 13-provision-devpause-api.sh's own devpause-sweep.sh deploy): that whole
# subtree gets generically copied onto the VM's web-servable
# /www/cgi-bin/ by 02-copy-www.sh, and this script is a plain cron job, not
# an HTTP-servable CGI endpoint — living under www/ would make a normal
# re-run of step 2 also deposit an unrequested, unexecutable second copy at
# /www/cgi-bin/lib/bedtime-sweep.sh, sitting under uhttpd's docroot for no
# reason. docker/provision/lib/ (a sibling of the numbered scripts, not of
# www/) has no such exposure.
#
# This is the baseline-state half of the Bedtime feature — real
# device-bedtime rule CREATION is a separate task's job
# (/cgi-bin/api/device-bedtime, not yet built when this script was
# written); this script only provisions the sweep that reconciles each
# existing `bedtime-<mac>` uci firewall rule's `enabled` option to match
# whether the current UTC hour falls in the fixed 21:00-07:00 window. It
# was written and proven safe to run before that endpoint exists — the
# sweep has nothing to reconcile until something starts creating rules,
# and ordering doesn't matter (same "provision the enforcement half first,
# safe to run standalone" precedent as devpause-sweep.sh) — mirroring
# 13-provision-devpause-api.sh's own sweep-half shape exactly, minus the
# endpoint-deploy half this script doesn't yet have anything to deploy.
#
# Critical gotcha this script works around (confirmed live in
# docker/facts.md Section 13, by reading /etc/init.d/cron directly):
# `/etc/init.d/cron start`'s own start_service() does
# `[ -z "$(ls /etc/crontabs/)" ] && return 1` — if /etc/crontabs/ is empty,
# it silently no-ops (returns exit 0 from the init script anyway; procd
# reports success regardless), and crond never actually starts. So this
# script always seeds /etc/crontabs/root with a real line BEFORE calling
# `/etc/init.d/cron start`, then independently verifies with `pgrep crond`
# rather than trusting the init script's own exit code. In practice cron
# should already be running by the time this step runs (Wave 5's
# 13-provision-devpause-api.sh seeds its own crontab entry and starts cron
# first), but this script checks `pgrep crond` defensively anyway rather
# than assuming — same discipline as 13's own verification.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/15-provision-bedtime-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/15-provision-bedtime-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/lib/bedtime-sweep.sh"

echo "=== 15-provision-bedtime-api.sh ==="

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/usr/bin/bedtime-sweep.sh ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "${SSH_TARGET}:/usr/bin/bedtime-sweep.sh"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /usr/bin/bedtime-sweep.sh && ls -la /usr/bin/bedtime-sweep.sh"

echo "Seeding /etc/crontabs/root with a every-5-minutes entry (idempotent — grep -qF guards against a duplicate line on re-run)..."
ssh_run "mkdir -p /etc/crontabs && (grep -qF '/usr/bin/bedtime-sweep.sh' /etc/crontabs/root 2>/dev/null || echo '*/5 * * * * /usr/bin/bedtime-sweep.sh' >> /etc/crontabs/root) && cat /etc/crontabs/root"

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

echo "=== 15-provision-bedtime-api.sh: sweep half done. Now deploying the /api/device-bedtime endpoint itself. ==="

# Deploys docker/provision/www/api/device-bedtime (the tracked source of
# truth for the /api/device-bedtime endpoint) onto the VM and verifies GET
# returns the correct "no schedule configured" shape for a MAC with no
# bedtime rule — same idiom as 13-provision-devpause-api.sh's own
# deploy-and-verify block for /api/device-pause (a dedicated, self-contained
# step even though 02-copy-www.sh already copies everything under
# docker/provision/www/ generically), since this endpoint's verification GET
# is a real, safe read (never mutates anything).
OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
API_SRC_FILE="${SCRIPT_DIR}/www/api/device-bedtime"

if [ ! -f "${API_SRC_FILE}" ]; then
  echo "ERROR: ${API_SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
ssh_run "mkdir -p /www/cgi-bin/api"

echo "Copying ${API_SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/device-bedtime ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${API_SRC_FILE}" \
  "${SSH_TARGET}:/www/cgi-bin/api/device-bedtime"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /www/cgi-bin/api/device-bedtime && ls -la /www/cgi-bin/api/device-bedtime"

echo "Verifying: GET http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/device-bedtime?mac=11:22:33:44:55:66 reports no schedule configured for a MAC with no bedtime rule..."
BODY="$(curl -s "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/device-bedtime?mac=11:22:33:44:55:66")"
echo "Response: ${BODY}"

if [ "${BODY}" = '{"enabled":false,"active":false}' ]; then
  echo "OK: /api/device-bedtime reports no schedule configured, as expected."
else
  echo "ERROR: expected {\"enabled\":false,\"active\":false}, got: ${BODY}" >&2
  exit 1
fi

echo "=== 15-provision-bedtime-api.sh done: bedtime-sweep.sh deployed, cron seeded (*/5 * * * *), crond confirmed running, /api/device-bedtime deployed and verified. ==="
