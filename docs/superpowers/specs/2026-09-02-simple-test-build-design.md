# Simple Test Build — Simplified Login, Parental Controls Redesign, Dark Mode

## Goal

Produce a second, standalone version of the desktop prototype — `sadd-website-simple.html` — for personal testing use, with three changes on top of the original `sadd-website.html`:

1. Replace the entire multi-screen onboarding/account-creation flow with a single simple login page (username + password), landing directly on the Dashboard (home page) on success.
2. Redesign the Parental Controls screen's content area, which is currently a dense, mixed-component 2-column grid, into a cleaner flat single-column "rows" layout — everything still visible, nothing hidden behind a click.
3. Add a real light/dark theme toggle across the whole app.

`sadd-website.html` itself is never modified — every change in this spec lands only in the new file, created as a full copy of the original before any edits begin.

## Why a separate file, not a mode inside the original

The user's own preference, given directly: a new file is simplest to reason about, carries zero risk to the existing prototype (which many prior waves of real OpenWrt integration work depend on staying intact), and is easy to discard later since this is explicitly a personal test build, not a product change. A same-file toggle was considered and rejected — it would add branching complexity to every future edit of the main file for a need that's inherently temporary.

## 1. Simplified login flow

### Current behavior
`state.screen` initializes to `'welcome'` (`sadd-website.html:653`), the first of a long onboarding sequence (Welcome → Discover → Comfort Level → Setup → Topology → WAN Check → Connection Health → Success → …) before a user ever reaches the Login screen, and Login itself doesn't yet have a wired "Log In" click handler at all (this whole flow is a static, non-functional mockup today). Navigation throughout the app is fully generic — any element with `data-goto="X"` calls `goTo(screen)`, which does `state.screen = screen; render();` (confirmed at `sadd-website.html:809-828` and the global click handler at `:2458-2460`). No screen currently links back to `welcome`/`login`/`signup` (confirmed: no "Log out"/"Sign out" affordance exists anywhere in the app, in the shell chrome or any of the 48 screens' content).

### New behavior
- `state.screen` initializes to a new screen key, `simplelogin`, instead of `welcome`.
- `screens['simplelogin']` is new markup: a centered card (not the current branded split-screen with marketing copy/testimonial/social login/passkey option) — logo mark, "Log in" heading, a Username field, a Password field, a small "For testing: admin / admin" hint, a "Log In" button, and an inline error area (hidden by default).
- A new `handleSimpleLogin()` function: reads the two input values, and if `username === 'admin' && password === 'admin'`, calls `goTo('dashboard')`; otherwise shows the inline error ("Incorrect username or password.") and does not navigate. No network call, no async — this is a pure client-side check against one hardcoded credential, appropriate for a personal test build.
- All 47 other screens (including the entire original onboarding sequence: `welcome`, `signup`, `mfa`, `setup`, `discover`, `comfortlevel`, `topology`, `wancheck`, `connectionhealth`, `success`, `hardware`, `hardwarequiz`, `rightforme`, `glossary`, and the original `login` screen itself) remain fully present in the `screens` object, completely unmodified — they are simply unreachable from the new entry point. Nothing is deleted; nothing else is rewired. If the user later navigates to one of these screens some other way (e.g. a future feature that links to `glossary` from a help menu), it still renders exactly as it does in the original file today.

### Why not delete the unreached screens
Several of them (`hardware`, `glossary`, `rightforme`, etc.) are general marketing/info content that may still be linked from elsewhere in the app outside the onboarding sequence specifically (e.g. a Settings or Help screen), not exclusively onboarding-only. Auditing every cross-reference to determine which are safe to delete is out of proportion to this task's actual goal (skip the flow, don't necessarily prune the file) — leaving them present and simply unreachable from the new entry point is the safe, minimal-risk choice, consistent with "don't delete the current code."

## 2. Parental Controls redesign

### Current layout, audited
`screens['parental']`'s content area (`sadd-website.html`, the `parental` key) is a `.split-desk` with a Family sidebar (Emma / Leo / Add child — **unchanged by this redesign**, not part of the crowding complaint) and a detail pane that crams, in a 2-column `.grid-2`:
- Left column: Bedtime (icon row), Pause now (toggle), Homework mode (toggle), a "Custom schedule" section with 7 day-chips + a 2-field time-range grid + an Allow/Block pill-toggle.
- Right column: a Content Filter radio-card group (4 large cards), then "All categories" — **15 individual toggle rows** crammed into half-width, then a Safe Search toggle.
- Below the grid (full width): Custom blocked sites (input + add button + list + export), Blocked apps (a 2-column icon-grid of 4 apps + a best-effort disclaimer), Exceptions (a list + add link).

