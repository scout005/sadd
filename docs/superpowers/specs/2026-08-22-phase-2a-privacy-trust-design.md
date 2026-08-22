# Phase 2a — Privacy & Trust Foundation — Design

**Status:** Approved
**Scope:** Closes the highest-priority P0 gaps identified in `docs/superpowers/specs/2026-08-22-phase-2-gap-analysis-findings.md`: Epic 11 (Privacy & Data Handling, ~0% covered), `US-14.3` (no shared/fixed SSH backdoor), and `US-15.1` (manufacturing-origin disclosure).

## Background

The Phase 2 gap analysis found Epic 11 almost entirely uncovered in both prototypes — the only privacy-adjacent artifact anywhere is a boilerplate "I agree to the Terms and Privacy Policy" checkbox on `sadd-website.html`'s `signup` screen. This is a striking gap given Epic 11 is the epic that formally resolved Sadd's own open product question about local-first data handling (`home-router-user-needs-analysis.md` §6.6) in the v0.2 backlog pass. `US-14.3` (no SSH backdoor) and `US-15.1` (origin disclosure) are both P0, both have a real UI touchpoint, and both are currently fully Missing.

## Stories in scope

| Story | File(s) | Summary |
|---|---|---|
| `US-11.1` | `sadd-website.html` | Local-only traffic inspection by default; opt-in cloud sync with explicit consent screen. |
| `US-11.2` | `sadd-website.html` | Configurable local log retention (7/30/90 days); cloud retention opt-in only. |
| `US-11.3` | `sadd-website.html` | Self-service account/data deletion entry point. |
| `US-14.3` | `sadd-website.html` | User-controllable remote/support access (SSH) toggle; no shared/fixed credential. |
| `US-15.1` | `sadd-website.html` + `sadd-mobile-app.html` | In-app "About" screen: manufacturing/country-of-origin disclosure. |

## Design

### `sadd-website.html` — new `privacy` screen (Simple Mode)

Reached from `settings` via a new row "Privacy". Content:
- Header stating the local-first default in plain language (mirrors the existing `security` screen's toggle-hero pattern for visual consistency).
- A single toggle: "Share diagnostic data with the cloud" — off by default — with a one-line explanation of exactly what would be uploaded if turned on (device counts and threat categories, never browsing history/content).
- A retention selector: three radio options (7 days / 30 days / 90 days) for local log retention, with a note "Cloud retention: only if diagnostic sharing is on above."
- A `btn-ghost`-style "Delete my account and data" row at the bottom, opening a simple confirm-style secondary screen or inline expand (not a multi-step flow — this is a prototype, not a production deletion pipeline) stating data will be deleted within 30 days.

### `sadd-website.html` — new `about` screen (Simple Mode)

Reached from `settings` via a new row "About". Content:
- App version (reuse whatever version string convention `advupdates` already uses, if any, for consistency).
- Manufacturing/country-of-origin line, e.g. "Designed and assembled in [origin] — see our compliance statement" (plain-language, no legal jargon, matching Sadd's voice).
- No links to the Pricing Promise or Built-on-OpenWrt public pages — those don't exist as screens in this prototype and are out of scope here (per the gap analysis' note that public-page stories need a separate scope decision).

### `sadd-website.html` — SSH toggle in `advapi` (Advanced Mode)

Add one new row to the existing `advapi` ("Developer & API Access") screen, below the existing API key/webhook content: a toggle "SSH access" (off by default) with a one-line explanation: "Disabled by default. When enabled, uses a unique key generated for this device — never a shared or default password." This is additive to the existing screen, not a new screen.

### `sadd-mobile-app.html` — wire up the existing About row

The `settings` screen already has an inert "Help & About" row (no `data-goto`, dead per the gap analysis). Add a `data-goto="about"` to it and a new `about` screen (same content as the website's About screen, adapted to the mobile app's simpler single-column style, no Advanced/Privacy content since those are out of this file's scope).

## Out of scope

- No changes to `sadd-mobile-app.html` beyond the About screen wiring — no Privacy screen added there in this pass.
- `US-14.1`/`US-14.2` (public CVE/disclosure pages) — not addressed; these need a scope decision (do public pages belong in these prototype files at all) before any implementation.
- The VPN engine (WireGuard vs. OpenVPN) mismatch — untouched in this phase.
- Any other Phase 2b/2c/2d items from the gap analysis' recommended sequencing.

## Testing

Same pattern as prior phases: for `sadd-website.html`, Python `json.loads`/`json.dumps` round-trip verification of the `screens` object (its existing single-line JSON-escaped format) plus grep-based presence checks. For `sadd-mobile-app.html`, Node `new Function()` parse-check on the extracted `<script>` block (its existing template-literal format) plus grep checks. Manual click-through of the new screens in both files before commit.
