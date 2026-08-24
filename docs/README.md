# Sadd — Final Design Package

A complete router product design package: research, interface design (28 screens, fully linked), and an engineering handoff mapping every screen to real OpenWrt implementation.

---

## Start here

| File | What it is | Open this if you want to... |
|---|---|---|
| **`02-Product-Backlog-User-Stories.html`** | The canonical requirements/backlog reference — 25 epics, personas, full Epic → User Story → Acceptance Criteria backlog, engineering task breakdown, NFRs, project plan, and product positioning, consolidated from every requirements/backlog/plan document in the project | Understand exactly what's in/out of scope and why, with priorities and points |
| **`01-Competitive-Analysis-Firewalla.html`** | The canonical competitive-analysis reference — deep Firewalla analysis plus a broader multi-vendor benchmark (eero, Gryphon, ASUS, TP-Link, NETGEAR, UniFi), consolidated from every competitive-analysis document in the project | Understand where this product sits against the competitive landscape |
| **`sadd-openwrt-mapping.md`** | Every screen mapped to real OpenWrt packages/UCI configs, plus what needs custom engineering | Hand off to firmware/backend engineering |

Persona research, brand feature benchmarking, and the original product brief that once lived in `home-router-user-needs-analysis.md` are now merged into `02-Product-Backlog-User-Stories.html` (personas, product concept) and `01-Competitive-Analysis-Firewalla.html` (brand benchmarks) — see those two documents instead of a standalone needs-analysis file.

> **Note:** `sadd-ui-mockups.html` (the clickable prototype), `sadd-sitemap.html`, `sadd-design-directions.html`, and `sadd-layout-directions.html` are no longer present in this directory. The Screen Inventory, Design System, and Engineering Handoff sections below document what those files contained; the live phone-first prototypes are `sadd-website.html` and `sadd-mobile-app.html` in the repo root.

---

## Design system, in one paragraph

**Layout:** Stacked Cards (status → quick actions → one section per card), chosen over five alternatives (Bento Grid, Chat Style, Carousel, House Map, Dense List) for being the most familiar mobile pattern with zero learning curve.
**Color:** Sadd Calm — soft teal (`#0D9488`), calm and reassuring, reads like a health/banking app rather than a networking product.
**Shape & type:** Meadow Playful's rounded pill buttons and soft card corners, paired with Baloo 2 (headings/labels) and Nunito (body text) — chunky and approachable without tipping into "kids' app" territory.
**Two-tier interface:** Simple Mode is the default everywhere — plain language, no jargon, sensible pre-filled defaults. Advanced Mode (reached via Settings → "Show advanced settings") is additive, never a replacement: same visual shapes, denser layout, technical language used freely for the first time, and an explicit "Expert mode" badge/warning banner as the handshake that you've crossed into a different zone.

---

## Screen inventory (28 total)

**Onboarding (7):** Welcome · Log in · Create account · Verify identity (MFA) · Name your Wi-Fi · Find devices · Setup complete

**Core / Simple Mode (10):** Home dashboard · Devices · Parental controls · Security & ad block · Remote access (VPN) · Guest Wi-Fi · Connect a device · Per-device parental controls · Ad block configuration · Connect a laptop (VPN)

**Help & Settings (2):** Help & fixes · Settings

**Advanced Mode (9):** Advanced hub · Network & VLANs · VPN Server (OpenVPN) · Firewall & port forwarding · Traffic & QoS · Multi-WAN & failover · Diagnostics & logs · Developer & API access

---

## Engineering handoff summary

From `sadd-openwrt-mapping.md`: roughly **60% of the product maps to stock OpenWrt packages** with no custom firmware work (VLANs, firewall, OpenVPN, QoS via `sqm-scripts`, multi-WAN via `mwan3`, diagnostics via `nlbwmon`). The concentrated custom-engineering work is:

1. **The Sadd Agent** — a daemon translating simple app actions into UCI/firewall/dnsmasq changes
2. **Screen-time tracking** — no native OpenWrt concept, built on top of traffic monitoring
3. **The laptop VPN "Easy setup" flow** — needs a custom desktop client + cloud cert-issuance handoff
4. **Named app blocking** — ongoing domain-list content-ops, not one-time engineering
5. **Cloud layer** — accounts, MFA, push notifications, none of which OpenWrt provides natively

Full package list and detailed per-screen mapping are in the mapping doc.
