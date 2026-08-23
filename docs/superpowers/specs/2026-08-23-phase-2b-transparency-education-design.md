# Phase 2b — Transparency & Education — Design

**Status:** Approved
**Scope:** Closes the remaining clean-Missing P0 gaps in Epic 4 (Transparency & Explainability) and Epic 16 (Beginner-First Education) identified in `docs/superpowers/specs/2026-08-22-phase-2-gap-analysis-findings.md`.

## Stories in scope

| Story | File(s) | Summary |
|---|---|---|
| `US-4.1` | `sadd-website.html` | Plain-English explanation for every blocked connection. |
| `US-4.4` | `sadd-website.html` | "Why was this blocked" + inline one-tap allow/unblock. |
| `US-16.1` | `sadd-website.html` | In-app plain-language glossary/primer, accessible standalone from Settings/Help. |
| `US-16.2` | `sadd-website.html` + `sadd-mobile-app.html` | Setup opens with a comfort-level question; both paths remain fully guided and never gate a Simple user. |

## Design

### `sadd-website.html` — block-detail tap-through (`US-4.1`, `US-4.4`)

The existing static `.mini-log-row` entries on `dashboard` and `security` (e.g. "Malicious domain blocked · 2 days ago") become tappable, navigating to a new `blockdetail` screen containing: what was blocked (plain language, no raw rule IDs), which device it was on, when, and a "This looks wrong — allow it" button. Implementation note: `.mini-log-row` isn't currently in the generic `textLinkMap`-driven row-click set (`.nav-card, .adv-row, .setting-row, .dcard`) — the click handler's row-matching selector needs `.mini-log-row` added to it, and the row text needs to resolve via `textLinkMap` same as other rows, OR each row gets a direct `data-goto="blockdetail"` attribute (simpler, avoids touching the shared handler's selector list — preferred approach).

### `sadd-website.html` — standalone Glossary (`US-16.1`)

New `glossary` screen reached from `help` via a new row "Networking glossary". Content: a `.setting-row`-styled list of ~8 common terms (VLAN, VPN, IP address, DNS, Firewall, Guest network, IoT, Bandwidth) each with a one-line plain-language definition. No app-wide tap-linking of every jargon occurrence — that's a much larger, cross-cutting UI pattern not practical to retrofit across 30+ existing screens in this pass; the standalone glossary satisfies the "accessible standalone from Settings/Help" half of the AC, which is the achievable slice for a prototype.

### `sadd-website.html` — comfort-level onboarding question (`US-16.2`)

New `comfortlevel` screen inserted as the new first step of onboarding, before `changepassword`. Two equal-weight cards: "I'm new to this" and "I know networking" — both, in this prototype, proceed to the same `changepassword` next screen (real pacing branches aren't representable in a static mockup without duplicating the entire flow). The `welcome` screen's existing forward action now points to `comfortlevel` instead of `changepassword`.

### `sadd-mobile-app.html` — comfort-level onboarding question (`US-16.2`)

Same pattern: new `comfortlevel` screen inserted before `admin` in the onboarding chain (after the connect/scan/Bluetooth path converges), both choices proceeding to `admin` identically.

## Out of scope

- App-wide tap-to-define jargon linking (only the standalone glossary is built).
- Any pacing/depth difference between the two `US-16.2` onboarding paths — both are cosmetically identical in this static prototype.
- Weekly "Network Health" summary (`US-4.5`, P1, not in this pass) and log filtering (`US-4.3`, P1, Advanced).
- Video walkthroughs (`US-16.3`) and the accessibility sub-stories (`US-16.4a/b/c`) — separate, larger pieces of work.

## Testing

Same pattern as Phase 2a: Python `json.loads`/`json.dumps` round-trip verification for `sadd-website.html`, Node `new Function()` parse-check for `sadd-mobile-app.html`, plus grep presence checks and a manual click-through before push.
