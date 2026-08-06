# Sadd Website — Bug Fixes (Phase A) Design

**Status:** Approved
**Scope:** `sadd-website.html` only — no new screens, no new patterns.

This is sub-project 1 of 3 in a larger effort (bugs → requirement gaps → new OpenWrt-coverage screens) against the `sadd-website.html` prototype, based on findings from a tester/reviewer pass (see conversation history — no separate findings doc was written, findings are reproduced below per-fix).

---

## Background

`sadd-website.html` is a single-file JS-driven SPA prototype: a `<script>` block defines `const screens = {...}` (28 keys, one per screen, HTML-as-string), `screenMeta` (auth vs. app shell), `pageTitles`, and a `render()` function swapping `screens[state.screen]` into the DOM. Navigation is via `data-goto="<key>"` attributes read by a delegated click handler.

A tester/reviewer pass (via the `superpowers:code-reviewer` agent) found 4 issues, all now scoped for this phase.

---

## Fix 1: Onboarding back-navigation

**Problem:** `signup`, `mfa`, `setup`, `discover` are `auth`-type screens (sidebar/bottom-nav hidden). The codebase has a `.back-btn` CSS class and a `backMap` object wired up in the delegated click handler, but **zero elements with class `back-btn` exist in any screen's HTML** — dead code. A user who reaches MFA and needs to fix a typo on Create Account has no way back.

**Fix:** Use the `.page-crumb` pattern already working on other screens (`guest`, `advvpn`, `adblock`, `devcontrols`, `connectdevice`, `laptopvpn`) — a `data-goto`-driven breadcrumb/back link, not the unused `.back-btn`/`backMap` path. Add one `.page-crumb` to each of the 4 screens, pointing to the previous screen in sequence:
- `signup` → `welcome`
- `mfa` → `signup`
- `setup` → `mfa`
- `discover` → `setup`

**Cleanup:** Remove the now-fully-dead `.back-btn` CSS rule and the `backMap` object + its handler branch from the script, since nothing will reference them after this lands.

---

## Fix 2: Mobile access to 3 Advanced screens

**Problem:** `advvpn` (VPN Server), `advlogs` (Diagnostics & Logs), `advapi` (Developer & API) are absent from the Advanced Hub's card grid (only 4 of 7 sub-screens are linked there) and absent from the mobile bottom nav. `.app-sidebar` is `display:none` below 860px, so on mobile there is no route to these 3 screens at all.

**Fix:** Add the 3 missing cards to `advhub`'s existing card grid, in the same visual/markup style as the current 4 (Network & VLANs, Firewall & Ports, Traffic & QoS, Multi-WAN & Failover). No new navigation pattern — just completing the grid. This restores reachability on every viewport, since the Advanced Hub itself is already reachable from Settings on both mobile and desktop.

---

## Fix 3: Remove orphaned `connectrouter` screen

**Problem:** `connectrouter` ("Connect to your router" — temporary Wi-Fi pairing, e.g. join `Sadd-Setup`) exists in `screens`/`screenMeta`/`pageTitles` but is referenced by nothing — no `data-goto` anywhere points to it. It's also absent from `docs/sadd-sitemap.html`'s documented onboarding flow (`Welcome → Create Account → Verify → Name Wi-Fi → Find Devices → Complete`), confirming it's leftover concept art from an earlier physical-AP-pairing design that was superseded by the account-based flow.

**Fix:** Delete the `connectrouter` entry from `screens`, `screenMeta`, and `pageTitles`. No flow changes needed elsewhere since nothing currently points to it.

---

## Fix 4: Misleading Bedtime chevron

**Problem:** The Bedtime row in `parental` renders a chevron (implying a drill-down sub-screen) but has no `data-goto` or click handler — it's inert, and the chevron misrepresents it as interactive beyond whatever inline control it already has.

**Fix:** Remove the chevron glyph/affordance from the Bedtime row's markup so its visual state matches its actual behavior.

---

## Out of scope for this phase

Everything from the reviewer's "Requirements reviewer" and "UX/UI reviewer" sections (MFA default method, device Block action, remote-access scope split, manual update approval, offline/empty states, guest-password display, color-only toggle states) — these are Phase B (requirement gaps), a separate spec.

New OpenWrt-coverage screens (DHCP reservations, Wi-Fi radio config, DDNS, NTP, IPv6, backup/restore) are Phase C, a separate spec.

---

## Testing

Manual click-through in a browser after implementation:
1. Onboarding: walk `welcome→signup→mfa→setup→discover`, confirm each screen's back-crumb returns to the correct prior screen, confirm no `.back-btn` elements or dead handler paths remain (search the script).
2. Advanced Hub: on a narrow viewport (<860px), confirm all 7 Advanced screens are reachable from `advhub`'s grid.
3. Confirm `connectrouter` no longer appears in `screens`/`screenMeta`/`pageTitles`, and the file's embedded JS object still parses as valid JSON (`json.loads` check, same technique used during the rebrand/notes-removal edits).
4. Confirm the Bedtime row in `parental` no longer shows a chevron.
