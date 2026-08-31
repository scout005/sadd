# Real OpenWrt Integration — Wave 2 (About + Diagnostics & Logs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the "App version"/"Built on OpenWrt" row on the `about` screen, and the "Recent activity" log list on the `advlogs` screen, in `sadd-website.html` show real data from the running OpenWrt VM — same pattern as Wave 1 (Devices, Firewall & Ports), reusing its established infrastructure rather than rebuilding it.

**Architecture:** No environment changes needed — Wave 1's Docker/QEMU/tap-device setup, provisioning pattern (`docker/provision/0N-*.sh`), Lua CGI conventions (hand-built JSON, `escapeHtml`/`shell_quote`), and frontend patterns (`fetchRouterApi`, `state.<screen>RenderId` stale-fetch-race guards, `.api-fallback-notice`) all carry forward unchanged. This wave adds two new read-only endpoints and wires two screen sections to them.

**Tech Stack:** Same as Wave 1 — Lua CGI under `uhttpd`, vanilla JS `fetch` in `sadd-website.html`.

**Before Task 1, read this:** `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md`'s Wave 2 roadmap entry (scope and the WAN-interface deferral reasoning) and `docker/facts.md` §7 (`ubus call system board`/`system info`, already captured — real field names, don't re-derive them). Read `docker/provision/www/api/devices` as the reference pattern for a read-only Lua CGI endpoint, and the current `renderDevicesScreen()`/`fetchRouterApi()` in `sadd-website.html` as the reference pattern for wiring a screen to one.

---

### Task 1: Real `/cgi-bin/api/system-info` endpoint

**Files:**
- Create: `docker/provision/www/api/system-info` (Lua CGI)
- Create: `docker/provision/06-provision-system-info-api.sh` (following `04`/`05`'s established pattern exactly — SSH_OPTS, env var overrides, idempotent, self-verifying)
- Modify: `docker/README.md` (extend Provisioning section with step 6)

- [ ] **Step 1:** Write the endpoint. `GET /cgi-bin/api/system-info` runs `ubus call system board` and `ubus call system info`, parses their JSON output (both already confirmed working and their exact shape captured in `docker/facts.md` §7 — verify live on your own running VM before hardcoding field-extraction logic, since `ubus call` output could in principle differ by version/hardware, don't blindly copy the facts.md JSON as gospel without re-confirming), and returns a flat `{distribution, version, revision, target, model, kernel, uptime}` object (or similar — pick sensible, minimal fields that map to what the About screen actually needs to show; don't just dump the raw nested ubus JSON verbatim, shape it for the frontend). Since there's no `lua-cjson`, you'll need to parse `ubus call`'s JSON *output* (not just build JSON to emit) — write a narrow, defensive parser for the specific flat/nested-but-known shape `ubus call system board`/`system info` actually produce (don't write a general-purpose JSON parser; scope it to what these two specific commands emit), or extract fields via simple pattern-matching against the known JSON structure if that's more robust than writing a parser — use your judgment, document the choice.
- [ ] **Step 2:** Verify: bring up the environment fresh per `docker/README.md` (fetch boot image if needed, `docker compose up -d --build`, wait healthy, run provisioning 01→05, then your new step), `curl http://localhost:8081/cgi-bin/api/system-info` — confirm real values matching what `ubus call system board` actually returns on that VM (cross-check via SSH), not hardcoded/fake placeholders.
- [ ] **Step 3: Commit**
```bash
git add docker/provision/ docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): add /api/system-info backed by real ubus system board/info"
```

---

### Task 2: Wire the `about` screen's version row to real data

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the CURRENT `screens['about']` HTML — it has a `.setting-row` with `<strong>App version</strong><span>1.0.0</span>` and a separate, much longer `.setting-row` with `<strong>Built on OpenWrt</strong><span>Sadd runs on OpenWrt 23.05...</span>` (marketing copy — leave its prose as-is, this task is not about rewriting copy). Only the FACTUAL version-string display becomes real.

- [ ] **Step 1:** Add `state.aboutRenderId` (mirroring `devicesRenderId`/`firewallRenderId` exactly). On navigating to `about`, after the static content renders, call an async `renderAboutScreen()` that fetches `/cgi-bin/api/system-info` via `fetchRouterApi` and, on success, updates ONLY the "App version" row's `<span>` text (e.g. to something like `OpenWrt 23.05.5 (r24106-10cc5fcd00) on QEMU Standard PC` — real, `escapeHtml`'d values from the fetch) — do NOT rewrite the "Built on OpenWrt" paragraph's marketing prose, just the factual version-string row. On failure (`null`), leave the static "1.0.0" text as-is with a small `.api-fallback-notice` inserted near that row (reuse the existing CSS class).
- [ ] **Step 2:** Verify with the real VM running (Playwright if available): navigate to About, confirm the App version row shows real OpenWrt version data, no fallback notice. Test the `file://` fallback: static "1.0.0" + notice, no console errors. Regression-check 2-3 other screens + a search query.
- [ ] **Step 3: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire About screen's version row to real /api/system-info"
```

---

### Task 3: Real `/cgi-bin/api/logs` endpoint

**Files:**
- Create: `docker/provision/www/api/logs` (Lua CGI)
- Create: `docker/provision/07-provision-logs-api.sh`
- Modify: `docker/README.md`

- [ ] **Step 1:** Investigate first (over SSH): run `logread` on the live VM, look at its real output format (timestamp, facility, message — confirm the exact format live, don't assume syslog's generic format applies verbatim to OpenWrt's `logread`). Decide a sensible cap (e.g. `logread | tail -n 30` or `logread -l 30` if that flag exists — check) so the endpoint doesn't return unbounded log history.
- [ ] **Step 2:** Write the endpoint. `GET /cgi-bin/api/logs` runs `logread` (capped), parses each line into `{timestamp, message}` (or whatever fields the real format naturally splits into — don't force a shape that doesn't match reality), returns a JSON array, newest-first or oldest-first — pick whichever matches how the frontend's existing static log list is ordered (check `screens['advlogs']`'s static `.tech-row` order first).
- [ ] **Step 3:** Verify: fresh VM, `curl http://localhost:8081/cgi-bin/api/logs`, confirm real log lines (e.g. boot messages, service start messages) appear, correctly parsed, valid JSON.
- [ ] **Step 4: Commit**
```bash
git add docker/provision/ docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): add /api/logs backed by real logread output"
```

