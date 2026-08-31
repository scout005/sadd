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
- LuCI web UI: http://localhost:8081/ (redirects to `cgi-bin/luci/`)
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
