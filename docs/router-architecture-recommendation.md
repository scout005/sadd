# Router Architecture Recommendation — Built on OpenWrt
*Frontend, backend, packaging/updates, and ISP-readiness. Written for a commercial product, not a hobbyist flash.*

---

## The shape of the system

Four layers, each independently swappable:

```
[ Mobile App / Web App ]  <-- local control-plane API (LAN) --> [ Router: OpenWrt + your daemon ]
        |                                                                |
        | cloud control-plane API (internet)                            | OTA agent, telemetry, relay client
        v                                                                v
[ Cloud Backend: accounts, router registry, remote-access relay, OTA server, push ]
```

The core design rule from everything we've discussed so far: **the router must be fully controllable over the local API with zero cloud dependency.** The cloud layer is additive (remote access, multi-router, backups, updates-at-scale), never required for local operation. That single rule is what makes the offline-MFA epic, the local-first onboarding epic, and this architecture all consistent with each other.

---

## 1. On-router software (the OpenWrt base)

**Don't ship stock OpenWrt + LuCI as the product.** Build a custom image using OpenWrt's own build system (the ImageBuilder, or full Buildroot toolchain for deeper customization) that includes only what you need:

**Core OpenWrt packages to build in:**
- `dnsmasq` + `nftables` (or `iptables-nft`) — DHCP/DNS and firewall, also your enforcement point for site/category blocking and the block page (DNS-level redirect to a local block-page server for HTTP, SNI-based blocking for HTTPS)
- `hostapd` — Wi-Fi, including multiple SSIDs for guest network isolation
- `wireguard-tools` (WireGuard is already in-kernel on modern OpenWrt) — this is your remote-access VPN transport (see Cloud section)
- `adblock` or a lightweight custom equivalent — network-wide ad blocking, DNS-list based
- `https-dns-proxy` / DNS-over-HTTPS — optional, pairs well with ad/tracker blocking
- `rpcd` + `ubus` — OpenWrt's native RPC bus; this is what your own daemon talks to under the hood instead of reinventing config access

**Your own daemon (the piece you build):** a service running on-device (Go or C, both compile cleanly for OpenWrt's typical MIPS/ARM targets) that:
- Exposes a clean local REST/JSON (or gRPC) API — this is the *only* thing your apps talk to. They never call `ubus`/UCI directly.
- Translates your API calls into `ubus` calls and UCI config writes underneath
- Handles local-only concerns that don't exist in stock OpenWrt: MFA verification (TOTP validated locally, per Epic E13), parental profile logic, device-friendly-naming, block-page serving, security status scoring
- Talks to the cloud backend when internet is available (registration, sync, OTA check-in) but degrades gracefully to local-only when it isn't

This local daemon is the single most important thing to get right — it's the seam between "OpenWrt, a router OS" and "your product." Treat it as its own well-tested codebase, not a pile of shell scripts.

---

## 2. Frontend

**Don't expose LuCI (OpenWrt's stock web UI) to end users.** It's built for the exact opposite audience — technical users who want raw config access. It can still exist on the box for your own engineering/support use, but hide it entirely from the consumer product, and never present it as "Advanced mode" — Advanced mode should still be *your* UI with more exposed options, not a drop into LuCI.

**Recommended stack:**
- **Mobile app:** React Native or Flutter, single codebase for iOS/Android. Talks to the local daemon's API when on the home Wi-Fi, and to the cloud API (via the remote-access tunnel) when away — ideally the app doesn't need to know which mode it's in; the API layer should present a consistent interface regardless of transport.
- **Web dashboard:** React (or same framework family as the mobile app if you want shared components), served either locally by the router (small embedded web server) for LAN access, and by the cloud for remote access — same backend contract as the mobile app.
- Both consume the same API contract from the local daemon / cloud backend — build that API once, and don't let the mobile and web clients drift into separate backend logic.

---

## 3. Cloud backend

Four services, ideally separable so any one can be swapped or scaled independently:

**a. Account & identity service** — registration, login, MFA enrollment/verification (SMS/push/email — the ones that *do* need cloud), router-to-account linking, multi-router registry (per Epic E14).

