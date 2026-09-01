# Real OpenWrt in Docker

A real OpenWrt 23.05.5 (x86-64) instance, booted with KVM-accelerated QEMU,
reachable from the host for LuCI, SSH, and a small `/api/*` backend the
frontend prototype talks to (six screens/sections wired to it so far, across
three completed waves — Devices/Firewall & Ports, About/Diagnostics & Logs,
Settings/Guest Wi-Fi). See
`docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` for
the full design/roadmap and `docs/superpowers/plans/2026-08-30-openwrt-integration-wave1.md`,
`docs/superpowers/plans/2026-08-31-openwrt-integration-wave2.md`, and
`docs/superpowers/plans/2026-08-31-openwrt-integration-wave3.md` for the
implementation plans this environment supports.

## Quick start

```bash
# One-time: download and prepare the OpenWrt disk image (gitignored — not
# committed, ~120MB; safe to re-run, it's a no-op if boot.img already exists)
bash docker/fetch-boot-image.sh

cd docker
docker compose up -d --build
```

Then:
- http://localhost:8081/ — before running the Provisioning steps below,
  this is OpenWrt's stock landing page (redirects to `cgi-bin/luci/`); once
  Provisioning step 3 has run, this serves `sadd-website.html` instead —
  LuCI is still reachable at `cgi-bin/luci/` directly either way, it just
  loses the auto-landing redirect from `/` (see "Why `/cgi-bin/api/ping`
  and not `/api/ping`" below for the docroot layout).
- SSH: `ssh root@localhost -p 2223` (no password set yet on a fresh image —
  OpenWrt prompts you to set one on first LuCI/SSH login)

Give it ~10-15 seconds after `docker compose up -d` for the kernel to boot
and services to start before the ports respond.

Tear down: `docker compose down` (add `-v` to also drop the named volume,
if one is in use — the current setup doesn't use one, state lives only in
the mounted `boot.img`, so `docker compose down` alone is enough for a
clean stop; deleting `boot-image/boot.img` and re-running `fetch-boot-image.sh`
gets you back to a completely fresh, unconfigured OpenWrt).

## How it works

```
docker compose up
        │
        ▼
Dockerfile.qemu-direct (debian:bookworm-slim + qemu-system-x86 + iproute2 + socat)
        │  entrypoint.sh:
        │  1. creates a tap device (tap0) in this container's network namespace
        │  2. assigns it 192.168.1.2/24 — the same subnet as OpenWrt's default
        │     br-lan (192.168.1.1), so the two are direct L2 neighbors
        │  3. starts socat relays: container:80 → 192.168.1.1:80,
        │     container:22 → 192.168.1.1:22
        │  4. execs qemu-system-x86_64, KVM-accelerated, disk = /boot.img
        │     (bind-mounted from docker/boot-image/boot.img), networking =
        │     the tap0 device (not QEMU's usermode/slirp NAT)
        ▼
Real OpenWrt kernel boots, br-lan comes up at 192.168.1.1 (its own static
default — OpenWrt never runs a DHCP client on its LAN interface)
        │
        ▼
docker-compose's `ports: 8081:80 / 2223:22` maps the host to this
container's own port 80/22 (where socat is listening), which relays
onward to the guest's real 192.168.1.1 over the tap link.
```

## Why this specific setup (not the two things tried first)

Two other approaches were tried and abandoned — both are documented in
detail, with exact error messages and root causes, in the design spec's
"Environment bring-up: findings from a live investigation" section:

1. **`qemux/qemu` generic wrapper** (this repo's original stub) — hit a
   benign-but-fatal gzip extraction bug on the official OpenWrt image, and
   even after working around that, its disk-boot logic couldn't boot a
   pre-built (non-installer) raw disk image correctly.
2. **`albrechtloh/openwrt-docker`** (purpose-built for OpenWrt specifically,
   including a documented `LAN_IF: veth` mode for exactly this
   no-physical-NIC scenario) — correctly detects KVM, but its container
   self-discovery step (`nsenter --target 1 --mount docker inspect ...`)
   requires a `docker` CLI binary to exist in the *true* host's root
   filesystem. That's true on a normal Linux Docker host (confirmed via
   the project's own issue tracker: the one case where this broke on
   native Linux was traced to Docker having been installed via `snap`,
   whose confinement hides the binary the same way — the actual maintainer
   fix was "install Docker via the normal apt method instead of snap").
   Docker Desktop's host namespace is a minimal, purpose-built LinuxKit VM
   that was never going to have a `docker` binary in it at all — this
   isn't a workaround-able config issue, it's an architectural mismatch
   with Docker Desktop specifically.

Also ruled out along the way: plain QEMU usermode/slirp networking
(`-netdev user,hostfwd=...`) genuinely cannot reach a router guest's own
address — slirp only forwards to whatever private address *it* hands the
guest (e.g. `10.0.2.15`), and OpenWrt's `br-lan` never requests one; it
just self-assigns `192.168.1.1` regardless. The tap-device approach above
is the minimum needed to give the guest's own chosen address a real,
reachable presence in the container's network namespace.

## Provisioning

The VM's own disk (`boot-image/boot.img`) is a running, mutable state, not
a durable/reviewable artifact — it's gitignored, and `docker compose down`
followed by deleting and re-fetching `boot.img` wipes it back to a bare,
unconfigured OpenWrt (see "Known limitations" below). Anything installed
or written by hand over SSH needs to be re-applied after that. The
`docker/provision/` scripts capture exactly that: what to run, in order,
against a fresh VM to get from a bare boot to a VM with the `/api/*`
backend ready.

**Important environmental fact these scripts work around:** this VM has no
WAN interface (see "Known limitations" below), so it has **no outbound
internet route at all** — `opkg update`/`opkg install <name>` genuinely
fail from inside the VM for every package, confirmed live (`opkg update`
fails with "Network unreachable" for every feed; `opkg install <name>`
then fails with "Unknown package" because there's no cached package list
to resolve names against). Because of this, `docker/provision/01-install-api-packages.sh`
runs on the **host** (which does have internet), not piped into an SSH
session on the VM — it downloads the two small `.ipk` files the VM needs
from the official OpenWrt feed, sha256-verifies them, copies them onto the
VM over `scp`, and only then runs `opkg install` there, against the local
files (which needs no network on the VM side).

After `docker compose up -d --build` (and the container has reported
`healthy`), run, from the repo root:

```bash
# 1. Install the Lua interpreter the CGI endpoint needs (see the script's
#    own header comment for exactly why uhttpd-mod-lua wasn't used and why
#    this can't just be `ssh ... opkg install lua`).
bash docker/provision/01-install-api-packages.sh

# 2. Copy the tracked API scripts onto the VM's CGI directory and make
#    them executable (this repo has core.filemode=false, so git does not
#    track the executable bit on these files — see the script's header
#    comment — so it's set explicitly on the VM after every copy).
bash docker/provision/02-copy-www.sh

# 3. Copy the frontend prototype (repo root's sadd-website.html) onto the
#    VM's docroot as index.html, so the VM's own uhttpd serves it at `/`.
bash docker/provision/03-copy-frontend.sh

# 4. Deploy the /api/devices endpoint (real DHCP-lease-backed device list)
#    and verify it responds with a JSON array. Self-contained/idempotent —
#    also re-runnable on its own against an already-provisioned VM.
bash docker/provision/04-provision-devices-api.sh

# 5. Deploy the /api/firewall-rules endpoint (real GET/POST/DELETE against
#    this VM's own UCI firewall config + fw4/nftables) and verify it
#    responds with a JSON array. Self-contained/idempotent, same pattern
#    as step 4.
bash docker/provision/05-provision-firewall-api.sh

# 6. Deploy the /api/system-info endpoint (real ubus-backed distro/
#    hardware/uptime info for the About screen) and verify it responds
#    with a JSON object. Self-contained/idempotent, same pattern as steps
#    4 and 5.
bash docker/provision/06-provision-system-info-api.sh

# 7. Deploy the /api/logs endpoint (real logread-backed recent-activity
#    log for the Diagnostics & Logs screen) and verify it responds with a
#    JSON array. Self-contained/idempotent, same pattern as steps 4-6.
bash docker/provision/07-provision-logs-api.sh

# 8. Create the baseline wireless config (this VM has NO wireless config at
#    all on a fresh boot — no wireless hardware for OpenWrt to have
#    auto-detected; see docker/facts.md Section 11) and deploy the
#    /api/wifi endpoint (real UCI-backed SSID + guest-network on/off state
#    for the Settings/Guest Wi-Fi screens) and verify it responds with a
#    JSON object. Idempotent AND self-healing (safe to re-run against an
#    already-configured VM — each section is checked for completeness via a
#    field-by-field readback, not just existence), unlike steps 4-7 this one
#    also creates real VM state, not just a stateless endpoint. If a section
#    is ever found partially/incorrectly configured (e.g. left behind by a
#    prior run that failed partway through), it's reverted (`uci revert
#    wireless`) and recreated rather than left broken and silently skipped
#    forever — same rollback-on-failure pattern as step 5's
#    /api/firewall-rules endpoint.
bash docker/provision/08-provision-wifi-api.sh

# 9. Create a baseline DNS ad-blocklist (this VM has NO dnsmasq confdir/
#    blocklist config at all on a fresh boot; see docker/facts.md Section 12)
#    via dnsmasq's own `confdir` mechanism (no new opkg package needed) and
#    deploy the /api/adblock endpoint (real dnsmasq-log-backed
#    enabled/blockedThisWeek state for the Ad Blocking screen) and verify it
#    responds with a JSON object. Idempotent AND self-healing, same pattern
#    as step 8: the blocklist file's content is checked byte-for-byte
#    (not just "does it exist") and both uci options are read back and
#    compared against their expected values; an incomplete/stale config
#    (e.g. left behind by a prior run, or a hand-edited file missing a
#    domain) is reverted (`uci revert dhcp`) and recreated rather than left
#    broken and silently skipped forever — same rollback-on-failure pattern
#    as steps 5 and 8. Also runs a genuine functional check every time (not
#    just after a fresh create): a real `nslookup doubleclick.net 127.0.0.1`
#    over SSH, confirmed to resolve to `0.0.0.0` — real proof the
#    confdir/logqueries/restart pipeline is actually in effect, not just
#    that uci claims it is.
bash docker/provision/09-provision-adblock-api.sh

# 10. Verify.
curl -s http://localhost:8081/cgi-bin/api/ping     # -> {"ok":true}
curl -sI http://localhost:8081/cgi-bin/api/ping    # -> Content-Type: application/json among the headers
curl -sI http://localhost:8081/                    # -> 200 OK, serving sadd-website.html
curl -sI http://localhost:8081/cgi-bin/luci/       # -> reachable (403 login-required, not 404)
curl -s http://localhost:8081/cgi-bin/api/devices  # -> JSON array of current DHCP leases (empty `[]` until a real client has a lease — see "Getting a real device onto the lease list" below)
curl -s http://localhost:8081/cgi-bin/api/firewall-rules  # -> JSON array of current port-forward rules (empty `[]` on a fresh VM)
curl -s http://localhost:8081/cgi-bin/api/system-info  # -> JSON object of real distro/hardware/uptime info, e.g. {"distribution":"OpenWrt","version":"23.05.5","revision":"r24106-10cc5fcd00","target":"x86/64","model":"QEMU Standard PC (i440FX + PIIX, 1996)","kernel":"5.15.167","uptime":117}
curl -s http://localhost:8081/cgi-bin/api/logs  # -> JSON array (newest-first, capped at 30) of real logread lines, e.g. [{"timestamp":"Mon Aug 31 15:18:55 2026","message":"authpriv.info dropbear[2232]: Exit (root) from <192.168.1.2:60990>: Disconnect received"}, ...]
curl -s http://localhost:8081/cgi-bin/api/wifi  # -> JSON object of real UCI wireless state, e.g. {"ssid":"Smith Family","guestEnabled":false}
curl -s http://localhost:8081/cgi-bin/api/adblock  # -> JSON object of real dnsmasq-blocklist state, e.g. {"enabled":true,"blockedThisWeek":4} — blockedThisWeek increases by exactly 1 per subsequent real blocked lookup (e.g. `ssh root@localhost -p 2223 nslookup doubleclick.net 127.0.0.1`), confirmed live
```

**Step 3 in detail — overwriting the stock landing page is intentional:**
`uhttpd.main.home='/www'` (confirmed in `docker/facts.md`), and a stock
OpenWrt image already ships `/www/index.html` there as a small redirect
page to `cgi-bin/luci/`. `docker/provision/03-copy-frontend.sh` copies
`sadd-website.html` over that same path (`/www/index.html`), so visiting
`http://localhost:8081/` now serves the frontend prototype instead of the
auto-redirect. This was confirmed to be an acceptable tradeoff for this
dev/test VM: LuCI itself is untouched and still fully reachable directly
at `/cgi-bin/luci/` (returns a real login page, not a 404) — the only
thing lost is the auto-landing convenience redirect from `/`. The existing
`/www/cgi-bin/` directory (LuCI's CGI dispatcher plus the `/api/*`
scripts from Task 3) is a sibling directory and is not touched by this
script.

All three scripts accept `OPENWRT_HOST`/`OPENWRT_PORT` env var overrides if
you've remapped the compose ports; they default to `localhost`/`2223`,
matching this repo's `docker-compose.yml`.

**Why `/cgi-bin/api/ping` and not `/api/ping`:** `uci show uhttpd` on this
VM confirms `uhttpd.main.home='/www'` (the docroot) and
`uhttpd.main.cgi_prefix='/cgi-bin'` (uhttpd's built-in CGI dispatch
prefix under that docroot). `/www/cgi-bin/` already exists on a stock
image — the `luci` CGI dispatcher lives there — so
`docker/provision/www/` mirrors the *contents* of that directory
(currently just `api/ping`) and gets copied to `/www/cgi-bin/`
specifically, as a sibling of `luci`, not a replacement for it.

**Files:**
- `docker/provision/01-install-api-packages.sh` — side-loads a Lua
  interpreter (`lua` + its `liblua5.1.5` dependency) onto the VM.
- `docker/provision/02-copy-www.sh` — copies `docker/provision/www/` onto
  the VM's `/www/cgi-bin/` and chmods any CGI scripts executable.
- `docker/provision/www/api/ping` — the tracked source of truth for the
  `/api/ping` endpoint (a `#!/usr/bin/lua` CGI script using uhttpd's
  built-in CGI support — no extra uhttpd package needed for this). The
  copy living on the VM's disk is just where it happens to currently run;
  this file is what to edit.
- `docker/provision/03-copy-frontend.sh` — copies the repo root's
  `sadd-website.html` onto the VM as `/www/index.html`, so the VM's own
  uhttpd serves the frontend prototype at `http://localhost:8081/`. The
  repo root's `sadd-website.html` is the tracked source of truth; this
  script just re-copies it onto the VM's (untracked, gitignored) disk
  state after a fresh boot.
- `docker/provision/04-provision-devices-api.sh` — copies (and chmods,
  and curl-verifies) `docker/provision/www/api/devices` onto the VM's
  `/www/cgi-bin/api/devices`. A dedicated, self-contained step even
  though `02-copy-www.sh` already copies everything under
  `docker/provision/www/` generically (this file included) — see the
  script's own header comment for why.
- `docker/provision/www/api/devices` — the tracked source of truth for
  the `/api/devices` endpoint: parses `/tmp/dhcp.leases` into
  `{hostname, ip, mac, leaseExpires, online}` entries (`online` comes from
  cross-referencing each lease's own IP against `/proc/net/arp` — keyed by
  IP, not MAC, since every test client sharing tap0's one hardware MAC
  with the container's own relay address would otherwise collide with it;
  see the script's own header comment) and prints
  them as a JSON array. Hand-builds its JSON (with a defensive escaper)
  rather than installing `lua-cjson` — see the script's own header
  comment for the reasoning. Excludes the container's own static tap-relay
  address (`192.168.1.2`, see `docker/facts.md` Section 9) — moot in
  practice since that address is never DHCP-issued and this endpoint only
  ever iterates real lease-file lines, but a defensive IP-string check is
  in there too.
- `docker/provision/05-provision-firewall-api.sh` — copies (and chmods,
  and curl-verifies) `docker/provision/www/api/firewall-rules` onto the
  VM's `/www/cgi-bin/api/firewall-rules`. Same dedicated-step rationale as
  `04-provision-devices-api.sh`.
- `docker/provision/www/api/firewall-rules` — the tracked source of truth
  for the `/api/firewall-rules` endpoint: `GET` lists this VM's real
  `config redirect` (port-forward) sections (parsed from `uci show
  firewall`) as `[{id, name, proto, src_dport, dest_ip, dest_port}, ...]`;
  `POST` hand-parses a small flat JSON body (`{name, proto, src_dport,
  dest_ip, dest_port}` — no `lua-cjson`, see the script's own header
  comment), validates it, `uci add`s a new `redirect` section, immediately
  `uci rename`s it to a stable generated id (`fwd_<unix-time>_<6 hex
  chars>`, per `docker/facts.md` Section 4's recommendation — anonymous
  `@redirect[N]` indices shift when other rules are deleted), sets its
  fields (**`src` is hardcoded to `'wan'`** — see "Real connectivity test"
  below for why), `uci commit`s, and reloads live via `/etc/init.d/firewall
  reload`; `DELETE` (id from `PATH_INFO` or `?id=`) removes that section by
  its stable name the same way. Every value that reaches a shell command
  is quoted defensively (`shell_quote()`); the DELETE id is additionally
  restricted to `[%w_]+` and checked to actually be a `redirect` section
  before deletion.
- `docker/provision/06-provision-system-info-api.sh` — copies (and chmods,
  and curl-verifies) `docker/provision/www/api/system-info` onto the VM's
  `/www/cgi-bin/api/system-info`. Same dedicated-step rationale as
  `04-provision-devices-api.sh`.
- `docker/provision/www/api/system-info` — the tracked source of truth for
  the `/api/system-info` endpoint: shells out to `ubus call system board`
  and `ubus call system info` (already present on a stock OpenWrt image —
  no new opkg package needed) and returns a flat
  `{distribution, version, revision, target, model, kernel, uptime}`
  object shaped for the About screen. Both `ubus call` commands' output
  shapes were confirmed live against this VM before writing the endpoint
  (`docker/facts.md` Section 7 captured them first; re-confirmed via a
  fresh SSH session during this task, values matched field-for-field).
  Since every field this endpoint needs is a top-level-unique key in one
  command's known, fixed output, field extraction uses plain
  `string.match` patterns anchored on `"key":` rather than a general JSON
  parser (unlike `firewall-rules`, which does carry a small parser — but
  that one has to accept an *arbitrary* client-supplied POST body, a
  genuinely different problem) — see the script's own header comment for
  the full reasoning. Hand-builds its response JSON (with the same
  defensive escaper as `devices`/`firewall-rules`) rather than installing
  `lua-cjson`, for the same no-outbound-internet reason.
- `docker/provision/07-provision-logs-api.sh` — copies (and chmods, and
  curl-verifies) `docker/provision/www/api/logs` onto the VM's
  `/www/cgi-bin/api/logs`. Same dedicated-step rationale as
  `04-provision-devices-api.sh`.
- `docker/provision/www/api/logs` — the tracked source of truth for the
  `/api/logs` endpoint: shells out to `logread -l 30` (`logread`'s own
  built-in tail-style line cap — confirmed live via `logread --help`,
  confirmed to behave identically to `logread | tail -n 30`) and returns a
  JSON array of `{timestamp, message}` entries for the Diagnostics & Logs
  screen's "Recent activity" list. The real, live-confirmed `logread`
  output format is an asctime-style datetime prefix (weekday, month, day,
  `HH:MM:SS`, year) followed by `<facility>.<severity> <tag>[optional
  [pid]]: <message>`, e.g. `Mon Aug 31 15:16:32 2026 authpriv.info
  dropbear[2185]: Exit (root) from <192.168.1.2:50572>: Disconnect
  received` — confirmed directly over SSH during this task, not assumed
  from generic syslog conventions. Only the fixed-width datetime prefix is
  split out into its own field; the facility/tag/message remainder is kept
  as one `message` string, since that boundary isn't unambiguous in
  general (message text itself can and does contain further colons) — see
  the script's own header comment for the full reasoning, the same
  "don't force a shape reality doesn't support" judgment call
  `system-info` documents for its own field extraction. `logread` always
  emits oldest-first; this endpoint reverses its capped output to
  newest-first to match the `advlogs` screen's existing static
  `.tech-row` list ordering (most-recent-activity-first), so Task 4's
  frontend wiring doesn't need to re-sort. Hand-builds its response JSON
  (with the same defensive escaper as `devices`/`firewall-rules`/
  `system-info`) rather than installing `lua-cjson`, for the same
  no-outbound-internet reason.
- `docker/provision/08-provision-wifi-api.sh` — unlike 04-07, this step
  does two things: (1) creates a baseline `/etc/config/wireless` on the VM
  over SSH (this VM has none at all on a fresh boot — see
  `docker/facts.md` Section 11 — so there's nothing to just copy/read the
  way firewall/system-info/logs had real underlying state already);
  (2) copies (and chmods, and curl-verifies)
  `docker/provision/www/api/wifi` onto the VM's `/www/cgi-bin/api/wifi`.
  Idempotent and self-healing: each section (`radio0`, `default_radio0`,
  `guest`) is skipped only if it already exists AND every one of its
  expected fields reads back correctly via `uci get
  wireless.<section>.<option>` — a bare `uci get wireless.<section>`
  succeeding (mere existence) is not enough, since that would also match a
  half-configured section left behind by a prior run that died partway
  through its own `uci set` sequence, and would then skip re-creating it
  forever. When a section exists but fails that completeness check, its
  uncommitted changes are reverted (`uci revert wireless`) and it's
  recreated from scratch, verified again, and only committed once complete
  (one retry, then a loud failure with a revert, never a silent partial
  commit) — same verify-before-commit/revert-on-failure pattern
  `docker/provision/www/api/firewall-rules` uses for its own POST handler.
  Re-running this script against an already-configured VM neither fails nor
  duplicates sections — confirmed live by running it twice in a row and
  diffing `uci show wireless` (identical, one of each section both times) —
  and re-running it against a VM with a deliberately-corrupted partial
  section correctly detects the incompleteness, reverts, and re-establishes
  the full correct config instead of leaving it stuck broken.
- `docker/provision/www/api/wifi` — the tracked source of truth for the
  `/api/wifi` endpoint: `GET` reads `uci get wireless.default_radio0.ssid`
  and `uci get wireless.guest.disabled`, returning `{ssid, guestEnabled}`
  where `guestEnabled` is `true` unless `disabled` reads exactly `'1'`
  (UCI's own disabled-option convention — absence of the option means
  enabled). Both section/option names match exactly what
  `08-provision-wifi-api.sh` creates. `POST` reads a JSON body
  `{guestEnabled: true|false}` (a minimal hand-rolled parser, same rationale
  as `firewall-rules`), sets `wireless.guest.disabled` to the inverse
  (`'0'` when `guestEnabled:true`, `'1'` when `false`), verifies the write
  before committing, `uci revert wireless` and a `Status: 500` on any
  partial failure, `Status: 400` on a missing/non-boolean `guestEnabled`,
  runs `wifi reload` (confirmed safe against this VM's phantom radio — just
  informational "not supported" lines, not a hang) after a successful
  commit, and responds with the new `{ssid, guestEnabled}` state — same
  verify-before-commit/rollback discipline as `firewall-rules`' POST
  handler. Hand-builds its response JSON (with the same defensive escaper
  as the other endpoints in this directory) rather than installing
  `lua-cjson`, for the same no-outbound-internet reason. Graceful
  degradation on `GET`: if a `uci get` fails for any reason (missing
  config/section, `uci` erroring), `ssid` falls back to `""` and
  `guestEnabled` falls back to `false` (matching the mockup's static
  "Guest network: Off" default) rather than crashing or emitting malformed
  JSON.
- `docker/provision/09-provision-adblock-api.sh` — same shape as
  `08-provision-wifi-api.sh`: (1) creates a baseline DNS blocklist on the VM
  over SSH (this VM has no dnsmasq `confdir`/blocklist config at all on a
  fresh boot — see `docker/facts.md` Section 12 for the confirmed live
  sequence this script uses unmodified: `mkdir -p
  /etc/dnsmasq.blocklist.d`, an `address=/<domain>/0.0.0.0` line per demo
  domain — `doubleclick.net`, `adservice.google.com`, `tracker.example.com`,
  the exact three shown in `sadd-website.html`'s `screens['adblock']`
  "This week" mini-log, confirmed by reading the actual HTML, not assumed —
  `dhcp.@dnsmasq[0].confdir` and `dhcp.@dnsmasq[0].logqueries=1` via `uci`,
  commit, `/etc/init.d/dnsmasq restart`); (2) copies (and chmods, and
  curl-verifies) `docker/provision/www/api/adblock` onto the VM's
  `/www/cgi-bin/api/adblock`. Idempotent and self-healing: the blocklist
  file's content is compared byte-for-byte against the expected three lines
  (not just "does the file exist") and both uci options are read back and
  compared against their expected values — a config left behind by a
  prior partial run, or hand-edited to drop a domain, is detected as
  incomplete rather than silently trusted. When incomplete, uncommitted
  `dhcp` changes are reverted (`uci revert dhcp`) and the whole config is
  recreated from scratch, verified again, and only committed once complete
  (one retry, then a loud failure with a revert) — same
  verify-before-commit/revert-on-failure pattern as
  `08-provision-wifi-api.sh` and `firewall-rules`' POST handler. Beyond the
  uci/file readback, this script also runs a genuine functional check every
  time it runs (not just after a fresh create): a real `nslookup
  doubleclick.net 127.0.0.1` over SSH, confirmed to return `Address:
  0.0.0.0` — real proof the confdir/logqueries/restart pipeline is actually
  in effect, not just that uci claims it is. Confirmed idempotent live by
  running it twice in a row against an already-configured VM (second run
  skips config creation entirely, logs "already exists and is complete,
  skipping", and still passes the functional nslookup check and endpoint
  redeploy/verify) and by running it against a VM with a deliberately
  stale/partial blocklist file (a leftover single-domain file from an
  earlier manual test) — correctly detected as incomplete, reverted, and
  recreated with the full three-domain content.
- `docker/provision/www/api/adblock` — the tracked source of truth for the
  `/api/adblock` endpoint: `GET` returns `{"enabled": <bool>,
  "blockedThisWeek": <int>}`. `enabled` is whether `uci get
  dhcp.@dnsmasq[0].confdir` currently equals the exact path
  `09-provision-adblock-api.sh` provisions
  (`/etc/dnsmasq.blocklist.d`) — checked live, not cached, so a
  hand-reverted or repointed config is correctly reported as disabled.
  `blockedThisWeek` counts real `logread` lines matching `config <domain>
  is 0.0.0.0` for each of the three blocklisted domains — the real, live-
  confirmed log signature `logqueries=1` produces for a blocked hit
  (`docker/facts.md` Section 12), genuinely distinct from `config error is
  REFUSED`, which is what every *other* lookup on this WAN-less VM shows
  regardless of blocking. Unlike `logs` (`logread -l 30`, capped for a short
  UI list), this endpoint runs plain `logread` with no line cap, so a count
  isn't silently truncated by unrelated log noise (dropbear session lines,
  etc.) crowding out older blocked-hit lines. Matching is a plain literal
  substring search (`string.find(line, needle, 1, true)`) rather than a
  `string.match` pattern, since the three domains are fixed known constants
  with nothing to capture — deliberately simpler than `logs`/`system-info`'s
  pattern-based field extraction, which both need capture groups for
  genuinely variable content. **"This week" is aspirational, documented as
  such in the code**: `logread`'s buffer is a small fixed-size ring, nowhere
  near a full week's history, so this counts everything currently in that
  buffer, not a true rolling 7-day count — real numbers, not guaranteed
  complete-week coverage; real week-long persistence is explicitly out of
  scope. Hand-builds its response JSON (no free-form string fields, so no
  escaper needed) rather than installing `lua-cjson`, for the same
  no-outbound-internet reason as every other endpoint in this directory.
  Graceful degradation: a failed `uci get` or `logread` degrades to
  `enabled:false` / `blockedThisWeek:0` rather than crashing or emitting
  malformed JSON.

### Real connectivity test — what it actually means in this topology

The plan this endpoint was built from originally called for a literal
"run a listener on the internal target, curl the forwarded external port
from this repo's normal shell, confirm it connects" test. **That's not
possible here**, and not for a superficial reason — `docker/facts.md`
Section 10 has the full live investigation, summarized:

- This VM has no `network.wan` interface (`docker/facts.md` Section 3).
  A `config redirect` with `src='wan'` (the only sensible default for a
  real port-forward — see the endpoint's own header comment) generates a
  correct, real DNAT rule, confirmed live in `nft list ruleset` — but fw4
  places it in a `dstnat_wan` chain nothing ever jumps into, since there's
  no wan device to gate that jump on. **Zero packets can ever reach a
  `src='wan'` rule in this VM's topology**, confirmed by direct inspection,
  not assumed.
- A `src='lan'` rule *is* reachable (traffic via the real `br-lan` device
  does get routed into `dstnat_lan`), and a manually-added one was proven,
  live, to actually intercept and DNAT a real TCP SYN packet (the
  `nft` rule's own packet counter incremented in lockstep with real
  connection attempts, and removing the rule measurably changed the
  connection's failure mode from an instant refusal to a full 3-second
  timeout). What could **not** be proven is a *complete* end-to-end
  connection, because this topology has no third, genuinely distinct
  network identity to act as a separate "internal target" — every
  throwaway test container shares the exact same network namespace as the
  `openwrt` container itself, and a DHCP-leased address from this
  environment's `busybox` image is never actually applied to an interface
  (no `/usr/share/udhcpc/default.script` present) so nothing can bind or
  listen on one. The resulting client-is-also-the-target scenario hits the
  well-known "hairpin NAT" limitation (the reply routes back locally
  instead of back through the guest for un-DNAT) — a structural property
  of this test topology, not a defect in the redirect mechanism itself.

Given that, what this endpoint's shipped verification actually is: (1) a
POST creates a real `redirect` section with `src='wan'`, confirmed via
`uci show firewall` and via the exact matching rule appearing in `nft list
ruleset`'s `dstnat_wan` chain (correct proto/port/dest, not a fabricated
or hand-typed value) — real proof the whole `uci add`/`rename`/`set`/
`commit`/reload pipeline produces genuinely correct firewall config; and
(2) `docker/facts.md` Section 10 separately documents a hand-run,
`src='lan'` live-packet test (not part of this endpoint — it always uses
`src='wan'`) proving the underlying reload/enforcement mechanism itself is
real, so if this VM ever gains a real WAN interface, the same `src='wan'`
rules this endpoint already creates would behave identically with zero
further changes.

### Getting a real device onto the lease list

A freshly-provisioned VM's `/tmp/dhcp.leases` is empty — nothing has
asked the guest's dnsmasq for a lease yet — so `/api/devices` correctly
returns `[]` until something does. `docker exec` does **not** reach the
guest (see `docker/facts.md`'s intro) and there's no separate Docker
network the guest's LAN side sits on either; what does work is attaching
a second, throwaway container directly to the `openwrt` container's own
network namespace (where `docker/entrypoint.sh`'s tap0 device lives) and
running a DHCP client on tap0 from inside it:

```bash
docker run --rm --network container:openwrt --cap-add=NET_ADMIN busybox \
  sh -c "udhcpc -i tap0 -n -q -x hostname:sadd-test-client"
```

This performs a real DORA exchange against the guest's dnsmasq using
tap0's own real hardware MAC, confirmed live to produce a real lease
(`udhcpc: lease of 192.168.1.232 obtained from 192.168.1.1 ...`) and a
matching real line in `/tmp/dhcp.leases` — see `docker/facts.md` Section
1a for the exact confirmed line and more detail. After running this,
`curl http://localhost:8081/cgi-bin/api/devices` reflects that real
device.

## Known limitations for this dev/test environment

- No physical Wi-Fi radio — this is a router with one virtual wired NIC
  only. Any Wi-Fi-related config work is at the `uci`/config level, not an
  actually-broadcasting network.
- Single interface — `eth0` is bridged into `br-lan` only; there's no
  separate WAN interface wired up yet. If a later wave needs a real
  separate WAN link, that's additional tap/network setup, not something
  this environment already provides.
- State lives only in `boot-image/boot.img`, gitignored and untracked —
  don't treat this as a durable environment; `docker compose down` followed
  by deleting and re-fetching `boot.img` gets you back to a pristine state,
  which is exactly what Task 9's full verification pass exercises.
- No end-to-end WAN packet test for firewall port-forwarding — a `src='wan'`
  redirect rule genuinely lands in a real `fw4` nftables chain (`dstnat_wan`),
  but that chain is topologically unreachable in this VM's single-interface
  setup (confirmed by exhaustive `nft list ruleset` inspection). See "Real
  connectivity test" above for what was actually proven instead (a `src='lan'`
  rule intercepting real live traffic, proving the same underlying mechanism).
- **No authentication on `/cgi-bin/api/*`**, and `docker-compose.yml` binds
  port 8081 to all interfaces, not just `localhost` — anyone reachable on
  the local network can add/delete real firewall rules, or flip the real
  guest Wi-Fi network on/off, with a plain `curl` (two independent
  write-capable endpoints as of Wave 3: `/api/firewall-rules`, `/api/wifi`).
  Acceptable only because this is an explicitly local, single-user dev/test
  tool — not something to carry into a later wave or real deployment as-is.
- The global search feature (built earlier this session, unrelated to this
  work) can't highlight search results on the Devices, Firewall & Ports
  (port-forwarding rules only), and Diagnostics & Logs screens when the
  router is reachable and responding quickly — real data overwrites the
  static demo text those search-index entries point at before the
  highlight fires. Confirmed during Wave 2's verification pass to extend
  to all of Diagnostics & Logs' "Recent activity" search entries (its
  whole log list is real-data-backed, unlike Firewall & Ports where only
  the port-forwarding rows are affected). The About screen is unaffected —
  none of its indexed search entries (App version's label, "Built on
  OpenWrt", the CVE table, pricing promise) point at the one span that
  actually goes dynamic, since only the factual version *value* is
  replaced, not any indexed label text. Settings and Guest Wi-Fi (Wave 3)
  are unaffected for the same reason, confirmed by checking the actual
  `searchIndex` entries rather than assuming: every entry pointing at those
  two screens ("Wi-Fi name & password", "Guest Wi-Fi", "Smith Guest")
  targets static label/marketing text, never the two now-dynamic spans
  (`#settingsWifiName`/`#settingsGuestStatus`) or the toggle switch/its
  description (`#guestWifiSwitch`/`#guestWifiDesc`) — search highlighting on
  both screens works correctly whether the router is reachable or not.
  Navigation still lands on the correct screen every time on every affected
  screen; only the cosmetic pulse is silently skipped, exactly matching the
  search feature's own designed "fail silently on content drift" behavior.
  Full detail in the design spec's Error Handling section.
