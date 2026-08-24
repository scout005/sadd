# Website Full Closure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every remaining Partial/Missing story for `sadd-website.html` from the v2 PO audit (`docs/superpowers/specs/2026-08-22-phase-2-gap-analysis-findings.md` lineage). 30 items across two categories: (a) a systemic click-handler wiring gap affecting 8 stories, (b) 22 content/structure completions. Mobile app and true N/A/no-UI-surface items are explicitly out of scope for this pass.

**Architecture:** Same as all prior phases — `screens`/`screenMeta`/`pageTitles` are single-line JSON in `sadd-website.html`, edited via Python `json.loads`/`json.dumps` round-trip; `forwardMap`/`textLinkMap` are plain JS objects, edited directly; CSS/click-handler logic edited directly via `Edit`.

**Tech Stack:** Static HTML/CSS/vanilla JS, Python 3, Node, Git.

---

### Task 1: Wire up dead buttons (systemic fix)

Add click-handler support for a `[data-action]` attribute pattern (generic, no-op state toggle showing a brief confirmation), OR wire specific buttons individually via existing `[data-goto]`/`textLinkMap` where a real navigation target exists, and via a new lightweight `.btn-secondary[data-confirm]`/`.switch`-like toggle for action-only buttons. Concretely:
- "Re-run setup wizard" row → add `textLinkMap['Re-run setup wizard']='welcome'`
- "Use a passkey instead" button → add `data-goto="wancheck"` (reuses existing success-path screen as a stand-in enrollment confirmation) — acceptable prototype fidelity
- "Scan now" (port scan) → add a generic `[data-action="scan"]` handler branch that flips the row's text to "Scanning…" then back (simple JS, no new screen)
- "Approve" (quarantine) / "Block this device" → add `[data-action]` handler that toggles a `.status-pill` class/text on the row (visual state change simulating the action)
- "This looks wrong — allow it" → same `[data-action]` pattern, updates blockdetail's own copy
- "Set up" (per-device VPN client) → `data-goto` to a small new inline state (toggle the row's own switch instead of a separate screen)
- "Start walk-test" → add a `walktest` screen (simple result: "Living Room: Strong · Bedroom: Weak · Garage: No signal") and wire `data-goto`
- "View the repo" (advupdates/about) → real `<a href="https://github.com/sadd/firmware" target="_blank" rel="noopener">` link

- [ ] Implement the generic `[data-action]` click-handler branch (toggles a `data-state` attribute and swaps visible text between two `data-label-on`/`data-label-off` values) — one shared piece of JS, reused by all the toggle-style buttons above.
- [ ] Apply `data-action` + `data-label-*` attributes to: Approve, Block this device, This looks wrong — allow it, Scan now, Set up (VPN client routing).
- [ ] Add `textLinkMap` entry for "Re-run setup wizard".
- [ ] Add `data-goto="wancheck"` to the passkey button.
- [ ] Build `walktest` screen + wire "Start walk-test" `data-goto`.
- [ ] Add real `href` to the repo link in `advupdates`.
- [ ] Verify (JSON round-trip + grep) and commit.

---

### Task 2: Onboarding structure — diagrams, consolidation, backhaul detail

- [ ] US-1.4: Add 3 simple CSS/SVG line-art diagrams (single router, router+modem, mesh system) to `topology`, replacing the broken "next screen" promise — diagrams live on `topology` itself, not a separate screen.
- [ ] US-1.1: Consolidate onboarding — merge `topology`'s question into `comfortlevel` as a single combined step (one screen, two questions, one continue action), and fold `wancheck` into `success` (silent auto-check, no separate screen). Net effect: chain drops from ~9 to ~7 screens. Update `forwardMap` accordingly.
- [ ] US-7.2: Add a Wi-Fi/Ethernet backhaul radio choice to the mesh-AP row in `advnetwork`.
- [ ] Verify and commit.

---

### Task 3: Security & privacy content completions

- [ ] US-2.4: Replace the geo-IP copy-only claim with a real scrollable list of ~6 selectable countries (checkboxes/switches).
- [ ] US-3.6: Add an interactive demo to `devices` — a "Simulate reconnect with new Wi-Fi address" button (`data-action`) that briefly shows "Still recognized as Leo's Laptop" copy.
- [ ] US-16.1: Expand the About "Security advisories" blurb into a real small table (CVE ID / Status / Date), 2 example rows both "Not applicable."
- [ ] US-16.4: Add sample incident-notification preview text next to the incident toggle in `notifications` (matching the pattern already used for the weekly-digest preview).
- [ ] US-15.2: Add a "Last HBOM/SBOM update: Aug 2026, v3" line to the compliance-statement section in `about` — strongest reasonable UI touchpoint for what's fundamentally a process artifact.
- [ ] Verify and commit.

---

### Task 4: Dashboard, notifications, local UI, mobile-app-parity items

- [ ] US-8.1: Add an "Ad Blocking" stat card to the literal `dashboard` screen's card-grid (currently only Devices/Parental/Security/Remote Access cards).
- [ ] US-10.4: Add a severity select (`Critical only` / `Important & above` / `Everything`) as a global control at the top of `notifications`, above the per-category toggles.
- [ ] US-10.5: Add "Local address: http://192.168.1.1" to the `about` local-web-UI line.
- [ ] US-10.6: Fix the tablet CSS cascade bug — reorder the tablet media query to come *after* the phone breakpoint (or raise specificity) so 641–860px doesn't fall through to phone styles.
- [ ] Verify and commit.

---

### Task 5: VPN, extensibility, and platform completions

- [ ] US-6.4: Expand `advwireguard`'s site-to-site section from one button into a small real flow — site-name field + "Generate pairing key" button (`data-action`, reveals a mono-badge key).
- [ ] US-12.4: Replace "view the repo and roadmap online" button-label-only roadmap reference with an actual short roadmap list (2-3 upcoming items) inside `advupdates`.
- [ ] US-18.1: Add one line to `about`'s OpenWrt paragraph naming the selection criteria ("selected for long-term-support commitment and mature Wi-Fi 7 driver support").
- [ ] US-18.4: Add "themed LuCI overlay" language to the Advanced Mode description (`advhub` or `about`'s local-web-UI line).
- [ ] Verify and commit.

---

### Task 6: Education epic completions

- [ ] US-17.1: Add inline `data-goto="glossary"` links on ~6 more jargon terms across existing screens (DHCP on `advnetwork`, Geo-IP on `advfirewall`, QoS on the relevant screen, Zero Trust on `advnetwork`, TLS/cipher on `advvpn`, subnet on `advnetwork`).
- [ ] US-17.2: Make the comfort-level paths genuinely diverge — "I know networking" skips the now-merged topology/comfort screen's second question and jumps straight to `changepassword`; "I'm new to this" still sees both questions. Update `forwardMap`/card `data-goto` targets accordingly.
- [ ] US-17.4: Add a small "▶ Watch (1:xx)" inline link next to the relevant control on `parental`, `vpn`, and `guest` screens, pointing back to `help` (point-of-use discoverability, not just centralized).
- [ ] US-17.5: Add `aria-label` attributes to icon-only interactive elements (switches, back-chevrons) on at least the most-used screens (`settings`, `dashboard`, `devices`), and add a real "Large text" toggle to `settings`.
- [ ] Verify and commit.

---

### Task 7: New weekly usage report screen (US-5.6)

- [ ] Add a `usagereport` screen (per-child weekly app/category breakdown, bar chart reusing `.bar-chart`), reachable from `parental`'s per-child detail via a new nav-card.
- [ ] Register in `screenMeta`/`pageTitles`.
- [ ] Verify and commit.

---

### Task 8: Final verification, manual check, push

- [ ] Full JSON round-trip check on `screens`/`screenMeta`/`pageTitles`.
- [ ] Grep-verify every new `data-action`/`data-goto` has a corresponding handler branch or screen.
- [ ] Manual browser click-through of: onboarding chain (both comfort-level paths), quarantine approve/block, port scan, site-to-site key generation, walk-test, weekly usage report, tablet-width resize (860px region).
- [ ] `git push origin main`.

## Note on US-10.8 (home-screen widget)

Explicitly **not** implemented — an OS-level home-screen widget has no in-app screen to represent it in an HTML prototype. Documented as a permanent N/A-by-nature item, not a deferred task.
