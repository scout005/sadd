# Sadd Mobile App — Design

**Status:** Approved
**Scope:** A new, separate file (not a modification of `sadd-website.html`). Phase D of the ongoing multi-phase effort — Phases A/B/C all live in `sadd-website.html` (bug fixes, requirement gaps, local-first onboarding redesign); this phase is a distinct, purpose-built mobile-only prototype.

## Background

The user asked for a new mobile app interface with its own onboarding flow (barcode scan or Bluetooth pairing, chosen explicitly by the user — not a default-plus-fallback pattern) and a minimal post-setup control surface (Devices / Network / Settings as a bottom tab bar), including a device auto-quarantine model with four named network categories a device can be reassigned to. This is deliberately simpler and more narrowly scoped than `sadd-website.html`'s full feature set (no Parental Controls screen, no Security dashboard, no Remote Access/VPN, no Advanced Mode, no desktop layout) — a focused mobile app covering only setup + device/network/admin control.

## Why a new file, not a revision of `sadd-website.html`

Confirmed during brainstorming: `sadd-website.html` already has a working, reviewed, desktop-capable responsive shell (mobile + desktop layouts sharing one `screens` object, Advanced Mode, 30+ screens). This new design is phone-only, has a different onboarding flow (Bluetooth instead of Ethernet cable, a combined router-name+admin-password step, no dedicated device-discovery scan screen), and a much smaller main-app surface. Building it as a new file avoids destabilizing the existing, already-shipped prototype and avoids forcing an artificial mobile/desktop split onto a design that was never meant to have a desktop mode.

**File name:** `sadd-mobile-app.html`, at the project root (sibling to `sadd-website.html`).

**Architecture:** Same proven pattern as `sadd-website.html` — a `screens` object (one key per screen, HTML-as-string), `forwardMap` for primary-button navigation, `.page-crumb`/`data-goto` for explicit navigation, a delegated click handler on `document.body`. No dual mobile/desktop `data-view` split — every screen is phone-width only. No `screenMeta`/Advanced-Mode distinction needed (there is no Advanced Mode in this app). Visual design system (colors, fonts, button/card shapes) matches `sadd-website.html`'s existing CSS (`--teal:#0D9488`, pill buttons, rounded cards, Baloo 2/Nunito-style type treatment) for brand consistency, but the stylesheet is a fresh, trimmed-down set — only the CSS rules this app's screens actually use, not a copy of the full `sadd-website.html` stylesheet.

## Screens

### Onboarding (7 screens)

**1. Connect** — Two equal-weight tappable cards, no default: "Scan Barcode" (camera icon) and "Connect via Bluetooth" (Bluetooth icon), each with a one-line description. This is the entry screen.

**2a. Scan Barcode path** — two screens:
- **Scanning**: a camera-viewfinder placeholder (reusing the decorative `.qr-box`-style pattern already established in `sadd-website.html`, adapted to look like an active scan target) with instructional text ("Point your camera at the barcode on your router").
- **Found**: confirmation state ("Router found!") with a Continue button.

**2b. Bluetooth path** — two screens:
- **Searching**: "Searching for nearby routers…" with a loading/spinner treatment.
- **Found**: shows the discovered router's name/ID with a "Connect" button (pairing confirmation).

Both paths converge on the same next screen (step 3) once connected.

**Fidelity note (applies to both paths):** this is a static prototype with no real camera or Bluetooth hardware integration anywhere in this project — the "scanning"/"searching" states are demo copy and static visuals representing the intended behavior, advanced by a plain Continue-style tap, exactly matching how `sadd-website.html`'s own QR/scan screens work (e.g. its `scan-banner` "Cable connected" state). Not a build instruction for real camera/BLE APIs.

**3. Router & Admin** — One combined screen: router name field + new admin password field (replaces the router's factory default). Required, no skip.

**4. Wi-Fi Setup** — Wi-Fi network name + Wi-Fi password fields. Required, no skip.

**5. All Set** — Brief success confirmation ("You're all set!"), single Continue button. Leads into the main app, landing on the Devices tab.

### Main app (bottom tab bar: Devices / Network / Settings)

Persistent 3-item bottom tab bar on every main-app screen, reusing `sadd-website.html`'s existing `.bottomnav`/`.bn-item` pattern. **Devices is the default/active tab** immediately after onboarding completes.

**6. Devices** (tab 1, default) — List of connected devices (icon, friendly name, status). Newly-joined devices are visually flagged (badge, matching the `.badge-new`/flagged-row treatment already established in `sadd-website.html`'s Phase B work) and are, by default, placed in an isolated **Quarantine** network: the device has internet access but cannot reach other devices or other network categories until explicitly reassigned.

**7. Device detail** (reached by tapping any device in the list) — Mirrors `sadd-website.html`'s existing per-device controls exactly, adapted to single-column mobile layout:
- Pause internet (timer chips: 15 min / 1 hr / Until tomorrow)
- Bedtime schedule toggle
- **Move to network** — a selector with exactly these options: **Kids, Family, IoT devices, Guest network** (plus implicitly "Quarantine" as the un-assigned starting state, not itself a selectable target once a device has been moved out of it)
- Block this device
- Forget this device

**8. Network** (tab 2) — Wi-Fi name and password, viewable and editable. One-tap guest network on/off toggle. Does **not** manage the four device-network categories directly — category (re)assignment happens only from the device detail screen (per explicit product decision during brainstorming), keeping this screen scoped to the physical Wi-Fi network itself.

**9. Settings** (tab 3) — Change admin password, about/help entry, "forget this router" action.

## Network categories (data model note)

Four named, predefined categories a device can be assigned to: **Kids, Family, IoT devices, Guest network**. "Family" is the trusted/default network (conceptually replacing "Main Network" terminology used elsewhere in the project). **Quarantine** is not a 5th selectable category in the UI — it's the automatic, unassigned starting state every new device begins in, distinct from the four named destinations a device gets moved *to*.

## Explicitly out of scope for this app

- Parental content-filtering/schedule details beyond the "Kids" network category assignment itself (no separate Parental Controls screen).
- Security status dashboard, ad blocking, remote access/VPN, firmware update screen, Advanced Mode — none of these exist in this app; it is intentionally narrower than `sadd-website.html`.
- Desktop/tablet layout — phone-only.
- A dedicated device-discovery/scan onboarding step (unlike `sadd-website.html`'s `discover` screen) — devices appear organically on the Devices tab as they connect, post-setup.

## Testing

No test suite exists for this project (static prototype). Verification follows the same pattern as Phases A/B/C: Python `json.loads`/`json.dumps` round-trip checks for the `screens` object, `grep`-based presence/absence assertions, a Node `new Function()` full-script parse check (given a prior phase's real syntax-error bug caught during review), and a final manual click-through covering both onboarding paths (barcode and Bluetooth) and the full tab-bar surface.
