# Phase 2 — Prototype vs. Backlog v0.2 Gap Analysis

**Status:** Findings — not yet acted on. This is the spec input for whatever Phase 2 implementation work comes next.
**Method:** Three parallel research passes (read-only), each fully extracting and reading every screen in `sadd-website.html` (31 screens) and `sadd-mobile-app.html` (12 screens), cross-referenced against all 92 stories in `docs/03-Sadd-Product-Backlog-User-Stories.html` (v0.2), grouped by epic (1–6, 7–12, 13–18). Every verdict below cites the specific screen/element checked, not a guess.

**Verdict legend:** Covered · Partial (some AC met, or tier-mismatched) · Missing · Missing (out of declared scope) — `sadd-mobile-app.html` was designed narrower than `sadd-website.html` from the start (no Parental Controls, no security dashboard, no VPN/Advanced Mode, no desktop layout) · N/A — no UI surface — business/legal/engineering-process story with nothing a screen could represent.

---

## Cross-cutting findings (read this before the tables)

1. **VPN engine mismatch, not just a gap.** `sadd-website.html`'s `advvpn` screen explicitly states the router runs **OpenVPN** ("This is what powers the one-tap … toggle") — but the backlog's `US-6.1` specifies **WireGuard** as the default one-tap engine, with OpenVPN as the Advanced-tier alternative (`US-6.2`). Neither "WireGuard" nor "AmneziaWG" appears anywhere in either file. This is a real architectural contradiction between the backlog and the existing prototype, not something a screen addition fixes — needs a product decision (rename the backlog's assumption, or change the prototype's engine) before Epic 6 work starts.
2. **Epic 11 (Privacy & Data Handling) is almost entirely uncovered**, despite being the epic that formally resolved Sadd's own open product question about local-first data handling in Phase 1. The only privacy-adjacent artifact in either file is a boilerplate "I agree to the Terms and Privacy Policy" checkbox on `sadd-website.html`'s `signup` screen. This is a striking gap for 2 P0 + 1 P1 story.
3. **Neither prototype models "public pages."** Both are exclusively logged-in app/dashboard screens. Every story that expects a public marketing/trust page (CVE advisory `US-14.1`, disclosure policy `US-14.2`, Pricing Promise `US-17.5`, Built-on-OpenWrt page `US-18.6`) reads as "Missing" — but this is a structural category gap (these prototypes were never meant to include a public website), not a per-story oversight. Worth deciding explicitly whether public-page mockups belong in scope for a future phase or are tracked entirely outside these two files.
4. **`sadd-mobile-app.html`'s declared scope isn't fully self-consistent.** Its own design spec excludes Parental Controls and a security dashboard, yet `devices`/`devicedetail` already include Quarantine status, a Kids/Family/IoT/Guest zone picker, a per-device pause timer, and a bare "Bedtime" toggle — all Parental-Controls/Security-adjacent. Meanwhile Epic 9 (Reliability, mostly Simple-tier) and Epic 11 (Privacy, Simple-tier, cross-cutting) are **not** covered by any declared exclusion, yet are 100% missing — real gaps, not by-design omissions.
5. **Two easy-to-miss positives, worth confirming before assuming they need to be (re)built:** `sadd-website.html`'s `advapi` screen already covers `US-12.5` (documented API keys + webhooks) well, and `advupdates` (Firmware Updates, reachable via `textLinkMap` from both Settings and Advanced hub) already contains a real automatic-rollback claim relevant to `US-18.3`. Both are short/easy-to-skim screens a less thorough pass could miss.
6. **`sadd-website.html`'s Advanced Mode has no first-class tier attribute** — it's inferred purely from an `adv`-prefixed screen-naming convention, not a `screenMeta` flag. Any future work that needs to know "is this screen Advanced-tier" programmatically (e.g. for consistency checks) will need to either formalize that convention or keep relying on the naming pattern.
7. **All "Covered" verdicts describe UI/copy presence in a static mockup, not working functionality** — expected for a prototype, but worth stating so a later reader doesn't over-read "Covered" as "implemented."

---

