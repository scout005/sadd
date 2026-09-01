# Real OpenWrt Integration — Wave 4 (Ad Blocking + Network & VLANs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `adblock` screen's on/off toggle and "N blocked this week" stat real (backed by a genuine dnsmasq DNS-blocklist, not the `adblock` package — no internet access on this VM to install its large dependency tree), and make the `advnetwork` screen's VLAN list real (backed by genuinely created `uci network` interfaces and kernel-level 802.1q sub-interfaces, not just inert config strings).

**Architecture:** No environment changes. Two new endpoints (`/cgi-bin/api/adblock` GET+POST, `/cgi-bin/api/vlans` GET-only) following the established Lua CGI conventions. Frontend follows the now-six-times-proven pattern (`state.<screen>RenderId`, `fetchRouterApi`/`fetchRouterApiWithStatus`, `setEscapedText`, correctly-scoped `.api-fallback-notice`). Ad Blocking's toggle mirrors Guest Wi-Fi's optimistic-update write pattern exactly.

**Tech Stack:** Same as Waves 1-3.

**Before Task 1, read this:** `docker/facts.md` §12 — both mechanisms (dnsmasq `confdir`-based blocklist with query-log-derived block counting; real 802.1q VLAN interfaces via `uci network` + `network reload`) were confirmed live before this plan was written, with the exact commands that work. Use them, don't re-derive. Also read `docker/provision/www/api/wifi` (the most recent GET+POST reference, including its verify-before-commit/revert-on-failure discipline) and the current `renderGuestScreen()`/`handleGuestWifiSwitchClick()` in `sadd-website.html` (the optimistic-update write reference).

---

### Task 1: Provision a baseline DNS blocklist + real `GET /cgi-bin/api/adblock`

**Files:**
- Create: `docker/provision/www/api/adblock`
- Create: `docker/provision/09-provision-adblock-api.sh`
- Modify: `docker/README.md`

- [ ] **Step 1:** The provisioning script creates the baseline blocklist over SSH, using the exact confirmed sequence from `docker/facts.md` §12: `mkdir -p /etc/dnsmasq.blocklist.d`, write a blocklist file with `address=/<domain>/0.0.0.0` lines for a plausible starter set matching the mockup's demo entries (check `screens['adblock']` in `sadd-website.html` for the exact domains shown in its "This week" mini-log — `doubleclick.net`, `adservice.google.com`, `tracker.example.com` were seen during design, confirm live against the current file, don't assume), set `dhcp.@dnsmasq[0].confdir` and `dhcp.@dnsmasq[0].logqueries=1` via `uci`, commit, `/etc/init.d/dnsmasq restart`. Make this idempotent (check before creating/setting, mirroring `08-provision-wifi-api.sh`'s established completeness-check-and-revert pattern — don't just check "does the file exist," verify its content is what's expected, same class of rigor Wave 3's code review required).
- [ ] **Step 2:** Write the endpoint. `GET /cgi-bin/api/adblock` returns `{"enabled": <bool>, "blockedThisWeek": <int>}`. `enabled` = whether `dhcp.@dnsmasq[0].confdir` is currently set (via `uci get`). `blockedThisWeek` = count of `logread` lines matching `config <domain> is 0.0.0.0` where `<domain>` is one of the blocklisted domains (parse `logread`'s real output — reuse/adapt patterns from `docker/provision/www/api/logs`'s line-parsing approach; "this week" is aspirational given `logread`'s buffer is much shorter than a week in practice — just count everything currently in the log buffer matching the pattern, and note this limitation in a comment rather than trying to implement real week-long persistence, which is out of scope).
- [ ] **Step 3:** Verify: fresh VM, provisioning 01→09, `curl http://localhost:8081/cgi-bin/api/adblock` returns real values; generate a few real blocked lookups over SSH (`nslookup doubleclick.net 127.0.0.1`) and confirm `blockedThisWeek` increases correspondingly on a subsequent `curl`.
- [ ] **Step 4:** Re-verify from a genuinely fresh VM boot.
- [ ] **Step 5: Commit**
```bash
git add docker/provision/ docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): provision DNS blocklist, add GET /api/adblock"
```

---

### Task 2: Wire the `adblock` screen's toggle-hero + stat to real data (read side)

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the CURRENT `screens['adblock']` HTML in full. The `<p class="dash-date">On · 1,204 ads blocked this week</p>` and the `.toggle-hero`'s `.switch` are the ONLY things that become dynamic in this task (write capability comes in Task 4) — the blocklist-tier radio cards, device exceptions, "This week" bar chart, mini-log top-3 domains, "Always allow" list, and "report broken site" button all stay static, explicitly out of scope (matching the design spec's narrow Wave 4 scope note).