**b. Remote-access relay** — this is the piece that makes "access my router from outside" actually work despite most home routers sitting behind NAT/CGNAT (they can't accept inbound connections). Recommended approach: an **outbound-initiated WireGuard tunnel** from the router to your relay, the same NAT-friendly pattern used by TR-069/ACS systems and by tools like Tailscale. Two realistic build choices:
   - **Self-hosted Headscale** (open-source control-plane implementation compatible with Tailscale's client) — gives you WireGuard key management, NAT traversal with relay fallback, and **ACL-based scoping already built in**, which maps directly onto your "management-only vs. full-LAN" access-scope stories (Epic E7) without you writing that logic yourself.
   - **Custom WireGuard orchestration** — more engineering effort, but full control, no third-party control-plane dependency. Reasonable if remote access becomes a core differentiator you want to own end-to-end.
   Either way: the router always initiates outbound, never accepts inbound — this keeps you consistent with the "no open inbound ports" principle already in the backlog's NFRs, and with how the future ISP/ACS layer will eventually want to reach the device too.

**c. OTA/update server** — hosts firmware images, tracks fleet versions, manages staged rollout (see below).

**d. Push notification + telemetry ingestion** — device alerts (new device joined, threat blocked) and opt-in diagnostics, scoped per the consent principle already in the backlog.

---

## 4. Packaging & updates

This is where your earlier "atomic, signed, rollback-capable" requirement gets implemented concretely.

**Recommended: RAUC** (Robust Auto-Update Controller), not OpenWrt's native `sysupgrade` alone. RAUC is a mature, widely production-deployed A/B update framework for embedded Linux — it's what runs updates on the Steam Deck, among other commercial embedded products — and gives you cleanly:
- **A/B partition slots** — update installs to the inactive partition while the device keeps running on the active one
- **Cryptographic signature verification** before any bundle is applied
- **Automatic rollback** if the new partition fails to boot successfully
- Update bundles can be delivered from your OTA server over the same outbound connection the router already maintains — no inbound exposure needed

This integrates into your custom OpenWrt build (RAUC runs alongside OpenWrt on the same Linux base) rather than replacing anything — you're adding a robust update mechanism on top of the OS you're already shipping.

**Staged rollout on the server side:** don't push a new firmware version to 100% of the fleet at once. Roll out to a small percentage first (internal devices, then a canary cohort of real users), watch for elevated failure/rollback rates, then widen. This is a server-side OTA policy, not a router-side concern — it belongs in the cloud OTA service, not the on-device agent.

---

## How this stays ready for the ISP project (without building it now)

Everything above already satisfies the architectural notes from the earlier "future consideration" document, without any extra work:
- WAN config is naturally isolated in OpenWrt's own config structure (UCI already separates `network`, `wireless`, `firewall`, etc.) — nothing to change later.
- The update mechanism (RAUC, signed, rollback-capable) is exactly the trigger surface a future TR-069/TR-369 agent would call remotely — you're not building a second update system later, just adding a new *caller*.
- The local daemon's clean API is itself the abstraction a management agent would sit behind — a future ISP integration becomes "add another authorized caller with scoped permissions," not a rearchitecture.
- The outbound-only remote-access relay pattern (WireGuard/Headscale) is the same connectivity model TR-069/TR-369 uses (device-initiated, NAT-friendly) — so the networking approach doesn't need to change either.

---

## Summary: recommended stack

| Layer | Recommendation |
|---|---|
| Base OS | OpenWrt, custom-built image (ImageBuilder/Buildroot), no stock LuCI exposed to users |
| On-device control | Custom daemon (Go) wrapping ubus/UCI, exposing one clean local REST/JSON API |
| Mobile app | React Native or Flutter |
| Web dashboard | React, served locally (LAN) and via cloud (remote) against the same API |
| Accounts/MFA | Dedicated cloud identity service, TOTP verified locally on-device |
| Remote access | Outbound WireGuard tunnel, via self-hosted Headscale or custom orchestration |
| Firmware updates | RAUC (A/B partitions, signed bundles, auto-rollback) over the existing outbound connection |
| Rollout strategy | Server-side staged/canary rollout, not all-at-once |
| ISP readiness | No new build now — the above choices already leave the door open |

---

*This is an architecture recommendation, not a backlog addition — happy to break any of these four layers into their own epic/stories in the Scrum backlog if/when you're ready to plan the engineering work.*