## Epic 1 — Onboarding & Setup

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-1.1 | Set up in under 10 min via phone | Simple | P0 | Covered — `welcome`→`changepassword`→`setup`→`recoverycode`→`discover`→`wancheck`→`success`, 5-step wizard + confirmation. QR/cable only, no Bluetooth path. | Covered — `connect`(barcode/Bluetooth)→scan/BT path→`admin`→`wifi`→`success`, 6 screens. |
| US-1.2 | Auto-detect network topology, no jargon | Simple | P0 | Missing — no topology-detection question anywhere in the wizard. | Missing — no topology question. |
| US-1.3 | Guided household setup: member → device → preset | Simple | P0 | Partial — split across 3 screens (`discover` for naming/Family-Guest, `parental` for per-child setup, `vpn` for invites), not one integrated flow. | Missing (out of declared scope) — no "person" profile concept; Parental Controls excluded. |
| US-1.4 | Pair multiple phones, admin/viewer roles | Simple | P1 | Partial — `vpn` has "Invite another family member" + a connected-users list, but no role selection. | Missing — no multi-user pairing UI. |
| US-1.5 | Passkey login (WebAuthn/FIDO2) | Simple | P1 | Missing — `login`/`mfa` use password + SMS/authenticator OTP + Google/Apple only. | Missing — no login/auth screen at all (flow starts post-auth). |
| US-1.6 | Static IP + local web UI | Advanced | P1 | Partial — Advanced Mode functions as an expert UI, but no explicit "static IP" setting or LAN-IP reachability text. | Missing (out of declared scope) — no Advanced Mode screens. |

## Epic 2 — Core Threat Protection (DPI / IDS / IPS)

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-2.1 | Auto malware/intrusion protection, default ON | Simple | P0 | Covered — `security` toggle-hero on by default, dashboard shows "214 threats blocked this month." | Missing (out of declared scope) — no security screen. |
| US-2.2 | Push notification within 5s of block | Simple | P0 | Partial — only static history rows, no tap-through, no "push" framing. | Missing (out of declared scope). |
| US-2.3 | Auto-block by default + per-rule Advanced tuning | Simple + Advanced | P0 | Partial — Simple toggle implied on, but no Advanced screen exposes per-rule/threshold tuning. | Missing (out of declared scope). |
| US-2.4 | Geo-IP filtering | Advanced | P1 | Missing — no country/geo blocklist UI anywhere. | Missing (out of declared scope). |
| US-2.5 | Automated open-port scanning | Advanced | P1 | Missing — `advfirewall` has manual port-forwarding + UPnP only, no scan feature. | Missing (out of declared scope). |
| US-2.6 | New-device quarantine, one-tap approve/deny | Simple | P0 | Partial — `devices` detail pane has isolation copy + "Move to…"/Block, but no push-driven approve/deny. | Covered — `devices` list shows Quarantine pill; `devicedetail` shows zone picker + Block/Forget. |

## Epic 3 — Network Segmentation & Zero Trust

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-3.1 | One-tap Kids/Guest/Smart Home zones | Simple | P0 | Partial — zones exist and are assignable (5 VLANs in `advnetwork`), but onboarding only offers Family/Guest; full model lives in Advanced-tier. | Partial — `devicedetail`'s zone picker offers 4 targets, but no zone auto-creation shown during onboarding. |
| US-3.2 | Device-type fingerprinting suggests zone | Simple | P1 | Missing — no suggested-zone UI. | Missing — move-to-network list has no suggestion. |
| US-3.3 | Device-level microsegmentation | Advanced | P1 | Missing — no default-deny same-zone toggle. | Missing (out of declared scope). |
| US-3.4 | Zero Trust least-privilege rules/device | Advanced | P1 | Missing — no allow-list-only rule engine. | Missing (out of declared scope). |
| US-3.5 | MAC-randomization-tolerant device identity | Simple + Advanced | P0 | Missing — algorithmic behavior with no UI representation; `advlogs` even logs "unknown MAC address" without addressing rotation. | Missing — no related UI. |