- [ ] **Step 1:** Add `state.adblockRenderId`. On navigating to `adblock`, fetch `/cgi-bin/api/adblock` via `fetchRouterApi`. On success, update the stat text (`setEscapedText`, e.g. `"${enabled ? 'On' : 'Off'} · ${blockedThisWeek} ads blocked this week"`) and set the switch's visual state to match real `enabled` (not the static hardcoded `on`). On failure, leave static content + one correctly-scoped `.api-fallback-notice`.
- [ ] **Step 2:** Verify with the real VM running: real stat/switch-state render correctly, no notice. `file://` fallback: static content + notice, no console errors. Rapid re-navigation race-guard test.
- [ ] **Step 3:** Regression-check the other 5 real screens/sections + 1-2 search queries.
- [ ] **Step 4: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Ad Blocking screen's toggle/stat to real /api/adblock"
```

---

### Task 3: Add `POST /cgi-bin/api/adblock` — real enable/disable

**Files:**
- Modify: `docker/provision/www/api/adblock`

- [ ] **Step 1:** `POST /cgi-bin/api/adblock` reads `{"enabled": true|false}` (reuse the established minimal JSON body parser). `enabled:true` → `uci set dhcp.@dnsmasq[0].confdir=/etc/dnsmasq.blocklist.d`; `enabled:false` → `uci delete dhcp.@dnsmasq[0].confdir` (removes the blocklist read entirely — confirm via SSH this is genuinely how to turn it back off, don't assume symmetry with the `set` path). Verify via readback before committing, `uci revert dhcp` + `Status: 500` on failure (mirroring `firewall-rules`/`wifi`'s established rigor), `uci commit dhcp` + `/etc/init.d/dnsmasq restart` on success. Respond with the new state.
- [ ] **Step 2:** Verify: `curl -X POST` toggling both directions, confirm via SSH (`uci get dhcp.@dnsmasq[0].confdir`, and a real `nslookup` test proving blocking genuinely stops/resumes) that the backend state genuinely changed, not just the endpoint's own claimed response. Test invalid input → `Status: 400`, no config change.
- [ ] **Step 3:** Re-verify from a genuinely fresh VM boot.
- [ ] **Step 4: Commit**
```bash
git add docker/provision/www/api/adblock
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): add POST /api/adblock for real ad-blocking toggle"
```

---

### Task 4: Wire the `adblock` screen's toggle to the real write endpoint

**Files:**
- Modify: `sadd-website.html`

**Context:** Mirror `handleGuestWifiSwitchClick()`'s established optimistic-update pattern exactly (flip immediately, disable during in-flight request via a pending flag, revert + show error notice on failure, mirror the code comment explaining why no `adblockRenderId` guard is needed on the write path if that reasoning still applies here — verify it does, don't just copy the comment blindly).

- [ ] **Step 1:** Wire the `adblock` screen's `.switch` click (give it a unique `id`, intercept before the generic cosmetic handler, exactly like `guestWifiSwitch`) to `fetchRouterApiWithStatus('/cgi-bin/api/adblock', {method:'POST', ..., body: JSON.stringify({enabled: <new state>})})`. Update the stat text's "On"/"Off" portion in sync with the switch's optimistic flip.
- [ ] **Step 2:** Verify: toggle via the UI, confirm real backend change (SSH `uci get`), reload page, confirm persisted state. Forced-failure test (confirm revert + no false success, backend genuinely unchanged, verified via SSH). Rapid double-click guard. `file://` fallback behaves reasonably. Other screens' switches unaffected.
- [ ] **Step 3:** Regression-check the rest of the app.
- [ ] **Step 4: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Ad Blocking toggle to real POST /api/adblock"
```

---

### Task 5: Provision baseline VLANs + real `GET /cgi-bin/api/vlans`

**Files:**
- Create: `docker/provision/www/api/vlans`
- Create: `docker/provision/10-provision-vlans-api.sh`
- Modify: `docker/README.md`

- [ ] **Step 1:** The provisioning script creates 5 real `uci network` interface sections over SSH, matching the mockup's demo VLANs (check `screens['advnetwork']` in `sadd-website.html` for the exact current names/subnets — Main Network 192.168.1.0/24 already exists as `network.lan`, don't recreate it; the other 4 — Kids 192.168.2.0/24, IoT/Smart Home 192.168.3.0/24, Guests 192.168.4.0/24, Quarantine 192.168.5.0/24 — need creating, using the exact confirmed sequence from `docker/facts.md` §12: `proto=static`, `device=br-lan.<N>` for a distinct VLAN id per network, matching `ipaddr`/`netmask`). Commit, `/etc/init.d/network reload`. Idempotent (completeness-check pattern, mirroring `08`/`09`).
- [ ] **Step 2:** Write the endpoint. `GET /cgi-bin/api/vlans` returns `[{name, subnet, active}, ...]` for all 5 (including the pre-existing `lan`/Main Network) — `name`/`subnet` from `uci show network`, `active` from whether the interface is genuinely up (check via `ubus call network.interface.<name> status` for a real `up` boolean, or `ip link show br-lan.<N>` state — pick whichever is more reliable, confirm live). Device-count is explicitly OUT of scope for this task (would need real per-VLAN DHCP service, a much larger undertaking) — do not include a fabricated device-count field; the frontend (Task 6) will keep that column's static demo numbers, documented as a known, deliberate gap.
- [ ] **Step 3:** Verify: fresh VM, provisioning 01→10, `curl http://localhost:8081/cgi-bin/api/vlans` returns all 5 real entries; cross-check `ip link show` confirms the real `br-lan.N` interfaces exist and are up.
- [ ] **Step 4:** Re-verify from a genuinely fresh VM boot.
- [ ] **Step 5: Commit**
```bash
git add docker/provision/ docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): provision real VLAN interfaces, add GET /api/vlans"
```

