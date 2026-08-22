# Sadd — Final Design Package

A complete router product design package: research, interface design (28 screens, fully linked), and an engineering handoff mapping every screen to real OpenWrt implementation.

---

## Start here

| File | What it is | Open this if you want to... |
|---|---|---|
| **`03-Sadd-Product-Backlog-User-Stories.html`** | The canonical requirements reference (v0.2) — full Epic → User Story → Acceptance Criteria backlog, merging this package's original brief with gated-in competitive research | Understand exactly what's in/out of scope and why, with priorities and points |
| **`sadd-ui-mockups.html`** | The final, clickable prototype — 28 screens, 56 mockups (mobile + desktop each), with real click-through navigation | Click through the actual product experience |
| **`sadd-sitemap.html`** | Visual flow map of all 28 screens grouped by tier, showing exactly how they connect | See the whole structure at a glance before diving into screens |
| **`sadd-openwrt-mapping.md`** | Every screen mapped to real OpenWrt packages/UCI configs, plus what needs custom engineering | Hand off to firmware/backend engineering |
| **`home-router-user-needs-analysis.md`** | Persona research, feature benchmarking against real router brands, and the original product brief (Part 6) this design was built from | Understand *why* each screen exists |

Exploration files (kept for reference, not the final direction):
- `sadd-design-directions.html` — 10 color palette options explored before landing on Sadd Calm teal
- `sadd-layout-directions.html` — 6 information-architecture options explored before landing on Stacked Cards

---

## How to use the prototype (`sadd-ui-mockups.html`)

**Two ways to navigate:**
1. **Real flow** — click buttons, back arrows, and linking rows exactly as a user would. Onboarding advances screen-to-screen, the Dashboard's cards/sidebar link to their sections, Settings links into Advanced Mode, etc.
2. **Jump to any screen** — the top tab bar is a reviewer shortcut that jumps directly to any of the 28 screens regardless of flow position, for fast QA or presentation.

**Mobile / Desktop toggle** — every screen has both, styled consistently but laid out appropriately for the viewport (stacked cards on mobile, sidebar + master-detail patterns on desktop).

**Design rationale panels** — every screen has a notes card explaining the specific UX decisions behind it, not just what it looks like.

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
