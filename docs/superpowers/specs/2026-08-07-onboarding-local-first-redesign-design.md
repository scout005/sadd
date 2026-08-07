# Onboarding Local-First Redesign — Design

**Status:** Approved
**Scope:** `sadd-website.html` only. Sub-project 3 of the ongoing multi-phase effort (Phase A: bug fixes, complete. Phase B: requirement gaps, complete. This is Phase C: onboarding re-architecture).

## Background

The current onboarding sequence in `sadd-website.html` is `welcome → signup → mfa → setup → discover → success`. This forces cloud account creation and MFA verification before any local router setup (Wi-Fi naming, admin password change) can happen.

This directly contradicts:
- **SRS FR-01** — first-run setup must complete in under 5 minutes "with no internet or account required."
- **Backlog Confirmed Product Decision #1** — "LOCAL-FIRST, CLOUD-SECOND... Router is fully secured and usable on the local network with zero internet/account required... Cloud account is optional, created whenever internet becomes available."
- **US14.1** (Must, MVP) — "No internet connection or account creation is required to complete local Wi-Fi and security setup."
- **US14.3** (Must, MVP) — account creation "can be started any time after local setup completes, not only during first-run."

This spec reorders onboarding so every required security step is local-only, and moves account/MFA creation to a separate, optional, post-setup entry point.

## Screens

All screens follow this file's existing `screens`/`screenMeta`/`pageTitles`/`textLinkMap`/`forwardMap`/`backMap` conventions — no new architecture, only new/reordered screen content and updated navigation maps.

### 1. `welcome` (rebuilt in place — currently exists but is the pre-account "Let's get your home Wi-Fi ready" splash; becomes the connect step)

Instructs the user to scan the QR code printed on a sticker on the router itself (bottom or back — matches US14.2/US19.2's factory-provisioned label). The sticker's QR is a **single combined code** encoding both (a) the temporary setup Wi-Fi's SSID/password (`Sadd-Setup-XXXX`, per-unit unique) and (b) the router's unique default admin credential — one scan joins the phone to the temp network and authenticates it to the local API in the same motion, so the user never types anything at this stage.

- Primary path: a QR visual using the existing `.qr-card`/`.qr-box` decorative pattern already used elsewhere in this file (guest network, connect-device screens) — this is a static prototype with no real camera integration anywhere, so "scanning" is represented the same way those other screens already represent it: decorative QR box + explanatory text + a `.btn-primary` that advances via `forwardMap` (simulating "scan complete"), not an actual camera trigger.
- Secondary path (toggle, matching the existing Family/Guest and Easy/Manual toggle pattern already used elsewhere in this file): "Connect with a cable instead" — Ethernet fallback for when the camera/QR isn't usable.
- A "Looking for your router…" scanning/waiting state confirms the local API is reachable before advancing (mirrors the existing `scan-banner` pattern already used in the discover screen) — same static-demo fidelity, not real network polling.
- Error handling copy only (this is a static prototype, no functional retry logic to implement): QR unreadable/damaged → manual fallback shows the SSID/password as plain text (same info, no scanning); local API unreachable → plain-language retry copy ("Still looking… make sure your router is powered on") — never a dead end, consistent with the rest of the file's fidelity level (copy/UI representing the intended behavior, not working logic).

### 2. `changepassword` (new — currently the admin-password step is folded into onboarding differently; this is now its own explicit step, first in the required sequence)

Required, no skip (matches existing non-skippable pattern used by Wi-Fi naming today). Opens already authenticated (via the QR scan's embedded default credential), asks only for the new admin password.

### 3. `setup` (existing screen, reused as-is — "Name your Wi-Fi")

Unchanged content. Required, no skip, same as today.

### 4. `recoverycode` (new)

One auto-generated recovery code, displayed once, large and copyable/screenshot-able. A confirmation checkbox ("I've saved this") gates the Continue button — matches the pattern already used for one-time-reveal secrets elsewhere in the product concept. This is the offline-capable local security factor (protects the local admin login independent of any cloud account); no TOTP/authenticator-app enrollment is offered at this stage — that remains an Advanced-mode option reachable later, not part of first-run.

### 5. `discover` (existing screen, reused as-is — "Find devices")

Unchanged content and behavior — stays skippable (Should priority, not Must).

### 6. `wancheck` (new)

Silent WAN reachability check. Two outcomes, both non-blocking (Continue is always enabled regardless of result — this was an explicit product decision made during brainstorming, not a default assumption):
- **Online:** brief green confirmation, auto-advances or one-tap continue.
- **Offline:** plain-language message ("No internet yet — that's OK, your Wi-Fi and security are ready") with a "Check again" retry action (static demo — no real polling logic, same fidelity as the rest of this task). No countdown, no forced wait, no dead end — Continue remains available throughout.

### 7. `success` (existing screen, reused as-is — "Your Wi-Fi is ready!")

Unchanged. Reached without the user ever having touched an account or MFA screen.

## Post-setup: optional account creation

`signup` and `mfa` (existing screens, content unchanged) are removed from the onboarding `forwardMap` chain entirely. They become reachable only via:
- A new dismissible banner/card on the `dashboard` screen, shown only when `wancheck` found the router online AND no account is linked — "Want to check on things when you're away? Set up remote access" — leading into the existing `signup → mfa` flow.
- The existing "Log in" path for returning users (unchanged).

## Navigation map changes

- `forwardMap`: `welcome → changepassword → setup → recoverycode → discover → wancheck → success → dashboard`. `signup`/`mfa` removed from this chain.
- Back-navigation: this file has no `backMap` (removed as dead code during Phase A) — each screen carries its own `.page-crumb` element with an explicit `data-goto` target. Every new/repositioned screen's crumb is updated to point to its new predecessor in the sequence above.
- `textLinkMap`: no changes needed for onboarding screens (they use `forwardMap`, not text-matched navigation); a new entry is needed for the dashboard's new "Set up remote access" banner → `signup`.
- `screenMeta`: `changepassword`, `recoverycode`, `wancheck` are all `'auth'` type (same shell as the rest of onboarding).

## Explicitly out of scope for this pass

- Bluetooth as a third connection method (Wi-Fi QR + Ethernet fallback covers it).
- Distinguishing factory-fresh vs. factory-reset unit flows (same flow serves both for MVP).
- Multi-person/concurrent setup handling.
- TOTP/authenticator-app enrollment during first-run (available later via Advanced Mode, not part of this redesign).
- Any change to the `signup`/`mfa` screens' own content — only their position in the flow changes.

## Testing

No test suite exists for this project (static prototype). Verification follows the same pattern as Phases A/B: Python `json.loads`/`json.dumps` round-trip checks for the `screens`/`screenMeta`/`pageTitles` objects, `grep`-based presence/absence assertions for `forwardMap`/`backMap`/`textLinkMap` changes, and a final manual click-through confirming the full local-only path reaches `success` without ever visiting `signup`/`mfa`, plus a separate click-through confirming the dashboard banner correctly leads into the (unchanged) account-creation flow.
