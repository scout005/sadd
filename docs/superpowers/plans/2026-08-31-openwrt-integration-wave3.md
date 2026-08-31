# Real OpenWrt Integration — Wave 3 (Settings rows + Guest Wi-Fi toggle) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `settings` screen's "Wi-Fi name & password" and "Guest network" row values real, and make the `guest` screen's on/off toggle a real write control against `uci wireless` — the first Wave 3 proof that write-capability generalizes beyond firewall rules (Wave 1) to a second config subsystem.

**Architecture:** Same infrastructure as Waves 1-2 — no environment changes. One new endpoint (`/cgi-bin/api/wifi`, GET + POST) following the `firewall-rules` write-endpoint pattern (verify-before-commit, `uci revert` rollback on partial failure, differentiated HTTP status codes). Frontend follows the now-four-times-proven pattern (`state.<screen>RenderId`, `fetchRouterApi`, `escapeHtml`, correctly-scoped `.api-fallback-notice`).

**Tech Stack:** Same as Waves 1-2.

**Before Task 1, read this:** `docker/facts.md` §11 — this VM has **no wireless config at all** by default (no wireless hardware for OpenWrt to have auto-detected), confirmed live; a baseline config has to be CREATED by provisioning, not just read, and the exact `uci set` sequence that was confirmed to work is given there — use it, don't re-derive it. Also read `docker/provision/www/api/firewall-rules` (the write-endpoint reference pattern: `shell_quote`, verify-then-commit, `uci revert` rollback, differentiated `Status:` headers) and the current `renderAboutScreen()`/`renderFirewallScreen()` in `sadd-website.html` (frontend reference patterns, including the two real bugs found and fixed in this exact pattern across Waves 1-2 — notice DOM-scope mismatch, and gating success on one field's truthiness instead of the response shape — don't reintroduce either).

---

### Task 1: Provision a baseline wireless config + real `GET /cgi-bin/api/wifi`

**Files:**
- Create: `docker/provision/www/api/wifi` (Lua CGI, GET only for this task — POST/write comes in Task 3)
- Create: `docker/provision/08-provision-wifi-api.sh`
- Modify: `docker/README.md`

- [ ] **Step 1:** The provisioning script must first create the baseline wireless config on the VM (over SSH), using the exact sequence confirmed in `docker/facts.md` §11: `touch /etc/config/wireless`, then `uci set`/`uci commit` a `radio0` (`wifi-device`, `disabled=1`) and a `default_radio0` (`wifi-iface`, `mode=ap`, `network=lan`, `ssid='Smith Family'`, `encryption=psk2`) — matching the mockup's static demo SSID so the "before/after" visual difference in later verification is meaningful, not confusing. Also create a `guest` `wifi-iface` section (separate SSID, e.g. `ssid='Smith Guest'`, `network` pointing at a guest network context — check whether a real `guest` `uci network`/firewall zone already exists from earlier exploration or needs a minimal one; keep this minimal, don't build a full guest-network firewall zone if one doesn't already exist and isn't strictly needed for this task's read-only scope — a `disabled=1` `wifi-iface` section with a plausible ssid is enough for Task 1/2's read-only needs), `disabled=1` to start (matching the mockup's default "Guest network: Off" state). Commit. Confirm this step is idempotent (re-running the provisioning script against an already-configured VM shouldn't fail or duplicate sections — check for existing config before creating, similar in spirit to how other provisioning scripts handle already-done state).
- [ ] **Step 2:** Write the endpoint. `GET /cgi-bin/api/wifi` runs `uci get wireless.default_radio0.ssid` and `uci get wireless.guest.disabled` (or equivalent — confirm exact section/option names against what Step 1 actually created), returns `{"ssid": "...", "guestEnabled": true|false}`.
- [ ] **Step 3:** Verify: fresh VM, run provisioning 01→08, `curl http://localhost:8081/cgi-bin/api/wifi` returns real values matching what you just configured, cross-checked via SSH `uci get`.
- [ ] **Step 4:** Re-verify from a genuinely fresh VM boot (delete `boot.img`, re-fetch, fresh container, provisioning 01→08 in order).
- [ ] **Step 5: Commit**
```bash
git add docker/provision/ docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): provision baseline wireless config, add GET /api/wifi"
```

