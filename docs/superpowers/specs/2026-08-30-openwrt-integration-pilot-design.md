# Real OpenWrt Integration Pilot — Design

## Goal

Prove that this prototype can be driven by a real, running OpenWrt instance instead of hardcoded demo data — starting with two screens on the desktop prototype (`sadd-website.html`): **Devices** and **Firewall & Port Forwarding**. This is a pilot: if it works end-to-end for these two, the same pattern extends to more screens later. It is not an attempt to wire up all 48+16 screens in one pass.

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

## Open questions to resolve during implementation (not blocking design approval)

- Exact `uhttpd` Lua integration package name/availability inside the container image — may require falling back to CGI-style Lua scripts instead of an in-process module.
- Exact source of DHCP lease data available inside a minimal `openwrt/rootfs`-based image (lease file path vs. an ubus-exposed call) — confirmed hands-on once the container is running.
- Whether `openwrt/rootfs`'s bundled kernel-facing tools (`nft`, `ip`) work as expected against Docker Desktop's underlying VM kernel, or whether some capability/module needs to be added — confirmed hands-on.