## Epic 4 — Transparency & Explainability

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-4.1 | Plain-English explanation per blocked connection | Simple | P0 | Missing — static one-line log rows, no tap-through detail view. | Missing (out of declared scope). |
| US-4.2 | Full block/allow history, 30-day retention | Simple | P0 | Partial — `advlogs` has recent-activity feed + CSV export, but it's Advanced-tier-only (backlog wants Simple) and shows no retention statement. | Missing (out of declared scope). |
| US-4.3 | Filterable logs by device/category/time | Advanced | P1 | Partial — `advlogs` exists with export, no search/filter controls. | Missing (out of declared scope). |
| US-4.4 | "Why was this blocked" + inline unblock | Simple | P0 | Missing — no "unblock"/"false positive"/"why" language anywhere. | Missing (out of declared scope). |
| US-4.5 | Weekly "Network Health" summary | Simple | P1 | Missing — no weekly-digest screen. | Missing (out of declared scope). |

## Epic 5 — Parental Controls & Content Filtering

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-5.1 | Age-based content filter preset, one tap | Simple | P0 | Partial — `parental`/`devcontrols` offer Kid-safe/Teen/Off presets, but 2-tier not the 3-tier Young Child/Tween/Teen model. | Missing (out of declared scope). |
| US-5.2 | Named app blocking | Simple | P0 | Covered — "Blocked apps" grid (TikTok/Instagram blocked, YouTube/Roblox allowed). | Missing (out of declared scope). |
| US-5.3 | Screen-time presets (School night/Weekend/Bedtime) | Simple | P0 | Partial — "Bedtime" + "Homework mode" toggles exist, but no named School-night/Weekend presets, no symmetric allow-only window. | Partial — `devicedetail` has a bare "Bedtime: Off" toggle only, no time range or presets — present despite declared scope exclusion. |
| US-5.4 | One-tap pause (device/person/house), auto-resume | Simple | P0 | Covered — "Pause All" (house), "Pause now" (person), timer-row (device). | Partial — device-level timer only; no person/house-level pause. |
| US-5.5 | Reward/bonus time grant | Simple | P1 | Covered — "+ Add bonus time" per device. | Missing (out of declared scope). |
| US-5.6 | SafeSearch enforcement | Simple | P0 | Missing — no SafeSearch mention anywhere. | Missing (out of declared scope). |
| US-5.7 | Person-based rules across devices | Simple | P1 | Covered — `parental` is person-centric (Emma/Leo own their settings). | Missing (out of declared scope) — device screens are purely device-centric. |

## Epic 6 — VPN & Remote Access

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-6.1 | One-tap remote access (WireGuard + DDNS) | Simple | P0 | Partial/mismatch — one-tap toggle + QR invite UX matches, but the underlying engine is explicitly labeled OpenVPN, not WireGuard; no DDNS mentioned. See finding #1 above. | Missing (out of declared scope). |
| US-6.2 | OpenVPN alternative to WireGuard | Advanced | P1 | Mismatch — OpenVPN is the *only/primary* engine, not an alternate to a WireGuard default. | Missing (out of declared scope). |
| US-6.3 | Per-device commercial VPN client routing | Advanced | P1 | Missing — no third-party VPN client routing UI. | Missing (out of declared scope). |
| US-6.4 | Site-to-site VPN | Advanced | P2 | Missing — no site-to-site wizard. | Missing (out of declared scope). |
| US-6.5 | VPN throughput ≥300 Mbps | Advanced | P0 | Missing/N/A-ish — a hardware/QA commitment, not UI-representable. | Missing (out of declared scope). |
| US-6.6 | Censorship-resistant protocol (AmneziaWG) | Advanced | P2 | Missing — only OpenVPN exposed. | Missing (out of declared scope). |

## Epic 7 — Wi-Fi Integration

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-7.1 | Router ships with working Wi-Fi out of box | Simple | P0 | Covered — `setup` sets SSID/password with strength meter. | Covered — `wifi`/`network` set SSID/password. |
| US-7.2 | Mesh AP expansion, inherits security zones | Advanced | P1 | Missing — no mesh/satellite/AP content anywhere. | Missing (out of declared scope). |
| US-7.3 | Wi-Fi signal heatmap / walk-test tool | Advanced | P2 | Missing — no heatmap/walk-test tool. | Missing (out of declared scope). |