Real data used throughout this section (Emma's profile) — the redesign preserves every real value, it only reorganizes presentation.

### New layout
The detail pane becomes a single-column, section-grouped list of rows (`.psec` section labels: "Schedule", "Content & filtering", "Apps"), each setting one row:

- **Schedule**: Bedtime (display row), Pause now (toggle row), Homework mode (toggle row), Custom schedule (its own block: 7 day-chips + time range, always visible, not collapsed).
- **Content & filtering**: Filter level (a compact inline segmented control — Kid-safe / Teen / Off / Custom — replacing the 4 large radio cards), Blocked categories (all 15 shown as small toggle chips, wrapping across lines — **all 15, not truncated**; the visual mockup's "+8 more" was a space-saving preview device only, not the intended shipped behavior), Safe Search (toggle row), Custom blocked sites (the existing input/add/list/export, kept as-is but styled to match the row rhythm).
- **Apps**: Blocked apps (existing app rows, restyled to match), Exceptions (existing list, restyled to match).

Nothing is hidden behind a click or an expand/collapse — every setting's full detail is visible on page load, per the approved direction. The page is taller (more scrolling) than the current grid in exchange for a single, consistent visual rhythm instead of four different component types (icon-rows, radio-cards, a dense toggle-grid, and an app-icon-grid) fighting for space in two half-width columns.

### What stays untouched
The Family sidebar list, the header row (child name, "Copy to another child", "View weekly usage report"), the weekly-email-report toggle, and the actual underlying data/values are all carried over unchanged — this is a presentation reorganization, not a data or feature change.

## 3. Dark mode

### Audited scope
Confirmed by direct script against the file (not assumed): the shared `<style>` block contains 113 hardcoded hex color occurrences (35 distinct values, `#fff` alone appearing 56 times), and the 48 screens' own inline styles contain 13 more distinct hex values (low-frequency — mostly one-off avatar/icon/status colors). The app already has a `:root` CSS custom-property system (`--teal`, `--bg`, `--card`, `--border`, `--text`, `--muted`, `--muted-2`) that much of the existing CSS already references — this makes theming tractable without a full rewrite.

### Approach
- Add a parallel dark palette as the same variable names, redefined under a `:root[data-theme="dark"]` selector (or equivalent), toggled by setting `data-theme` on `<html>`.
- Go through the `<style>` block's hardcoded structural colors (backgrounds, card fills, borders, body/muted text — `#fff`, `#F1F5F9`, `#0F172A`, `#1E293B`, `#94A3B8`, `#E2E8F0`, `#64748B`, etc.) and point them at the matching CSS variable instead of a literal value, so they follow the theme automatically. **Important**: this classification is per *occurrence*, not per color *value* — `#fff` appears 56 times and plays more than one role (e.g. a card's white background, which must darken, versus white text sitting on a teal button, which must stay white in both themes since the button itself stays teal-colored). Each of the 113 occurrences needs its own read of what it's actually styling before deciding whether it becomes `var(--card)`/`var(--text)`/etc. or stays a literal `#fff` — a blind find-and-replace on the string `#fff` would break button text.
- Brand/status accent colors are left as literal values in both themes, per the approved scope: the teal brand color itself may get a slightly adjusted dark-mode-friendly shade (as shown in the approved mockup — `#0D9488` → `#14B8A6` for better contrast on a dark background) since it's structural/brand-identity, but one-off colors like app icon backgrounds (TikTok's black, Instagram's pink), status colors (red for blocked, green for OK), and category-pill colors stay exactly as they are today in both themes.
- The 13 inline hex values in individual screens are reviewed the same way: structural ones (e.g. an inline `#fff` used as a card background) are converted to `style="...var(--card)..."` (CSS variables work fine inside inline `style` attributes); accent ones are left alone.
- **Toggle placement**: one switch in the sidebar footer (`.sidebar-foot`, confirmed present in the app shell that wraps every logged-in screen — `sadd-website.html:591-616`), so it's reachable from anywhere after login; a matching toggle on the `simplelogin` page itself, for before login.
- **Persistence**: the chosen theme is saved to `localStorage` and re-applied on page load, so the choice survives a reload. No backend involved — this is a static file.

### Known limitation, disclosed
This is a structural-only theme, not an exhaustive one. If a future addition to the app introduces a new hardcoded color without routing it through the CSS variable system, it won't automatically respond to the theme toggle — the same category of gap that already exists informally today (colors added inline rather than via a class), just now visible as a dark-mode inconsistency instead of invisible. Not fixed by this task; worth a passing mention if anyone extends `sadd-website-simple.html` later.

## Testing

No browser is available in this environment (established throughout this whole project's prior frontend work) — verified the same way every other frontend task in this session has been: `node --check` (or equivalent) on the extracted `<script>` block, a fresh `JSON.parse` of the `screens` object confirming the expected key count and that untouched screens are byte-identical to the original file, and careful manual tracing of the new login-check logic and the theme-toggle logic against the DOM structure being built. The color-audit script used to size the dark-mode task (counting hex occurrences in `<style>` and in `screens`) is re-run after the conversion to confirm the structural colors were actually converted and the accent colors were correctly left alone — a concrete, checkable proxy for "did the conversion match what was designed," not just eyeballing the diff.

## Non-goals

- No change to `sadd-website.html` itself.
- No deletion of any of the 47 now-unreached onboarding/marketing screens.
- No new sub-screens or navigation for Parental Controls' expanded detail (explicitly rejected in favor of the flat, nothing-hidden layout).
- No `prefers-color-scheme`/OS-following dark mode — this is an explicit manual toggle only, matching what was shown and approved.
- No change to any other screen's layout (only `parental`'s content pane is redesigned this task; other crowded pages, if any, are a separate future request).
- No real authentication, session management, or credential storage beyond the one hardcoded test pair — this is a local test build, not a security-hardened login.
