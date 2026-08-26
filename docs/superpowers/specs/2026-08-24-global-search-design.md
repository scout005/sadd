# Global Search — Design

## Goal

Add a global search to both prototypes that can find devices, people, apps, settings/config pages, activity/security log entries, and config values (ports, IPs, domains, VLAN subnets, blocked countries) — then jump to the right screen and highlight the exact matching record, not just the page it's on.

## Placement

**Desktop/tablet (`sadd-website.html`):** A persistent search input in `.app-topbar`, between `.app-topbar-title` and `.app-topbar-actions`. Always visible, no click-to-reveal step (confirmed via visual mockup — Option A). An instant-results dropdown panel opens beneath the bar as soon as the input is non-empty.

**Mobile (`sadd-mobile-app.html`):** A search icon in each screen's header opens a full-screen search view (input + instant results), sized for the phone frame. The mobile app has no shared top-bar element like the desktop shell — this needs its own investigation into whether screens share a common header-rendering path (see Open Questions).

## What's searchable

One flat JS array, `searchIndex`, of records with this shape:

```js
{
  type: 'device' | 'person' | 'app' | 'setting' | 'log' | 'rule' | 'network',
  label: string,       // primary bold line, e.g. "Xbox Series X"
  sub: string,         // context line, e.g. "External 3074 → 192.168.1.45:3074 · Firewall & Ports"
  screen: string,      // key into the `screens` object to goTo()
  matchText: string,   // a substring expected to appear in that screen's rendered DOM, used to locate + highlight the element after navigating
  keywords: string,    // extra space-separated search terms not visible in label/sub (e.g. "xbox nat forward" for a port rule)
}
```

Populated from a full survey of the 48 desktop screens (already done this session — every screen has been read/reviewed in detail):

- **Devices** (~5): Emma's iPhone, Living Room TV, Leo's Laptop, Kitchen Speaker, Unknown device
- **People** (~5): Emma, Leo, Jenna Miller, Mark, Grandma
- **Apps** (~4): TikTok, Instagram, YouTube, Roblox
- **Settings/config pages** (~25): every sidebar item and reachable sub-page (Wi-Fi name, Guest network, Firewall & Ports, VPN Server, Network & VLANs, Traffic & QoS, Multi-WAN, Diagnostics & Logs, Developer & API, Privacy, About, etc.) — page title + a couple of descriptive keywords each
- **Activity/security log entries** (~15–20): the existing sparse entries across `advlogs`, `security`/`blockdetail`, `connectionhealth`, **plus new entries added specifically to prove out the port/site-block use case** (e.g., "Inbound connection blocked on port 3074", "social-app.example.com blocked for Emma's iPad")
- **Config values / rules** (~10): the 2 port-forwarding rules (Xbox, Home Security NVR), 5 VLANs (Main/Kids/IoT/Guests/Quarantine), 5 geo-IP blocked countries, MFA methods

Total index size: roughly 90–120 records.

## Instant results UI

- Debounced input listener (no debounce delay needed for an in-memory array — filters synchronously on every keystroke).
- Match logic: case-insensitive substring match against `label`, `sub`, and `keywords`, combined; simple relevance ordering — label-starts-with-query first, then label-contains-query, then keyword match.
- Results grouped by `type` under an uppercase label (e.g. "CONFIG · PORT FORWARDING", "ACTIVITY LOG", "DEVICES"), capped at ~4 per group to keep the dropdown a reasonable height.
- Matched substrings wrapped in `<mark>` inside the rendered `label`/`sub`.
- Each row shows a right-aligned action chip ("Jump to rule", "Jump to log", "Open").
- Keyboard support: `↓`/`↑` move a `.active` selection through the flattened result list, `Enter` activates the selected (or first) result, `Esc` closes the panel and blurs the input. Click-outside also closes it.
- Empty query → panel hidden.

## Click-through / highlight behavior

1. Close the results panel, clear/blur the input (query text does not persist across navigation).
2. `goTo(result.screen)` — same mechanism already used by every `data-goto` link in the app.
3. After the screen re-renders, locate the DOM element whose `textContent` includes `result.matchText` (walking up to the nearest meaningful row container — `.setting-row`, `.rule-row`, `.list-item`, `.tech-row`, etc.), call `scrollIntoView({behavior:'smooth', block:'center'})` on it, and apply a temporary highlight (a CSS class adding a brief colored outline/background pulse) that removes itself after ~2 seconds via `setTimeout`.
4. If no matching element is found on the rendered screen (index/content drift), fail silently — just leave the user on the target screen with no highlight, rather than erroring.

## Non-goals / explicitly out of scope

- No fuzzy matching / typo tolerance — plain substring matching is enough for a prototype's search-bar demo.
- No search history or recent-searches list.
- No cross-session persistence of anything search-related.
- Not wiring search into `sadd-website.html`'s tablet/phone responsive breakpoints as a separate compact treatment — the persistent bar's own CSS should degrade reasonably at the existing breakpoints already in the file; a dedicated compact mode is not required by this design.

## Open questions for the implementation plan

- **Mobile header structure:** need to confirm during planning whether `sadd-mobile-app.html`'s 16 screens share a common header-rendering path (so the search icon can be added once) or whether each screen's template embeds its own header markup (requiring ~16 individual edits). This changes the task breakdown but not the design.
- **Highlight CSS:** exact color/animation for the temporary highlight pulse will be chosen to match each file's existing design tokens (teal accent) during implementation, not prescribed pixel-for-pixel here.