## Epic 8 — Ad & Tracker Blocking

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-8.1 | Network-wide ad/tracker blocking, default ON | Simple | P0 | Covered — `security`/`adblock` toggle on by default, "1,204 ads blocked this week." | Missing (out of declared scope) — no ad-block screen. |
| US-8.2 | One-tap whitelist for broken sites | Simple | P0 | Partial — `adblock` lists one whitelisted site, no add control or "report broken site" flow. | Missing (out of declared scope). |
| US-8.3 | Import custom blocklists | Advanced | P1 | Partial + tier mismatch — a "Custom lists" radio exists, but lives in the Simple-tier `adblock` screen, not Advanced Mode; no real import UI. | Missing (out of declared scope). |

## Epic 9 — Reliability & Multi-WAN

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-9.1 | Automated watchdog restart + uptime target | Simple | P0 | Partial — manual "Restart" quick action + a past-restart log entry, but no automatic-on-failure logic or uptime %. | Missing — no WAN/restart/uptime content anywhere. |
| US-9.2 | Plain-language "why did internet drop" | Simple | P0 | Partial — `help` (live health checks + "Simulate offline mode") is the closest analog but never classifies root cause. | Missing — no equivalent screen. |
| US-9.3 | Automatic dual-WAN failover | Advanced | P1 | Covered — `advwan` Primary/Backup + "Auto-switch on outage" toggle. | Missing (out of declared scope). |
| US-9.4 | Load balancing across two WANs | Advanced | P2 | Missing — `advwan` only supports failover, not load-balance/pinning. | Missing (out of declared scope). |

## Epic 10 — Mobile App & Dashboard

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-10.1 | Single-app home dashboard (device/threat/alert counts) | Simple | P0 | Covered — `dashboard` status line, device count, threats-blocked count, Remote Access card, all in one app. | Partial — `devices` shows device count/list, but no threat/alert count or unified status line (security dashboard out of scope). |
| US-10.2 | Rename + group devices, auto-suggested names | Simple | P0 | Partial — rename only exists during onboarding (`discover`); ongoing `devices` only offers zone reassignment. | Partial — zone reassignment only, no rename/icon control. |
| US-10.3 | Configurable push notifications by severity | Simple | P0 | Partial — `settings` shows only a summary row "Notifications · 3 enabled," no drill-down. | Missing — `settings` has no notifications entry at all. |
| US-10.4 | Dedicated tablet layout | Simple | P1 | Missing — one `@media` breakpoint collapses everything to phone/nav layout, no tablet-specific layout. | Missing (out of declared scope) — phone-only by design. |
| US-10.5 | Home-screen widget | Simple | P2 | Missing — no widget mockup. | Missing — no widget mockup. |

## Epic 11 — Privacy & Data Handling

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-11.1 | Local-only by default, opt-in cloud consent | Simple | P0 | Missing — only a boilerplate ToS/Privacy-Policy checkbox on `signup`. | Missing — no privacy content anywhere. |
| US-11.2 | Configurable log retention (7/30/90 days) | Simple | P0 | Missing — no retention control anywhere. | Missing. |
| US-11.3 | Self-service account & data deletion | Simple | P1 | Missing — no deletion flow. | Missing. |

## Epic 12 — Developer & Power-User Extensibility

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-12.1 | Run Docker containers on router | Advanced | P2 | Missing — no Docker/container card in `advhub`. | Missing (out of declared scope). |
| US-12.2 | SSH access, key-based, off by default | Advanced | P2 | Missing — no SSH toggle anywhere. | Missing (out of declared scope). |
| US-12.3 | Open-source firmware repo, documented branches | Advanced | P1 | Missing — `advupdates` shows version history but no repo/branch reference. | Missing (out of declared scope). |
| US-12.4 | Public roadmap and changelog | Advanced | P1 | Partial — `advupdates`' per-release history is changelog-like, but lives in the router's own admin UI, not a public site. | Missing (out of declared scope). |
| US-12.5 | Documented REST API / webhook access | Advanced | P2 | Covered — `advapi`: API key section + "Generate new API key" + Webhooks. | Missing (out of declared scope). |
| US-12.6 | opkg/apk package manager access | Advanced | P2 | Missing — no package-manager reference. | Missing (out of declared scope). |

