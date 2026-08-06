# Phase B — Requirement Gaps Design

**Status:** Approved
**Scope:** `sadd-website.html` only. Sub-project 2 of the larger "study docs → check requirements → fix `sadd-website.html`" effort (Phase A, bug fixes, is complete: 7 tasks, all committed and pushed).

This spec covers the 5 requirement gaps found by the tester/reviewer pass documented in conversation history (no separate findings doc — reproduced per-gap below) and refined through brainstorming with the user, including one scope expansion (auto-quarantine VLAN for unknown devices) beyond the original review finding.

---

## Background

`sadd-website.html` is a single-file JS-driven SPA prototype. `const screens = {...}` is a single very long line holding a JS object literal, one key per screen (currently 27 keys after Phase A's `connectrouter` removal), each value being that screen's HTML as a string. Screen keys relevant to this spec: `mfa`, `devices`, `advnetwork`, `advhub`, `vpn`, `advvpn`, `settings`, `dashboard`, `help`.

**Line-number caution:** the `screens`/`screenMeta` object's line number has shifted twice already during Phase A (586 → 584 → possibly further after this phase's edits, since Task 7 also removed content). Every implementation task in the eventual plan must re-locate it via `grep -n "^  const screens = "` before editing — never assume a fixed line number.

Navigation mechanics (established in Phase A, reused here): `data-goto="<key>"` attributes drive direct navigation; `.dcard`/`.nav-card`/`.adv-row`/`.setting-row` elements navigate via `<strong>` label text matched against `textLinkMap`; `.page-crumb` elements provide back-navigation.

---

## Gap 1: MFA default method

**Finding:** `mfa` screen pre-selects "Authenticator app" as the active `.mfa-toggle` tab. The spec (confirmed product decision, `home-network-security-research.md` §5, SRS FR-02) requires SMS/push to be the pre-selected default, with authenticator app and email as visible (not hidden) alternatives.

**Fix:** In the `mfa` screen's HTML, swap which `.mfa-toggle button` starts with `class="active"` and which `data-panel` starts visible — "Text message" (SMS/push) becomes the default active tab instead of "Authenticator app". No other change to this screen; the toggle mechanism itself (`.mfa-toggle button` + `data-panel`/`data-group`) is existing, working JS (Phase A didn't touch it) and needs no modification — only which option starts selected changes.

---

## Gap 2: Device Block action + auto-quarantine VLAN

