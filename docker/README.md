# Real OpenWrt in Docker

A real OpenWrt 23.05.5 (x86-64) instance, booted with KVM-accelerated QEMU,
reachable from the host for LuCI, SSH, and (once later tasks build it) a
small `/api/*` backend the frontend prototype talks to. See
`docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` for
the full design and `docs/superpowers/plans/2026-08-30-openwrt-integration-wave1.md`
for the implementation plan this environment supports.

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

# 5. Verify.
curl -s http://localhost:8081/cgi-bin/api/ping     # -> {"ok":true}
curl -sI http://localhost:8081/cgi-bin/api/ping    # -> Content-Type: application/json among the headers
curl -sI http://localhost:8081/                    # -> 200 OK, serving sadd-website.html
curl -sI http://localhost:8081/cgi-bin/luci/       # -> reachable (403 login-required, not 404)
curl -s http://localhost:8081/cgi-bin/api/devices  # -> JSON array of current DHCP leases (empty `[]` until a real client has a lease — see "Getting a real device onto the lease list" below)
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