## Epic 13 — Fleet & Small-Business Mode

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-13.1 | Multi-router web console for fleet/sites | Business | P2 | Missing — no fleet console; `advhub` manages one router only. | Missing (out of declared scope). |
| US-13.2 | Documented REST API + token auth for fleet mgmt | Business | P2 | Partial — `advapi` exists but is single-router/Advanced-tier, not fleet-scoped. | Missing (out of declared scope). |
| US-13.3 | Exportable compliance reports | Business | P2 | Missing — `advlogs` CSV export is a live activity log, not standardized report templates. | Missing (out of declared scope). |

## Epic 14 — Trust, Disclosure & Vulnerability Management

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-14.1 | Public CVE/security-advisory page | Public page | P0 | Missing — no public-page content modeled (structural, see finding #3). | Missing — same. |
| US-14.2 | Vulnerability-disclosure policy + security.txt | Public page | P0 | Missing — no such content. | Missing. |
| US-14.3 | User-controllable remote/support access, no backdoor | Advanced | P0 | Missing — no SSH toggle or remote-access control anywhere; zero "SSH" hits in the file. | Missing (out of declared scope). |
| US-14.4 | Push incident-guidance during security events | Simple | P1 | Missing — `settings` notifications row has no drill-down/content. | Missing — no notifications content. |
| US-14.5 | Local-only vuln scan data, opt-in before upload | Advanced | P0 | Missing — no vulnerability-scanning feature exists at all. | Missing (out of declared scope). |
| US-14.6 | SLA to track upstream OpenWrt advisories | Process | P1 | N/A — no UI surface. | N/A — no UI surface. |

## Epic 15 — Regulatory Compliance & Manufacturing

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-15.1 | In-app "About" screen: origin disclosure | Simple | P0 | Missing — no "About" screen exists at all. | Missing — `settings` has an inert "Help & About" row (no `data-goto`, non-functional), no compliance content. |
| US-15.2 | HBOM/SBOM maintained per SKU | Process | P0 | N/A — no UI surface. | N/A. |
| US-15.3 | Legal review of mfg partner vs. Covered List | Process | P0 | N/A — no UI surface (backlog itself notes this is a legal/business gate). | N/A. |
| US-15.4 | Plain-language supply-chain statement | Simple (+ public page) | P1 | Missing — no such statement in-app. | Missing. |

## Epic 16 — Beginner-First Education & Onboarding Content

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-16.1 | Tap-anywhere glossary/tooltips | Simple | P0 | Missing — `help` is troubleshooting-only, no tooltip/glossary system. | Missing — no glossary content of any kind. |
| US-16.2 | Setup opens with a comfort-level question | Simple | P0 | Missing — no comfort-level question or pacing branch in the wizard. | Missing — same. |
| US-16.3 | ≥8 embedded <2-min video walkthroughs | Simple | P1 | Missing — no video/media elements anywhere. | Missing. |
| US-16.4a | Full setup via local web UI (LuCI-based), no app needed | Simple + Advanced | P1 | Missing — the site is a cloud-account app, not a router-local LuCI-style admin UI; Advanced Mode is custom-styled, not evidently LuCI. | Missing (out of declared scope) — local web UI is a desktop/router-local concept, outside phone-only scope. |
| US-16.4b | Screen-reader accessible setup/daily-use | Simple | P1 | Missing/unverifiable — no ARIA roles/labels observed on icon-only controls. | Missing/unverifiable — same pattern. |
| US-16.4c | Formal WCAG 2.1 AA audit | Process | P1 | N/A — no UI surface. | N/A. |

## Epic 17 — Hardware & Pricing

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-17.1 | Resolve single-router vs. mesh-first decision | Process | P0 | N/A — no UI surface. | N/A. |
| US-17.2 | Simple 3-SKU lineup naming | Process | P0 | N/A — no UI surface. | N/A. |
| US-17.3 | "Which model do I need" quiz | Simple | P1 | Missing — no quiz feature. | Missing. |
| US-17.4 | No subscription required for core protection | Process | P0 | Partial (real touchpoint) — `security` screen states verbatim: *"all core security is included free, no subscription required."* | Missing (out of declared scope) — no Security dashboard to carry the claim. |
| US-17.5 | Public, dated "Pricing Promise" page | Public page | P0 | Missing — no pricing/promise page modeled. | Missing. |
| US-17.6 | New paid tiers must be strictly additive | Process | P0 | N/A — no UI surface (governance policy). | N/A. |
| US-17.7 | Docs: tiers differ in throughput, not security | Simple | P0 | Missing — no product-comparison content anywhere. | Missing. |

## Epic 18 — OpenWrt Platform Foundation

| ID | Story (short) | Tier | Pri | sadd-website.html | sadd-mobile-app.html |
|---|---|---|---|---|---|
| US-18.1 | Lock OpenWrt release/branch + hardware target | Process | P0 | N/A — no UI surface. | N/A. |
| US-18.2 | GPL boundary ADR | Process | P0 | N/A — no UI surface. | N/A. |
| US-18.3 | Fail-safe sysupgrade OTA with rollback | Process | P0 | Partial (real touchpoint) — `advupdates` states verbatim: *"if an update fails to start properly, your router automatically rolls back on its own."* | Missing — no firmware/update screen at all. |
| US-18.4 | Local web UI as themed/extended LuCI | Advanced | P1 | Partial — an Advanced Mode tier exists (8 sub-screens), fulfilling the concept, but is fully custom-styled with zero LuCI branding/behavior evidence. | Missing (out of declared scope) — no Advanced Mode. |
| US-18.5 | Curated/version-pinned opkg package manifest | Process | P0 | N/A — no UI surface. | N/A. |
| US-18.6 | Public "Built on OpenWrt" provenance page | Public page | P1 | Missing — "OpenWrt" doesn't appear anywhere in the app's own UI text. | Missing. |
| US-18.7 | On-router agent daemon (UCI translation) | Process | P0 | N/A — no UI surface (backend daemon; UI only reflects results). | N/A. |

---

## Priority Gaps — Missing P0 stories in `sadd-website.html`

These are the highest-priority items: P0 (MVP-blocking), and currently **Missing** (not Partial, not Covered) in the primary full-scope prototype. Ordered by epic:

1. `US-1.2` — Auto-detect network topology (Epic 1, Onboarding)
2. `US-3.5` — MAC-randomization-tolerant device identity (Epic 3, Segmentation)
3. `US-4.1` — Plain-English block explanation (Epic 4, Transparency)
4. `US-4.4` — "Why was this blocked" + inline unblock (Epic 4, Transparency)
5. `US-5.6` — SafeSearch enforcement (Epic 5, Parental Controls)
6. `US-11.1` — Local-only by default, opt-in cloud consent (Epic 11, Privacy)
7. `US-11.2` — Configurable log retention (Epic 11, Privacy)
8. `US-14.1` — Public CVE/advisory page (Epic 14, Trust) — *structural, see finding #3*
9. `US-14.2` — Disclosure policy + security.txt (Epic 14, Trust) — *structural*
10. `US-14.3` — User-controllable remote/support access, no backdoor (Epic 14, Trust)
11. `US-15.1` — In-app "About" screen origin disclosure (Epic 15, Compliance)
12. `US-16.1` — Tap-anywhere glossary/tooltips (Epic 16, Education)
13. `US-16.2` — Comfort-level onboarding question (Epic 16, Education)
14. `US-17.7` — Docs: tiers differ in throughput, not security (Epic 17, Hardware)

**Also flag, even though not a clean "Missing":** `US-6.1`/`US-6.2` (VPN engine mismatch — a correctness issue, not an absence) and the Epic 2/9/10 P0 stories currently **Partial**, since several of those are close to done and may be cheaper wins than the full-Missing list above.

---

## Recommended next steps

This is too much to implement in one pass (14+ clean-Missing P0s, plus a dozen consequential Partials, across a 92-story backlog). Suggested sequencing for a follow-up brainstorm, mirroring how Phases A/B/C worked:

- **Phase 2a — Privacy & Trust foundation:** Epic 11 (Privacy & Data Handling, currently ~0% covered) + Epic 14's in-app stories (`US-14.3` SSH/no-backdoor toggle) + `US-15.1` (About screen). These are foundational, P0, and currently the emptiest.
- **Phase 2b — Transparency & Education:** Epic 4's Missing P0s (`US-4.1`, `US-4.4`) + Epic 16's Missing P0s (`US-16.1` glossary, `US-16.2` comfort-level onboarding question) — these are Sadd's stated differentiators and are currently the weakest-represented despite that.
- **Phase 2c — VPN engine decision + fix:** Resolve the WireGuard-vs-OpenVPN mismatch (product decision required first, not just an implementation task) before touching Epic 6 screens.
- **Phase 2d — Remaining P0 gaps + notable Partials:** `US-1.2`, `US-3.5`, `US-5.6`, `US-17.7`, plus cleanup on the Partial P0s in Epics 2/9/10.
- **Public-page stories** (`US-14.1`, `US-14.2`, `US-17.5`, `US-18.6`) — decide whether these belong as new mockup screens in these files at all, or are tracked as a separate marketing-site deliverable outside this prototype's scope, before scheduling them into any phase.

---

## Closure status (Phases 2a–2g, completed)

All of the above was implemented in a continuous run through Phases 2a–2g. Summary of what changed and the judgment calls made along the way:

- **2a — Privacy & Trust foundation:** New Privacy screen (`US-11.1`, `US-11.2`, `US-11.3`), new About screen (`US-15.1`), SSH-access toggle in `advapi` (`US-14.3`); mobile app's dead "Help & About" row wired up.
- **2b — Transparency & Education:** Block-detail tap-through with plain-English reasons and an inline allow action (`US-4.1`, `US-4.4`); standalone Networking glossary (`US-16.1`); comfort-level onboarding question in both prototypes (`US-16.2`).
- **2c — VPN engine fix:** Resolved the WireGuard/OpenVPN mismatch by product decision (not just implementation): added a new `advwireguard` screen as the actual engine behind the one-tap toggle, repositioned the existing OpenVPN screen as the Advanced-tier alternate for older clients, and split `advhub`'s single VPN dcard into two (`US-6.1`, `US-6.2`).
- **2d — Remaining clean-Missing P0s:** Network topology onboarding question (`US-1.2`), a MAC-randomization-tolerant recognition note on device detail (`US-3.5`), a Safe Search toggle in Parental Controls (`US-5.6`).
- **2e — Public-page content:** Rather than building separate marketing-site pages (which don't fit either file's logged-in-app-shell architecture), the content was folded into the About screen: tier-parity documentation (`US-17.7`), a security advisories summary combined with disclosure-policy language (`US-14.1`, `US-14.2`), the Pricing Promise (`US-17.5`), and a "Built on OpenWrt" line (`US-18.6`) — website gets the full set, mobile app gets a lighter version (pricing promise + Built on OpenWrt only).
- **2f — Partial-P0 cleanup:** Root-cause hint added to Help's Wi-Fi warning and an automatic-restart note near the dashboard's Restart action (`US-9.1`, `US-9.2`); the previously-inert Notifications settings row wired up to a real severity-toggle screen (`US-10.3`).
- **2g — High-value remaining P1s:** Geo-IP filtering and open-port scanning added to the Firewall screen (`US-2.4`, `US-2.5`); an open-source-firmware/repo note added to Firmware Updates (`US-12.3`, `US-12.4`); a device-type zone suggestion added to device detail (`US-3.2`).

**Consciously not implemented, and why:**
- **All `N/A — no UI surface` stories** (HBOM/SBOM process, GPL boundary ADR, OpenWrt version/target lock, curated package manifest, the on-router agent daemon, hardware-tier/SKU-naming business decisions, legal Covered List review, governance policy) — these are business/legal/engineering-process work with nothing a UI mockup can represent, not gaps in the prototype.
- **Epic 13 (Fleet & Small-Business Mode)** — deliberately excluded from both files' default and Advanced experiences by Phase 2a's own design principle: a Business-tier fleet console is a different product surface, not a settings screen bolted onto the consumer app.
- **Remaining P1/P2 items not covered in this pass:** mesh AP accessory and Wi-Fi heatmap (Epic 7), custom blocklist import (`US-8.3`, tier-mismatch noted but not restructured), WAN failover/load-balancing (Epic 9), tablet layout and home-screen widget (Epic 10), per-device VPN client routing and site-to-site VPN (Epic 6), Docker support and opkg access (Epic 12), video walkthroughs and the WCAG audit (Epic 16), and any Business-tier Epic 13 screens. These are reasonable candidates for a future pass but were judged lower-value-per-effort than what shipped here.