**Finding:** `devices` screen shows "Unknown device" with a plain "Online" status pill — no visual distinction from a recognized device, and no direct Block action (SRS FR-05, backlog US4.3: "New/unknown devices are visually flagged in the device list" + "direct 'Block' action"). Expanded during brainstorming: unknown devices should also be automatically network-isolated (matching the product's existing IoT-isolation principle, Part 6.3.E of the product brief) rather than sitting on the main LAN while unreviewed.

**Fix — list view:**
Unknown/unrecognized device rows in the `devices` screen's list (both the mobile list and the desktop `.split-desk-list`) get:
- A warm-tinted row background + border (matching the visual language already used for `.check-warn`/`.adv-warning` elsewhere: amber tint, not the neutral white of normal rows)
- A small "New" badge next to the device name (uppercase, amber background, pill-shaped — matching the `.chip-warning` treatment already in the CSS)
- Status text changes from a bare "Online" pill to something reflecting quarantine, e.g. "Online · Quarantined"

**Fix — detail pane:**
The device detail pane (reached by tapping the unknown device) gains, alongside the existing Pause/Bedtime/Group/Forget controls:
- A "Move to…" control: a `<select>` element with one `<option>` per existing named network (Main Network, Kids, IoT / Smart Home, Guests) — this reuses the exact `<select><option>...</option></select>` pattern already established in the `discover` (onboarding) screen for assigning a device's category, rather than inventing a new interaction pattern. Selecting an option is a placeholder/demo interaction with no wired-up logic, matching the fidelity of the existing Pause/Bedtime controls (also non-functional demo UI).
- A "Block" button (styled like the existing `.btn-danger-soft` "Forget this device" button already in this pane)
- The existing "Group" `.setting-row` (currently showing static value "Kids") is replaced by this new "Move to…" select for the unknown device specifically — recognized devices' detail panes are untouched and keep their plain "Group" row as-is
- Until the admin acts, the device's `.sr-main`/detail header should reflect it's currently in "Quarantine"

**Fix — Network & VLANs (Advanced Mode):**
Add a 5th row to the `advnetwork` table, following the exact existing row pattern (icon, name, subnet, device count, active-toggle):
- Name: "Quarantine"
- Subnet: `192.168.5.0/24` (next in the existing sequential pattern: .1, .2, .3, .4)
- Device count: 1 (matching the single "Unknown device" shown in the demo data)
- Active toggle: on

**Fix — Advanced Hub summary:**
The `advhub` screen's "Network & VLANs" card updates from `<div class="dcard-big">4</div><div class="dcard-sub">networks configured</div>` to `5` / "networks configured", reflecting the new VLAN.

**Explicitly not built:** real VLAN assignment logic, real network isolation enforcement, or a generalized "review new devices" queue/screen — this is a static prototype; the fix demonstrates the intended UX (visual flag, quarantine-by-default, admin decides later) using the same non-functional-but-representative fidelity as the rest of the file's demo interactions.

---

## Gap 3: Remote-access scope split (management-only vs. full-LAN)

**Finding:** Neither `vpn` (Simple Mode) nor `advvpn` (Advanced Mode, VPN Server/OpenVPN) distinguishes the required two access scopes (SRS FR-14, backlog US7.4/US7.5, Confirmed Product Decision #7): management-only is the default, out-of-box behavior; full-LAN access is a separate, opt-in, Advanced-only setting that coexists with (never replaces) the default.

**Fix:** Add to the `advvpn` screen only:
- A new setting row: "Full home network access", a toggle, **off by default**
- Directly below/attached to it, a warning banner reusing the existing `.adv-warning` pattern (amber background, warning icon, bold headline + explanatory sub-text) — copy along the lines of: "Turning this on lets remote sessions reach every device on your network, not just router settings. Only enable this if you understand the risk."

**Explicitly not changed:** the `vpn` screen (Simple Mode) — no scope language, no toggle, no indicator added there. Per the two-tier design principle, Basic-mode users get management-only access with zero configuration and zero exposure to the concept; only Advanced Mode users see or control the distinction.

---

## Gap 4: Manual update approval / firmware update history

**Finding:** No screen exposes update history, manual approval, or rollback status (SRS FR-12, backlog US11.2). `security` and `settings` both show only a terse "Up to date" status.

**Fix:** Add one new screen, key `advupdates`, titled "Firmware Updates", following the existing `.wizard-desk > .wizard-card` Advanced-screen layout pattern (same as `advnetwork`, `advqos`, etc.), containing:
- Current version + last-checked timestamp (reuse data already implied elsewhere: v4.2.1, matching `security`'s existing status card)
- An auto/manual update toggle — **auto by default** (matching the SRS's "automatic by default" MVP requirement; manual approval is the opt-in Advanced exception)
- An update history list: 2-3 past entries, each showing version, date, and a one-line change summary (reusing the `.mini-log`/`.mini-log-row` pattern already used on the dashboard's device card)
- A rollback status line noting the previous version is retained and automatic rollback covers failed updates (satisfying the NFR: "A/B rollback covers failed updates")

**Navigation — two entry points:**
1. **Advanced Hub:** add an 8th `.dcard` to `advhub`'s grid, label "Firmware Updates", following the exact pattern established in Phase A's Task 2 (label text must exactly match a new `textLinkMap` entry `'Firmware Updates':'advupdates'`)
2. **Settings:** the "Update router" row (which lost its trailing chevron in Phase A's Task 7, since nothing existed to link to at the time) gets the chevron re-added, and its label "Update router" gets a new `textLinkMap` entry pointing to `advupdates`

Both entry points route to the same screen — no duplication of content.

---

## Gap 5: Offline / "can't reach your router" state

**Finding:** No screen shows an explicit offline/unreachable state; the dashboard's status card is always the green "Everything is working" state (SRS FR-04: "stale data (daemon unreachable) → explicit 'can't reach your router' state, never a false green"; FR-11: local features stay available, cloud-dependent ones are clearly labeled unavailable rather than silently failing).

**Scope decision (made during brainstorming):** since this is a static prototype with no real connectivity to simulate, the fix is a single representative offline state on the Dashboard (the primary status surface), not a rewrite of every screen's data-loading assumptions.

**Fix — new offline dashboard state:**
When active, the `dashboard` screen's status card swaps from the green "Everything is working" card to a grey, dashed-border card reading "Can't reach your router" with a last-seen timestamp and a plain-language nudge ("Check it's powered on"). Below it, the quick-actions row is split into two labeled groups:
- **"Still available on this Wi-Fi"** — Pause All, Guest Wi-Fi, Restart (all fully local actions, remain enabled)
- **"Needs internet"** — Remote Access (shown visually dimmed/disabled, per FR-11's "clearly labeled unavailable" requirement, not silently missing)

**Fix — reachability:** Add a small "Simulate offline" link to the `help` screen (Help & Fixes — fits its troubleshooting theme), which toggles a piece of view state and re-renders the `dashboard` screen content between its normal and offline variants. Implementation approach: extend the existing delegated click-handler pattern with a new `data-goto`-adjacent affordance (e.g. a link with a distinct data attribute, e.g. `data-toggle-offline`) that flips a boolean in `state` and calls `render()` when the current/target screen is `dashboard` — following the same lightweight `state` object + `render()` pattern already used for screen navigation, not a new architecture.

---

## Files touched (all within `sadd-website.html`)

- `screens` object: `mfa`, `devices`, `advnetwork`, `advhub`, `advvpn`, `settings`, `dashboard`, `help` modified; new key `advupdates` added.
- `screenMeta` object: new entry `advupdates: 'app'`.
- `pageTitles` object: new entry `advupdates: 'Firmware Updates'`.
- `textLinkMap` object: new entries for `'Firmware Updates':'advupdates'` and `'Update router':'advupdates'`.
- `<script>` block: small addition to `state`/`render()` for the offline-preview toggle (Gap 5 only — all other gaps are pure markup/data changes, no new JS logic).

## Testing

No test suite exists for this project (static prototype). Verification is the same pattern used throughout Phase A: Python `json.loads`/`json.dumps` round-trip checks confirming the `screens`/`screenMeta`/`pageTitles`/`textLinkMap` objects stay valid JSON/JS after each edit, `grep`-based presence/absence assertions for specific markup, and a final manual click-through per gap.