---

### Task 4: Wire the `advlogs` screen's "Recent activity" list to real data

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the CURRENT `screens['advlogs']` HTML — the "Recent activity" section has `.tech-row` entries (`<div class="tech-row"><div class="tr-label">...</div><div class="tr-val">...</div></div>`), plus filter `<select>` dropdowns above it (device/category/date-range — these are cosmetic/non-functional in the static version; leave them non-functional, wiring them to actually filter the real log list is NOT in this task's scope, note this explicitly if you're tempted to scope-creep). The "Live download/upload" Mbps cards above the log list are explicitly OUT of scope for this wave (see the design spec's Wave 2 note) — do not touch them.

- [ ] **Step 1:** Add `state.logsRenderId`. On navigating to `advlogs`, after static content renders, call `renderLogsScreen()` — fetch `/cgi-bin/api/logs` via `fetchRouterApi`; on success, replace the `.tech-row` list (only that list — not the Mbps cards, not the filter dropdowns) with real entries built from the fetched data (reusing `.tech-row`/`.tr-label`/`.tr-val` markup, `escapeHtml`'d); on failure, leave the static demo log entries + `.api-fallback-notice`.
- [ ] **Step 2:** Verify with the real VM running: navigate to Diagnostics & Logs, confirm real log lines render (not the static "Emma's iPhone joined the network" demo entries), no fallback notice, Mbps cards unchanged (still static — confirm you didn't accidentally touch them). Test `file://` fallback: static demo entries + notice. Regression-check other screens + search.
- [ ] **Step 3: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Diagnostics & Logs' Recent Activity to real /api/logs"
```

---

### Task 5: Full Wave 2 verification pass

**Files:** none (verification only)

- [ ] **Step 1:** Fresh-state check: tear down, delete `boot-image/boot.img`, re-fetch, bring up fresh, run all 7 provisioning scripts (`01`-`07`) in order exactly as `docker/README.md` documents. Confirm every step succeeds from nothing.
- [ ] **Step 2:** Regression check, VM up: sweep all 48 screens (Playwright), confirm zero console errors. Re-run search queries from Wave 1's own verification plus at least one targeting the `about`/`advlogs` screens' STATIC (non-replaced) entries, to confirm the same "highlight doesn't fire on now-dynamic content, but does on unaffected static content" pattern documented for Wave 1 holds here too (expected, not a bug — don't try to fix it, just confirm you understand and can point to why, consistent with Wave 1's documented precedent).
- [ ] **Step 3:** Regression check, VM down (`file://`): confirm both new screens' sections fall back cleanly, confirm all 48 screens still clean, confirm zero console errors (watch specifically for the same class of browser-network-layer noise Wave 1 Task 9 found and fixed for `file:` — the existing `location.protocol === 'file:'` guard in `fetchRouterApi` should already cover these two new call sites automatically since they reuse that same helper; verify this is actually true rather than assuming it).
- [ ] **Step 4:** If anything breaks, fix it properly and commit. If clean, say so.
- [ ] **Step 5:** Update `docker/README.md`'s Known Limitations section and the design spec if this wave surfaced anything new worth documenting (mirroring Wave 1's Task 9 closing pattern) — don't skip this if something real comes up, but don't manufacture busywork if nothing does.
- [ ] **Step 6:** Tear down cleanly.

---

## Self-review notes

- **Spec coverage:** matches the corrected Wave 2 scope exactly (About's version row + Diagnostics & Logs' activity list only; Mbps cards and WAN-dependent screens explicitly excluded, per the design spec's 2026-08-31 scope correction).
- **Placeholder scan:** no TBDs; the two genuine open questions (exact `ubus`/`logread` output parsing approach) are investigation steps with clear success criteria, same pattern Wave 1's Task 1/2 used for legitimate infra uncertainty — not vague placeholders.
- **Naming consistency:** `state.aboutRenderId`/`state.logsRenderId` follow the established `state.<screen>RenderId` convention exactly. `/cgi-bin/api/system-info` and `/cgi-bin/api/logs` follow the established `/cgi-bin/api/<noun>` path convention.
- **Scope:** narrowly targeted — two screen SECTIONS (not whole screens), consistent with how Wave 1 only touched the port-forwarding section of Firewall & Ports, not its whole screen.