---

### Task 6: Wire the `advnetwork` screen's VLAN list to real data

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the CURRENT `screens['advnetwork']` HTML in full. Only the 5 `.adv-row` VLAN list entries' name/subnet/active-switch become dynamic — the device-count column stays static (per Task 5's explicit scope note), and everything else on the screen (Zero Trust section, Coverage/mesh section, DHCP range/DNS servers/Static IP grid at the bottom) stays static, explicitly out of scope.

- [ ] **Step 1:** Add `state.vlansRenderId`. On navigating to `advnetwork`, fetch `/cgi-bin/api/vlans`. On success (even matching exactly 5 entries is expected but don't hardcode that assumption — render whatever the real array contains), replace the `.adv-row` list's name/subnet/active-switch fields with real data (reusing the exact same markup structure, `setEscapedText` for name, real subnet string, `active` mapped to the switch's `on`/off class) while leaving each row's device-count number as whatever static markup already shows (or a neutral placeholder if that's cleaner — your call, document it). On failure, static rows + one correctly-scoped notice.
- [ ] **Step 2:** Verify: real VLAN list renders correctly matching the API, no notice. `file://` fallback: static rows + notice. Race-guard test.
- [ ] **Step 3:** Regression-check the rest of the app (all 6 other real screens/sections, search).
- [ ] **Step 4: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Network & VLANs' list to real /api/vlans"
```

---

### Task 7: Full Wave 4 verification pass

**Files:** none (verification only)

- [ ] **Step 1:** Fresh-state check: tear down, delete `boot-image/boot.img`, re-fetch, bring up fresh, run all 10 provisioning scripts in order.
- [ ] **Step 2:** Regression check, VM up: sweep all 48 screens, zero console errors, re-run established search queries plus any targeting Ad Blocking/VLANs' now-dynamic content (check searchIndex first, don't assume).
- [ ] **Step 3:** Regression check, VM down (`file://`): all 8 real screens/sections fall back cleanly, zero console errors across all 48 screens.
- [ ] **Step 4:** Fix any genuine bug found; otherwise say so plainly.
- [ ] **Step 5:** Update `docker/README.md`'s Known Limitations and the design spec's roadmap/Frontend-changes/Security-posture/search-interaction sections to reflect Wave 4 as done — mirroring exactly how Waves 1-3's closeouts did this. Do a careful full read-through of the design spec (not a skim) — each prior wave's own closeout has missed at least one stale reference that a LATER whole-wave review then had to catch; try to genuinely not repeat that this time.
- [ ] **Step 6:** Tear down cleanly.

---

## Self-review notes

- **Spec coverage:** matches the corrected Wave 4 scope (Ad Blocking toggle+stat, VLAN list) exactly; Site Blocked/Block Detail explicitly deferred per the design spec's 2026-09-01 correction.
- **Placeholder scan:** no TBDs; both mechanisms were confirmed live before this plan was written (`docker/facts.md` §12), with exact working commands given, not vague investigation steps.
- **Naming consistency:** `state.adblockRenderId`/`state.vlansRenderId`, `/cgi-bin/api/adblock`, `/cgi-bin/api/vlans` follow established conventions exactly.
- **Type consistency:** `{enabled, blockedThisWeek}` used consistently for adblock GET/POST; `[{name, subnet, active}]` used consistently for vlans GET and its frontend consumer.
- **Scope:** narrowly targeted per-field/per-row, consistent with every prior wave's discipline — device-count explicitly and deliberately excluded from VLANs, documented as a known gap rather than fabricated.
