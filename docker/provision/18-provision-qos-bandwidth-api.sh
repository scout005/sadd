#!/bin/sh
# Deploys docker/provision/lib/qos-bandwidth-sweep.sh (the tracked source
# of truth for the per-device bandwidth accumulation sweep) onto a running
# OpenWrt VM as /usr/bin/qos-bandwidth-sweep.sh, seeds a cron entry that
# runs it every 5 minutes, verifies crond is genuinely running, then
# deploys and verifies docker/provision/www/api/qos-bandwidth.
#
# Deliberately NOT under docker/provision/www/ for the sweep script (same
# reasoning as 13-provision-devpause-api.sh's devpause-sweep.sh and
# 15-provision-bedtime-api.sh's bedtime-sweep.sh): that whole subtree gets
# generically copied onto the VM's web-servable /www/cgi-bin/ by
# 02-copy-www.sh, and this script is a plain cron job, not an
# HTTP-servable CGI endpoint. docker/provision/lib/ has no such exposure.
#
# Critical gotcha this script works around (confirmed live in
# docker/facts.md Section 13, by reading /etc/init.d/cron directly):
# `/etc/init.d/cron start`'s own start_service() does
# `[ -z "$(ls /etc/crontabs/)" ] && return 1` — if /etc/crontabs/ is empty,
# it silently no-ops (returns exit 0 from the init script anyway; procd
# reports success regardless), and crond never actually starts. So this
# script always seeds /etc/crontabs/root with a real line BEFORE calling
# `/etc/init.d/cron start`, then independently verifies with `pgrep crond`
# rather than trusting the init script's own exit code.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/18-provision-qos-bandwidth-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/18-provision-qos-bandwidth-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/lib/qos-bandwidth-sweep.sh"

echo "=== 18-provision-qos-bandwidth-api.sh ==="

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/usr/bin/qos-bandwidth-sweep.sh ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "${SSH_TARGET}:/usr/bin/qos-bandwidth-sweep.sh"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /usr/bin/qos-bandwidth-sweep.sh && ls -la /usr/bin/qos-bandwidth-sweep.sh"

echo "Ensuring /etc/qos-bandwidth/ exists on the VM..."
ssh_run "mkdir -p /etc/qos-bandwidth"

echo "Seeding /etc/crontabs/root with a every-5-minutes entry (idempotent — grep -qF guards against a duplicate line on re-run)..."
ssh_run "mkdir -p /etc/crontabs && (grep -qF '/usr/bin/qos-bandwidth-sweep.sh' /etc/crontabs/root 2>/dev/null || echo '*/5 * * * * /usr/bin/qos-bandwidth-sweep.sh' >> /etc/crontabs/root) && cat /etc/crontabs/root"

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

echo "=== 18-provision-qos-bandwidth-api.sh: sweep half done. Now deploying the /api/qos-bandwidth endpoint itself. ==="

OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
API_SRC_FILE="${SCRIPT_DIR}/www/api/qos-bandwidth"

if [ ! -f "${API_SRC_FILE}" ]; then
  echo "ERROR: ${API_SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
ssh_run "mkdir -p /www/cgi-bin/api"

echo "Copying ${API_SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/qos-bandwidth ..."
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${API_SRC_FILE}" \
  "${SSH_TARGET}:/www/cgi-bin/api/qos-bandwidth"

echo "Making it executable..."
ssh_run "chmod +x /www/cgi-bin/api/qos-bandwidth && ls -la /www/cgi-bin/api/qos-bandwidth"

echo "Verifying: GET http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/qos-bandwidth returns a JSON array..."
BODY="$(curl -s "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/qos-bandwidth")"
echo "Response: ${BODY}"

case "${BODY}" in
  \[*\])
    echo "OK: /api/qos-bandwidth returns a JSON array shape."
    ;;
  *)
    echo "ERROR: expected a JSON array (e.g. [] or [{...}]), got: ${BODY}" >&2
    exit 1
    ;;
esac

echo "=== 18-provision-qos-bandwidth-api.sh done: qos-bandwidth-sweep.sh deployed, cron seeded (*/5 * * * *), crond confirmed running, /api/qos-bandwidth deployed and verified. ==="