---

### Task 2: Wire the `settings` screen's two rows to real data

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the CURRENT `screens['settings']` HTML — the "Wi-Fi name & password" row (`<strong>Wi-Fi name & password</strong><span>Smith Family</span>`) and the "Guest network" row (`<strong>Guest network</strong><span>Off</span>`). Only these two `<span>` values become real — everything else on this hub screen (Update router row, and whatever else is below it — read the full screen content, don't assume it's only these rows) stays static. Neither row currently navigates anywhere for editing (no dedicated sub-screen exists, confirmed during Wave 3's design pass) — this task only makes the DISPLAYED VALUES real, it does not add an edit flow.

- [ ] **Step 1:** Add `state.settingsRenderId`. On navigating to `settings`, call `renderSettingsScreen()` (mirroring the established four-screen pattern exactly) — fetch `/cgi-bin/api/wifi`, on success update both spans' text (`ssid` for the Wi-Fi row, `guestEnabled ? 'On' : 'Off'` for the Guest network row) via `id`-based hooks (add `id`s to both spans, following the `aboutVersionValue` precedent), `escapeHtml`'d. Use the corrected, established success-check convention (`data && typeof data === 'object'`, not gating on one field's truthiness — this was a real bug found and fixed on the About screen, don't reintroduce it). On failure, leave both static values as-is with ONE `.api-fallback-notice` covering both rows (not two separate notices) — place it sensibly (e.g. after the Wi-Fi row, before Guest network, or wherever reads most naturally — use judgment, and get the insertion/duplicate-check DOM scope consistent, the exact bug class already found once this wave).
- [ ] **Step 2:** Verify with the real VM running (Playwright): navigate to Settings, confirm both rows show real values, no fallback notice. Test `file://` fallback: static values + one notice, no console errors. Rapid re-navigation test for the race guard.
- [ ] **Step 3:** Regression-check Devices, Firewall & Ports, About, Diagnostics & Logs, and 1-2 search queries.
- [ ] **Step 4: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Settings screen's Wi-Fi/Guest rows to real /api/wifi"
```

---

### Task 3: Add `POST /cgi-bin/api/wifi` — real guest network toggle

**Files:**
- Modify: `docker/provision/www/api/wifi`

**Context:** Follow `docker/provision/www/api/firewall-rules`'s established write-endpoint conventions exactly: `shell_quote()` any interpolated value (though this endpoint's only writable field is a boolean, so injection surface is minimal — still follow the pattern for consistency and defense-in-depth), verify each `uci set` before `uci commit`, `uci revert wireless` and a `Status: 500` response on any partial-failure, differentiated `Status:` headers for bad input (`400`) vs success.

- [ ] **Step 1:** `POST /cgi-bin/api/wifi` reads a JSON body `{guestEnabled: true|false}` (reuse/adapt the minimal hand-rolled JSON body parser from `firewall-rules` — this body shape is even simpler, a single boolean field), sets `wireless.guest.disabled` to the inverse (`disabled='0'` when `guestEnabled:true`, `disabled='1'` when `false` — confirm this is genuinely how the section you created in Task 1 represents enabled/disabled, verify against real `uci show wireless` rather than assuming), verifies the write, commits, runs `wifi reload` (confirmed safe/non-hanging against this VM's phantom radio in `docker/facts.md` §11), responds with the new state.
- [ ] **Step 2:** Verify: `curl -X POST` toggling both directions, confirm real `uci show wireless` reflects the change each time, confirm `GET /cgi-bin/api/wifi` reflects it too. Test an invalid body (missing/non-boolean `guestEnabled`) → confirm `Status: 400` and no config change.
- [ ] **Step 3:** Re-verify from a genuinely fresh VM boot.
- [ ] **Step 4: Commit**
```bash
git add docker/provision/www/api/wifi
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): add POST /api/wifi for real guest network toggle"
```

---

### Task 4: Wire the `guest` screen's toggle to the real write endpoint

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the CURRENT `screens['guest']` HTML — the `.toggle-hero` with a `.switch` element controls guest Wi-Fi on/off. Read how `.switch` clicks are currently handled in the file's existing delegated click handler (there's an existing generic `.switch` toggle branch used by many static screens purely for cosmetic on/off state with no backend — this screen's switch needs to become a REAL write control specifically, which means either intercepting this one switch's clicks before the generic handler, or adding a specific check keyed off this screen/element before the generic branch runs — read the existing handler fully and choose the cleanest integration point, consistent with how `.search-result-row`/`data-firewall-delete-id` were given specific branches ahead of generic ones in the search feature and Firewall & Ports work).

- [ ] **Step 1:** On navigating to `guest`, fetch `/cgi-bin/api/wifi` (mirroring the established pattern) and set the `.switch`'s visual on/off state to match real `guestEnabled` (rather than trusting the static markup's hardcoded `on` class) — on failure, leave the static state as-is with a fallback notice.
- [ ] **Step 2:** Wire the switch's click specifically on this screen to `fetchRouterApiWithStatus('/cgi-bin/api/wifi', {method:'POST', ..., body: JSON.stringify({guestEnabled: <new state>})})` — optimistic-update or wait-for-response, your call (document which and why), disable the switch during the in-flight request to prevent double-toggle races (mirroring the add-rule submit-button-disable pattern from Firewall & Ports), on failure revert the visual state and show a brief error indication (consistent in spirit with the add-rule form's inline error handling), on success leave it in the new state.
- [ ] **Step 3:** Verify with the real VM running (Playwright): navigate to Guest Wi-Fi, toggle the switch, confirm real `uci show wireless`/`GET /cgi-bin/api/wifi` reflect the change, reload the page, confirm the switch shows the persisted real state (not reset to the static default). Toggle back, confirm the same. Test the fallback path (`file://`): switch shows static default state, clicking it does NOT silently pretend to succeed — confirm reasonable UX (e.g. disabled, or an error shown on click-attempt — your call, document it). Test rapid double-click doesn't fire two conflicting requests.
- [ ] **Step 4:** Regression-check the rest of the app (other screens, search) and confirm the generic `.switch` cosmetic-toggle behavior on OTHER screens (which should NOT hit this new write path) still works exactly as before.
- [ ] **Step 5: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Guest Wi-Fi toggle to real POST /api/wifi"
```

---

### Task 5: Full Wave 3 verification pass

**Files:** none (verification only)

- [ ] **Step 1:** Fresh-state check: tear down, delete `boot-image/boot.img`, re-fetch, bring up fresh, run all 8 provisioning scripts (`01`-`08`) in order exactly as `docker/README.md` documents.
- [ ] **Step 2:** Regression check, VM up: sweep all 48 screens, zero console errors. Re-run established search queries plus at least one targeting Settings/Guest Wi-Fi's now-dynamic content, to confirm/document whether the same "highlight silently skipped" pattern applies here too (check the actual `searchIndex` entries for these screens first — they may or may not target the now-dynamic spans/switch, confirm rather than assume).
- [ ] **Step 3:** Regression check, VM down (`file://`): all screens including the two Wave 3 ones fall back cleanly, zero console errors.
- [ ] **Step 4:** If anything breaks, fix it and commit. If clean, say so.
- [ ] **Step 5:** Update `docker/README.md`'s Known Limitations and the design spec's roadmap/Frontend-changes/search-interaction sections to reflect Wave 3 as done, mirroring exactly how Waves 1-2's own Task-5/9 closeouts did this — don't skip, this has been a recurring integration-review finding when skipped.
- [ ] **Step 6:** Tear down cleanly.

---

## Self-review notes

- **Spec coverage:** matches the corrected Wave 3 scope (Settings' two row values, Guest Wi-Fi's toggle) exactly; Network & VLANs/Ad Blocking/Site Blocked explicitly deferred per the design spec's 2026-08-31 correction, not silently dropped.
- **Placeholder scan:** the one open question (exact `guest` `uci network`/firewall-zone shape, if any beyond the `wifi-iface` section itself) is a bounded investigation step with clear guidance (keep minimal, don't over-build), not a vague TBD.
- **Naming consistency:** `state.settingsRenderId`, `/cgi-bin/api/wifi` follow the established conventions exactly.
- **Type consistency:** `{ssid, guestEnabled}` is used consistently as the GET response shape and the POST request/response shape across all tasks in this plan.
