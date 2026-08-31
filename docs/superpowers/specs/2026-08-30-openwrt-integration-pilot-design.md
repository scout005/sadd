# Real OpenWrt Integration — Design & Roadmap

## Goal

Drive as much of this prototype as genuinely can be by a real, running OpenWrt instance, instead of hardcoded demo data. The full target is documented below as a roadmap of "waves," each one a self-contained slice that gets its own implementation plan when its turn comes. **Wave 1** — the first slice actually being designed and built now — covers two screens on the desktop prototype (`sadd-website.html`): **Devices** and **Firewall & Port Forwarding**. Everything below Wave 1 in the roadmap is sequenced but not yet detailed at the same level; each wave gets its own design pass (reusing this document's architecture) immediately before it's built, since exact implementation details depend on what's actually true inside the running container by that point.

Not every screen in the app can be "real" in this sense — see **Full roadmap** below for the honest breakdown of which screens are genuinely OpenWrt-backable, which are pure UI-flow/marketing content with nothing to execute, and which are cloud/account-system features that would need an entirely different (non-router) backend.

This is a genuinely different kind of work than the rest of this repo's session history (which has been static HTML/CSS/JS editing). It involves real infrastructure (Docker, a real OpenWrt image, real `uci`/`ubus`/`nft` commands) and carries real uncertainty about exact package availability and behavior inside a containerized OpenWrt — some implementation details below are best-effort and may need to change once we're hands-on inside a running container. That's expected and fine for a pilot.

## Why this shape, not a docker-exec shim or raw ubus-from-browser

Two other approaches were considered and rejected:

- **Raw ubus/uci JSON-RPC called directly from the browser** (what LuCI itself effectively does) — technically the most "native" option, but ubus/uci's config schema is low-level OpenWrt internals, not a stable public contract. Building a product UI directly against it means a future OpenWrt version bump can silently break the frontend.
- **An external shim that `docker exec`s into the container** — fast to build, but a dead end for production: on real router hardware there is no outside host to exec into. Anything built this way is throwaway testing scaffolding, not a step toward a real product.

Instead: a small API daemon lives **inside the OpenWrt image itself**, under `uhttpd` (the same web server LuCI uses), written in Lua (OpenWrt's native scripting layer for this, `uhttpd`'s Lua/CGI handler support) or, as a fallback if Lua tooling proves too fragile inside the pilot image, a cross-compiled Go binary serving the same contract. This daemon exposes a small, clean, versioned REST API and is the only thing that shells out to `uci`/`ubus`/`nft`. The frontend never touches OpenWrt internals directly. Crucially, this exact code can run unmodified on real router hardware later — nothing here is thrown away when moving from Docker testing to a real device.

## Architecture

```
Browser (sadd-website.html, devices + advfirewall screens only)
        │  same-origin fetch('/api/...')
        ▼
uhttpd  (inside the OpenWrt container, also serves the static HTML file)
        │  routes /api/* to
        ▼
Lua API daemon (or Go fallback)
        │  shells out to
        ▼
uci / ubus / nft   (real OpenWrt config + firewall state)
        │
        ▼
Real kernel netfilter (nftables) + real dnsmasq DHCP leases,
inside the Docker container's network namespace
```

The container is started with `--cap-add=NET_ADMIN --cap-add=NET_RAW` (required for `nft` rule manipulation) and attached to two Docker networks — one standing in for "WAN," one for "LAN" — so `uci network`/`uci firewall` have two real zones to bind to, mirroring a real router's topology instead of one flat container network.

## Components

### 1. Docker/OpenWrt environment
- Base: `openwrt/rootfs` (OpenWrt's official published rootfs image), or a `Dockerfile` built from it.
- Packages needed beyond the base rootfs: `uhttpd` + Lua CGI/module support (exact package name TBD hands-on — `uhttpd-mod-lua` if available, otherwise plain Lua CGI scripts under `uhttpd-mod-cgi`, which is more universally available), `firewall4`/`nftables` (usually present by default on modern OpenWrt), `dnsmasq` (usually present by default), `lua`, `lua-cjson` (for building/parsing JSON API responses).
- Two attached networks (WAN-side, LAN-side) so the device has something resembling a real router's interface layout.

### 2. Devices API
- `GET /api/devices` → reads real DHCP lease data (dnsmasq's lease file and/or `ubus call dhcp ...` if the package exposes it) plus a liveness signal (e.g. ARP table / a quick ping), returns `[{hostname, ip, mac, online, leaseExpires}, ...]`.
- Read-only for the pilot — no device-blocking/quarantine actions wired yet (that's a natural next slice, not part of this pilot).

### 3. Firewall & Port Forwarding API
- `GET /api/firewall/rules` → reads current `uci show firewall` `redirect` (port-forward) sections, returns them as JSON.
- `POST /api/firewall/rules` → adds a new redirect section via `uci add firewall redirect` + `uci set ...` + `uci commit firewall`, then reloads (`/etc/init.d/firewall reload` or `fw4 reload`) so the change is live immediately, not just written to config.
- `DELETE /api/firewall/rules/:id` → removes the section, commits, reloads.

### 4. Frontend changes
- Only `screens['devices']` and `screens['advfirewall']` change from static HTML strings to render functions that fetch from `/api/devices` / `/api/firewall/rules` and build the row markup dynamically, reusing the exact same CSS classes (`.list-item`, `.rule-row`, etc.) the static versions already use — so this stays visually identical, just data-driven instead of hardcoded.
- Every other screen (all 46 remaining desktop screens, all 16 mobile screens) is untouched — still static demo data, exactly as it is today.
- The file is served from the container's `uhttpd` alongside the API (same origin, no CORS needed). Editing the file locally and reloading in the browser pointed at the container still works the same way it does today.

### 5. Error handling
If `/api/devices` or `/api/firewall/rules` is unreachable (e.g. the file is opened directly via `file://` outside the container, or the container isn't running), the screen falls back to today's existing static demo data and shows a small, non-blocking notice ("Can't reach router — showing demo data") rather than breaking or blanking the screen. This keeps the rest of the prototype's existing behavior (all other screens, the search feature, etc.) working exactly as before regardless of whether the container is up.

## Testing / how we'll know it's real, not just displayed

- **Devices**: attach a second, throwaway test container to the same "LAN" Docker network with a DHCP client; confirm it shows up in the real device list in the UI (hostname/IP/MAC), not just in a raw `dnsmasq` log.
- **Firewall**: add a port-forward rule through the UI; confirm the resulting `nft list ruleset` inside the container matches; then do an actual connectivity test — e.g. run a tiny listener on the internal target and `curl`/`nc` the forwarded port from outside the container — to prove the rule is genuinely enforced, then remove it through the UI and confirm the same connection now fails.

## Non-goals for this pilot

- Real Wi-Fi radios — no physical wireless hardware exists in a container; any "Wi-Fi settings" work later is config-level only (`uci get/set wireless`), not an actually-broadcasting network.
- Cloud/remote-access, multi-site "Fleet & Business," or mobile-app real-time sync — all need real cloud infrastructure, out of scope here.
- Real VLAN trunking across physical switch ports — a container can only demonstrate the `uci network`/bridge/8021q config semantics, not physical trunk behavior.
- Any auth/session model beyond a single shared admin session for the pilot — proper multi-user RBAC (matching the product's family-profile model) is a later concern.
- Persisting the container across host reboots, or treating this as a daily-driver setup — it's a dev/test environment.
- Any screen other than `devices` and `advfirewall` becoming live — everything else keeps working exactly as it does today.

## Full roadmap: every screen, categorized

All 48 `sadd-website.html` screens, sorted into what "make it real" would actually mean for each. Mobile (`sadd-mobile-app.html`) screens are a subset of the same underlying concepts (devices, network, notifications, about) and follow whichever desktop wave covers the matching concept — not separately waved below.

### Group 1 — genuinely OpenWrt-backable (the real work), in waves

**Wave 1 (this design, building now):**
- Devices — real DHCP leases
- Firewall & Port Forwarding — real `uci`/`nft` rules

**Wave 2 (next, once Wave 1 is proven):**
- About — real OpenWrt version/board info (`ubus call system board`) — easy, high-confidence win
- Diagnostics & Logs — real `logread` output instead of fake log lines
- WAN check (onboarding step) — a real outbound connectivity test (ping/curl from the container's WAN side)
- Connection Health — real WAN interface up/down history, tracked over time via `ubus subscribe network.interface` or logread parsing

**Wave 3 (config-mutating, higher risk/complexity):**
- Settings — real Wi-Fi name (SSID) and real admin password (`uci wireless`, `uci system` / rpcd login)
- Guest Wi-Fi — real guest SSID + firewall zone config (no real broadcast, config-level only)
- Network & VLANs — real `uci network` VLAN/bridge config (container-level only, not physical trunk ports)
- Ad Blocking — real DNS blocklist (`adblock` or `https-dns-proxy` package) with real blocked-count
- Site Blocked / Block Detail — the real block-landing-page and log entry produced by the above

**Wave 4 (harder simulation, needs real generated traffic/hardware-adjacent behavior):**
- Traffic & QoS — real `tc`/SQM config; demoing actual prioritization needs real traffic flowing, hard to make compelling in a container
- Multi-WAN & Failover — real `mwan3` config; a believable failover demo needs two real WAN links and a way to fail one on purpose
- Per-Device Controls — time-based/manual per-MAC block, real but fiddly
- Parental Controls — bedtime/content-filter schedules as real time-based firewall/DNS rules, real but the most involved of this group
- VPN Server (WireGuard) — real `wireguard-tools`, generate real peer configs
- VPN Server (OpenVPN) — real `openvpn` package, generate real client configs
- Connect a Laptop (VPN) — consumes whichever VPN server above is real
- Developer & API Access — real SSH (dropbear) enable/disable toggle at minimum
- Weekly Usage — real per-device bandwidth accounting (`nlbwmon` or nft counters)
- Notifications (preference toggles) — real as stored config; actual delivery (email/webhook) is a separate, later concern

Waves 3-4 are ordered by rough complexity, not obligation — the actual order when we get there can be re-prioritized based on what's most useful to test at the time.

### Group 2 — pure UI flow / marketing content, nothing to execute

Welcome, Success, Discover, Let's Get Started (comfort level), Your Setup (topology), Advanced Settings hub, Hardware & Pricing, Which Model?, Is This Right For Me?, Networking Glossary. These stay exactly as they are — static demo/marketing content is the correct, finished state for them, not a gap.

### Group 3 — cloud/account-system features, not router firmware

Login, Signup, MFA, Save your recovery codes, Privacy, Fleet & Business (multi-site), Support Access. A router itself has no concept of "your account" — that lives in a company's cloud. Making these real means building a separate mock account/cloud backend, an unrelated project to this OpenWrt work. Not scheduled as part of this roadmap; revisit as its own design if/when it becomes a priority.

### Group 4 — physically impossible in Docker

Wi-Fi Walk-Test Results — needs real radios and someone physically walking a house with a signal meter. No container can produce this data; stays static/simulated indefinitely regardless of any backend work.

## Open questions to resolve during implementation (not blocking design approval)

- Exact `uhttpd` Lua integration package name/availability inside the container image — may require falling back to CGI-style Lua scripts instead of an in-process module.
- Exact source of DHCP lease data available inside the running OpenWrt VM (lease file path vs. an ubus-exposed call) — confirmed hands-on once the container is running.

### Environment bring-up: findings from a live investigation (2026-08-30)

Before writing the implementation plan, the boot environment itself was tested hands-on, since this repo already had a `docker/docker-compose.yml` stub. This replaces the original "run `openwrt/rootfs` as a plain userland container" idea below with a much better-grounded plan, and leaves one concrete blocker for Task 1 to resolve:

**Confirmed working:**
- Docker Desktop on this machine has KVM available to containers (`--device=/dev/kvm` works, verified directly).
- The official OpenWrt 23.05.5 x86-64 combined image, once downloaded, is a genuinely valid, bootable raw disk (confirmed via `file` → "DOS/MBR boot sector", and a full real kernel boot reaching a console prompt with `br-lan` up).
- A minimal hand-written `qemu-system-x86_64 -enable-kvm -drive file=...,format=raw ...` container (`docker/Dockerfile.qemu-direct`, committed) successfully boots this real OpenWrt kernel end-to-end. This is a proven fallback path if the options below don't pan out.

**Two real bugs found and worked around:**
1. The official OpenWrt combined `.img.gz` has benign trailing bytes after its valid gzip stream (confirmed: `gzip -dc` still produces a complete, correct, valid disk image; the trailing bytes are just data gzip's strict checker flags as a warning/exit-code-2, not actual corruption). The originally-stubbed `qemux/qemu` wrapper's own extractor treats this as a fatal error and infinite-restart-loops. Fix: pre-decompress once, bind the raw `.img` in directly (this wrapper supports that natively) — bypasses its extractor entirely.
2. Even with a valid pre-extracted raw disk bound in, that same wrapper's own disk-boot logic reports "Boot failed: not a bootable disk" — it appears designed around installer-media workflows (like Windows/macOS ISO installs onto a fresh empty disk) rather than booting a pre-built, already-complete disk image directly. Not resolved with that wrapper; abandoned in favor of the option below.

**Current best candidate, with one known blocker:** `albrechtloh/openwrt-docker` (https://github.com/AlbrechtL/openwrt-docker) is a project purpose-built for exactly this scenario — real OpenWrt kernel, KVM acceleration, and (relevant to this Windows/WSL2/Docker Desktop environment specifically) a documented `LAN_IF: "veth"` mode for exactly the "no direct physical NIC passthrough available" case. Tried directly (compose committed to `docker/docker-compose.yml`) — it correctly detects KVM and starts building its virtual networking, but its container self-discovery step (`nsenter --target 1 --mount docker inspect -f '{{.State.Pid}}' $(cat /etc/hostname)`) fails with `nsenter: failed to execute docker: No such file or directory`. This runs with `pid: "host"`, so `nsenter --target 1` enters the true host PID namespace and tries to exec a `docker` CLI binary there — which exists on a normal bare-metal Linux Docker host, but Docker Desktop's actual host namespace is a minimal purpose-built LinuxKit VM with no such binary. This is a genuine environment-specific incompatibility with Docker Desktop, not a config typo.

**RESOLVED (2026-08-31):** none of the three candidate fixes above panned out for `albrechtloh/openwrt-docker` — mounting `/var/run/docker.sock` didn't help (confirmed: `nsenter --mount` switches into the *host's* actual filesystem, where the container's own bind mounts, socket included, are no longer visible at all), and the project's own issue tracker (#32) confirmed this exact failure mode: on native Linux it was traced to Docker being installed via `snap` (whose confinement hides the `docker` binary from a plain host-namespace `nsenter` the same way), fixed there by switching to a normal apt install — no equivalent fix exists for Docker Desktop, whose host namespace is a minimal LinuxKit VM that was never going to contain a `docker` binary at all. This is a genuine architectural dead end for this project on Docker Desktop specifically, not a missing flag.

Fell back to option 3 — hand-rolled tap networking around the already-proven `docker/Dockerfile.qemu-direct` direct-QEMU path — and it worked on the first properly-configured attempt. Root cause of why plain QEMU usermode/slirp networking (the very first thing tried) couldn't work at all: slirp only forwards to whatever private address *it* assigns the guest (e.g. `10.0.2.15`); OpenWrt's `br-lan` never requests one via DHCP — it self-assigns `192.168.1.1` as a static default regardless of what the network layer offers. A tap device (`tap0`, assigned `192.168.1.2/24` — the same subnet as `br-lan`) makes the guest's own real address a direct L2 neighbor of the container, and a pair of `socat` relays (`container:80 → 192.168.1.1:80`, `container:22 → 192.168.1.1:22`) bridges that to the ports Docker exposes to the host. Verified end-to-end: `curl http://localhost:8081/` returns a real `200` serving genuine LuCI HTML ("LuCI - Lua Configuration Interface"), and the real dropbear SSH banner (`SSH-2.0-dropbear`) is reachable on the mapped SSH port — both through the exact `docker compose up -d` command documented in `docker/README.md`, from a cold start (freshly-fetched `boot.img`, freshly-built image), not just an already-running dev session.

Final setup: `docker/docker-compose.yml` builds `docker/Dockerfile.qemu-direct` (Debian + `qemu-system-x86` + `iproute2` + `socat`), whose `docker/entrypoint.sh` creates the tap device, starts the relays, then execs QEMU. `docker/fetch-boot-image.sh` reproducibly downloads and prepares the disk image (gitignored — not committed, ~120MB). Full details, exact commands, and the two abandoned approaches are in `docker/README.md`.

This replaces the design's earlier assumption of a plain `openwrt/rootfs` userland container — running the *real* OpenWrt kernel under KVM is both more authentic and, as it turned out, the path that actually works.
