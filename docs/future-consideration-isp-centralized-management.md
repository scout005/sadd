# Future Consideration: ISP / Centralized Remote Management
**Status: Not in current scope. Not part of the product backlog or sprint plan.**
This is a set of architectural notes so today's router framework doesn't have to be reworked later when this becomes its own project. Nothing here should be scheduled or built now — it's a "leave room for" list, not a "build this" list.

---

## Why this matters now, even though the project is later

If an ISP is eventually going to provision, monitor, and update this router at scale, a few decisions made *today* in the app/firmware architecture are expensive to retrofit afterward — mainly around how settings are stored, how updates are packaged, and who's allowed to change what. Getting the shape of these right now costs little; getting them wrong means a rewrite later.

---

## The industry-standard approach (for context)

ISPs don't usually build bespoke remote management — they use one of two Broadband Forum standards:
- **TR-069 (CWMP)** — the long-established standard: the router (CPE) opens an outbound session to the ISP's Auto Configuration Server (ACS), which can then push configuration, trigger firmware downloads, and run diagnostics. It works outbound-only, so it works fine behind NAT/CGNAT without opening inbound ports.
- **TR-369 (USP)** — the newer, still-coexisting standard, built for real-time messaging, better security, and multi-party access (vendor, ISP, and consumer all able to manage different parts of the same device). Major operators are already integrating it, generally alongside TR-069 rather than replacing it outright.

You won't need to implement either now — just be aware that "whoever manages this later" will likely want to speak one or both of these protocols to a device fleet, and the framework should be able to expose itself in that shape without a rebuild.

---

## Architectural considerations to keep in mind today

### 1. Separate "local settings" from "network-level settings" in the data model
Keep a clean line between what a homeowner controls (device names, parental profiles, block lists) and what would eventually be ISP/WAN-level (WAN connection type, DNS provisioning, bandwidth profile, firmware channel). Even if both live in the same local config store today, model them as distinct namespaces/schemas now — it's the difference between "add a remote-management module later" and "re-architect the config store later."

### 2. Design settings around a config schema, not scattered app logic
If settings are defined in one structured, versioned schema (rather than hardcoded across screens), that schema is exactly what an ACS-style system would eventually read/write against. This also makes your own app more maintainable regardless of the ISP project.

### 3. Build firmware updates as atomic, signed, rollback-capable packages from day one
Regardless of who triggers an update (the user, or later an ISP), the underlying mechanism should be:
- Cryptographically signed packages, so only authorized updates install
- Atomic apply with automatic rollback on failed boot (A/B partition style, if hardware allows)
- Versioned, with the current version queryable by any management layer

This is good practice for the consumer product anyway (ties directly into your existing "automatic firmware updates" story) — the only difference later is *who* is allowed to trigger it.

### 4. Keep a permissions/roles concept in mind, even with a single "admin" today
Right now there's effectively one admin (the homeowner). Down the line, an ISP-managed model typically needs at least three tiers: **device owner** (homeowner), **ISP/operator** (network-level access — WAN config, firmware, diagnostics), and **vendor** (manufacturer-level, e.g. security patches). You don't need multi-role support now, but avoid hardcoding "there is exactly one admin" assumptions into auth logic — leave the door open for scoped roles later.

### 5. Log and expose diagnostics in a structured way
Whatever you build for the "detailed security log" (Advanced mode) should be structured data internally, not just human-readable text — structured logs/diagnostics are what a remote-management agent would eventually report upstream (device health, connection status, error counts) without you having to redesign logging later.

### 6. Treat WAN configuration as its own module, not baked into general settings
Even though WAN config isn't user-facing in a meaningful way today (most homes just get DHCP from the ISP), keep WAN provisioning logic isolated in its own module/service rather than intertwined with LAN/Wi-Fi settings. This is the piece an ISP's ACS would most want to touch directly later (connection type, VLAN tagging, DNS assignment), and isolating it now avoids entangling it with consumer-facing features.

### 7. Assume outbound-only connectivity for any future management channel
Don't build anything today that assumes the router needs an open inbound port for remote access — the standard approach (and the one that survives NAT/CGNAT ISP networks) is the device initiating outbound sessions to a management server, not the reverse. If any "remote access" feature is ever added to the current product, keep it outbound-initiated for consistency with this future model.

### 8. Keep telemetry opt-in and clearly scoped
When centralized management arrives, there will be real telemetry flowing to the ISP (device health, usage patterns, diagnostics). Build current analytics/telemetry (if any) with clear consent boundaries and scoping from the start, so adding an ISP-visible telemetry stream later is additive, not a privacy-model retrofit.

---

## What NOT to do right now
- Don't implement TR-069/TR-369 support — premature, and the standards may shift by the time this project starts.
- Don't build a multi-tenant permissions system — just avoid *assuming* single-tenant in ways that are hard to undo.
- Don't add ISP-specific UI or settings screens to the current app.
- Don't let this consideration slow down or complicate the current backlog — it's purely a "keep the door open" list.

---

*This document is intentionally separate from `router-security-app-backlog.xlsx` and `home-network-security-research.md`. Revisit it when the ISP-management project actually starts — at that point it becomes its own set of epics/stories, likely centered on TR-069/TR-369 integration, ACS connectivity, staged rollout tooling, and ISP-facing admin dashboards.*
