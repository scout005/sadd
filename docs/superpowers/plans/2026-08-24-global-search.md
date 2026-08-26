# Global Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a working global search to both prototypes — a persistent search bar in the desktop top bar and a shared search icon on mobile — that finds devices, people, apps, settings pages, log entries, and config values, then navigates to and highlights the exact matching record.

**Architecture:** A hand-authored `searchIndex` array (one per file) drives a filter-as-you-type dropdown. Selecting a result calls the existing `goTo(screen)` function, then a new `highlightAndScroll(matchText)` helper locates the matching element in the freshly-rendered DOM and scrolls/highlights it. No build step, no external libraries — same single-file pattern as the rest of both prototypes.

**Tech Stack:** Vanilla JS, CSS, HTML. `sadd-website.html` is edited via Python JSON round-trip scripts (its `screens`/`screenMeta`/`pageTitles` objects are single-line JSON). `sadd-mobile-app.html` is edited via the `Edit` tool (plain template literals). Both verified visually via Playwright screenshots (established pattern this session).

**Refinement over the design spec:** the spec proposed "a search icon in each screen's header" for mobile. Investigation during planning found `sadd-mobile-app.html` has a real shared shell — `.statusbar` and `#screenContent` are static markup outside the `screens` object (lines 114–134), with a `.bottomnav` also shared. So the search icon goes into that shared shell **once**, not into all 16 screen templates individually. Same visible outcome (an icon that's always present, opens full-screen search), cleaner implementation.

---

### Task 1: Add port-block/site-block log entries needed for the search demo to work

**Files:**
- Modify: `sadd-website.html` (`screens['advlogs']`, `screens['connectionhealth']`)

The design's whole motivating example ("user suspects a port is blocked, search finds the record") needs real log text to match against. `advlogs.html` already has a "Recent activity" `.tech-row` list; `connectionhealth.html` has a WAN-drop history list in the same pattern.

- [ ] **Step 1:** In `screens['advlogs']`, insert two new `.tech-row` entries into the existing "Recent activity" list (reuse the exact same `.tech-row` markup pattern already there, e.g. `<div class="tech-row"><div class="tr-label">Inbound connection blocked on port 3074</div><div class="tr-val">Today, 6:42 PM</div></div>`), and one for a site block: `<div class="tech-row"><div class="tr-label">social-app.example.com blocked for Emma's iPad</div><div class="tr-val">Yesterday</div></div>`. Insert them right after the existing 5 `.tech-row` entries, before the "Export logs" button.
- [ ] **Step 2:** Verify with a Python round-trip: load `screens`, assert the 3 new strings are present, dump counts of `.tech-row` in `advlogs` (should go from 5 to 8 total incl. the log ones — cross-check against the actual pre-edit count read from the file, don't assume).
- [ ] **Step 3: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): add port-block and site-block log entries for search demo"
```

---

### Task 2: Build the desktop `searchIndex` array and insert it into the script

**Files:**
- Modify: `sadd-website.html` (new top-level `const searchIndex = [...]` near `const forwardMap`/`textLinkMap`, around line 677)

- [ ] **Step 1:** Author the full array (~100–120 records) covering, per the design doc's category list — devices, people, apps, every sidebar/settings page, activity log entries (including the 3 from Task 1), the 2 port-forwarding rules, 5 VLANs, 5 geo-IP countries, MFA methods. Each record: `{type, label, sub, screen, matchText, keywords}`. Use the exact visible text already present in each screen (already fully catalogued from this session's screen-by-screen review) so `matchText` is guaranteed to exist verbatim in the rendered DOM. Example entries:

```js
const searchIndex = [
  {type:'device', label:"Emma's iPhone", sub:'Online · Family · Devices', screen:'devices', matchText:"Emma's iPhone", keywords:'emma iphone phone family'},
  {type:'rule', label:'Xbox Series X port rule', sub:'External 3074 → 192.168.1.45:3074 · Firewall & Ports', screen:'advfirewall', matchText:'Xbox Series X', keywords:'3074 xbox port forward nat'},
  {type:'log', label:'Inbound connection blocked on port 3074', sub:'Diagnostics & Logs', screen:'advlogs', matchText:'Inbound connection blocked on port 3074', keywords:'3074 port block firewall inbound'},
  {type:'log', label:"social-app.example.com blocked for Emma's iPad", sub:'Diagnostics & Logs', screen:'advlogs', matchText:'social-app.example.com blocked', keywords:'site block domain emma social'},
  {type:'setting', label:'Firewall & Ports', sub:'Advanced settings', screen:'advfirewall', matchText:'Firewall & Port Forwarding', keywords:'firewall port forwarding nat upnp geo-ip'},
  {type:'network', label:'Kids VLAN', sub:'192.168.2.0/24 · Network & VLANs', screen:'advnetwork', matchText:'Kids', keywords:'vlan network kids subnet'},
  {type:'app', label:'TikTok', sub:'Blocked · Reliable · Parental Controls', screen:'parental', matchText:'TikTok', keywords:'tiktok blocked app'},
  // ... continue for every device/person/app/page/log/rule/vlan/country cataloged in the design doc
];
```

- [ ] **Step 2:** Insert this constant into the script, immediately before `const forwardMap = {`.
- [ ] **Step 3:** Verify: `node -e "..."` or a small Python/JS syntax check isn't available for embedded `<script>` — instead verify by loading the file in Playwright (`page.evaluate('() => searchIndex.length')`) after this task's write, confirming the array parses and returns the expected count (~100–120).
- [ ] **Step 4: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): add searchIndex data for global search"
```

---

### Task 3: Add the search bar HTML and CSS to the desktop top bar

**Files:**
- Modify: `sadd-website.html` (`.app-topbar` markup near `id="pageTitle"`; new CSS rules near `.app-topbar-actions`)

- [ ] **Step 1:** Insert a search bar between `.app-topbar-title` and `.app-topbar-actions`:

```html
<div class="topbar-search">
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
  <input type="text" id="searchInput" placeholder="Search devices, logs, settings…" autocomplete="off">
  <div class="search-results-panel" id="searchResultsPanel" style="display:none;"></div>
</div>
```

- [ ] **Step 2:** Add CSS (matching the design's mockup — pill input, dropdown panel with box-shadow, grouped labels, `<mark>` highlight, active-row state):

```css
.topbar-search{position:relative;flex:1;max-width:420px;margin:0 20px;}
.topbar-search>svg{position:absolute;left:14px;top:50%;transform:translateY(-50%);color:var(--muted-2);pointer-events:none;}
.topbar-search input{width:100%;height:38px;border-radius:999px;border:1.5px solid var(--border);background:var(--bg);padding:0 14px 0 38px;font-family:'Nunito',sans-serif;font-size:13px;color:var(--text);}
.topbar-search input:focus{outline:2px solid var(--teal);outline-offset:1px;background:#fff;}
.search-results-panel{position:absolute;top:46px;left:0;right:0;background:#fff;border:1.5px solid var(--border);border-radius:14px;box-shadow:0 8px 24px rgba(15,23,42,.12);max-height:70vh;overflow-y:auto;z-index:20;}
.search-group-label{font-size:10.5px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--muted-2);padding:10px 16px 4px;}
.search-result-row{display:flex;align-items:center;gap:12px;padding:10px 16px;border-top:1px solid var(--bg);cursor:pointer;}
.search-result-row:first-of-type{border-top:none;}
.search-result-row.active,.search-result-row:hover{background:var(--teal-tint);}
.search-result-icon{width:30px;height:30px;border-radius:9px;background:var(--teal-tint);color:var(--teal-dark);display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:14px;}
.search-result-main{flex:1;min-width:0;}
.search-result-main strong{display:block;font-size:13px;}
.search-result-main span{font-size:11.5px;color:var(--muted);}
.search-result-main mark{background:var(--teal-light);color:var(--teal-dark);border-radius:3px;padding:0 2px;font-weight:700;}
.search-result-chip{margin-left:auto;font-size:10px;font-weight:700;color:var(--teal-dark);background:var(--teal-tint);border-radius:999px;padding:3px 9px;flex-shrink:0;white-space:nowrap;}
.search-empty{padding:24px 16px;text-align:center;color:var(--muted-2);font-size:12.5px;}
.search-highlight-pulse{animation:searchPulse 2s ease-out;}
@keyframes searchPulse{0%{box-shadow:0 0 0 3px var(--teal);}100%{box-shadow:0 0 0 0 transparent;}}
```

- [ ] **Step 2 (media query check):** Read the existing `@media` breakpoints for `.app-topbar` (lines ~496–497 area, tablet/phone) and add a corresponding narrower `.topbar-search{max-width:...}` override inside each so the bar doesn't crowd out the title on narrow viewports — check current values before writing new ones, don't guess.
- [ ] **Step 3:** Verify: screenshot the top bar on a representative screen at desktop width via Playwright, confirm the input renders inline between title and actions with no overlap.
- [ ] **Step 4: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): add search bar HTML/CSS to top bar"
```

---

### Task 4: Add the filter/render/keyboard-nav JS logic

**Files:**
- Modify: `sadd-website.html` (new functions near `goTo`; new listeners near the existing `input`/`keydown` delegated handlers at lines 816/826)

- [ ] **Step 1:** Add a matching + grouping function:

```js
function searchMatch(query){
  const q = query.trim().toLowerCase();
  if(!q) return [];
  const scored = [];
  for(const item of searchIndex){
    const hay = (item.label+' '+item.sub+' '+item.keywords).toLowerCase();
    if(!hay.includes(q)) continue;
    const score = item.label.toLowerCase().startsWith(q) ? 0 : item.label.toLowerCase().includes(q) ? 1 : 2;
    scored.push({item, score});
  }
  scored.sort((a,b)=>a.score-b.score);
  return scored.map(s=>s.item);
}

function groupResults(results){
  const labels = {device:'Devices', person:'People', app:'Apps', setting:'Settings', log:'Activity Log', rule:'Config · Rules', network:'Networks'};
  const groups = {};
  for(const r of results){
    if(!groups[r.type]) groups[r.type] = [];
    if(groups[r.type].length < 4) groups[r.type].push(r);
  }
  return Object.keys(groups).map(type=>({label:labels[type]||type, items:groups[type]}));
}

function highlightText(text, query){
  const i = text.toLowerCase().indexOf(query.toLowerCase());
  if(i === -1) return text;
  return text.slice(0,i) + '<mark>' + text.slice(i,i+query.length) + '</mark>' + text.slice(i+query.length);
}

let searchActiveIndex = -1;
let searchFlatResults = [];

function renderSearchResults(query){
  const panel = document.getElementById('searchResultsPanel');
  const results = searchMatch(query);
  searchFlatResults = results;
  searchActiveIndex = -1;
  if(!results.length){
    panel.innerHTML = '<div class="search-empty">No matches for "'+query+'"</div>';
    panel.style.display = 'block';
    return;
  }
  const groups = groupResults(results);
  let html = '';
  let flatIdx = 0;
  const chipFor = {log:'Jump to log', rule:'Jump to rule', setting:'Open', device:'Open', person:'Open', app:'Open', network:'Open'};
  const iconFor = {log:'📄', rule:'🛡️', setting:'⚙️', device:'📱', person:'👤', app:'🔲', network:'🌐'};
  for(const g of groups){
    html += '<div class="search-group-label">'+g.label+'</div>';
    for(const item of g.items){
      html += '<div class="search-result-row" data-idx="'+flatIdx+'"><div class="search-result-icon">'+iconFor[item.type]+'</div><div class="search-result-main"><strong>'+highlightText(item.label, query)+'</strong><span>'+highlightText(item.sub, query)+'</span></div><div class="search-result-chip">'+chipFor[item.type]+'</div></div>';
      flatIdx++;
    }
  }
  panel.innerHTML = html;
  panel.style.display = 'block';
}

function activateSearchResult(item){
  const panel = document.getElementById('searchResultsPanel');
  panel.style.display = 'none';
  const input = document.getElementById('searchInput');
  input.value = '';
  input.blur();
  goTo(item.screen);
  setTimeout(()=>highlightAndScroll(item.matchText), 80);
}
```

- [ ] **Step 2:** Add the highlight/scroll helper:

```js
function highlightAndScroll(matchText){
  const rowSelectors = '.setting-row,.rule-row,.list-item,.tech-row,.app-block-row,.check-card,.result-card,.nav-card,.adv-row,.fam-list-item';
  const candidates = Array.from(document.querySelectorAll(rowSelectors));
  const target = candidates.find(el => el.textContent.includes(matchText));
  if(!target) return;
  target.scrollIntoView({behavior:'smooth', block:'center'});
  target.classList.add('search-highlight-pulse');
  setTimeout(()=>target.classList.remove('search-highlight-pulse'), 2000);
}
```

- [ ] **Step 3:** Wire up input/click/keyboard events. Add to the existing `document.body.addEventListener('input', ...)` handler (before its `otp-box` early-return logic, as a separate branch):

```js
document.body.addEventListener('input', (e)=>{
  if(e.target.id === 'searchInput'){
    renderSearchResults(e.target.value);
    return;
  }
  const box = e.target.closest('.otp-box');
  // ...existing otp-box logic unchanged below
```

Add a new click branch (in the existing `document.body.addEventListener('click', ...)` handler, near the top before the generic `data-goto` handling) for clicking a result row:

```js
const resultRow = e.target.closest('.search-result-row');
if(resultRow){
  const idx = parseInt(resultRow.dataset.idx, 10);
  activateSearchResult(searchFlatResults[idx]);
  return;
}
```

Add to the existing `keydown` handler (new branch, before the `otp-box` logic):

```js
if(e.target.id === 'searchInput'){
  const rows = () => Array.from(document.querySelectorAll('.search-result-row'));
  if(e.key === 'ArrowDown'){ e.preventDefault(); searchActiveIndex = Math.min(searchActiveIndex+1, searchFlatResults.length-1); }
  else if(e.key === 'ArrowUp'){ e.preventDefault(); searchActiveIndex = Math.max(searchActiveIndex-1, 0); }
  else if(e.key === 'Enter'){ if(searchFlatResults[searchActiveIndex >= 0 ? searchActiveIndex : 0]) activateSearchResult(searchFlatResults[searchActiveIndex >= 0 ? searchActiveIndex : 0]); return; }
  else if(e.key === 'Escape'){ document.getElementById('searchResultsPanel').style.display = 'none'; e.target.blur(); return; }
  else return;
  rows().forEach((r,i)=>r.classList.toggle('active', i === searchActiveIndex));
}
```

Add a click-outside close (new small listener, appended near the other body listeners):

```js
document.body.addEventListener('click', (e)=>{
  if(!e.target.closest('.topbar-search')) {
    const panel = document.getElementById('searchResultsPanel');
    if(panel) panel.style.display = 'none';
  }
}, true);
```

- [ ] **Step 4:** Verify via Playwright: type "3074" into `#searchInput`, confirm the results panel shows the Xbox rule and the port-block log entry with `<mark>3074</mark>` present; press `ArrowDown` then `Enter`, confirm `state.screen` changed and a `.search-highlight-pulse` class briefly appears on the matched element.
- [ ] **Step 5: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire up global search filtering, keyboard nav, and highlight-on-navigate"
```

---

### Task 5: Full desktop verification pass

**Files:** none (verification only)

- [ ] **Step 1:** Screenshot all 48 screens again (existing `shot_all_screens.py` pattern from this session) to confirm the new top-bar search input doesn't break any screen's layout and no console errors appear.
- [ ] **Step 2:** Run at least 5 representative search queries via Playwright and assert expected top result: `"emma"` → Emma device/person, `"3074"` → Xbox rule + port-block log, `"tiktok"` → TikTok app entry, `"firewall"` → Firewall & Ports setting, `"north korea"` → geo-IP country entry. For each, click the top result and assert `state.screen` matches the expected target screen.
- [ ] **Step 3: Commit** (only if Step 1/2 required fixes; otherwise no commit needed for a clean pass)

---

### Task 6: Add the shared search icon + full-screen search overlay to the mobile shell

**Files:**
- Modify: `sadd-mobile-app.html` (shell markup around line 117 `.statusbar`; new CSS near existing shell styles)

- [ ] **Step 1:** Add a search icon button next to the status bar (or as its own thin bar directly below it), plus a full-screen overlay container, both as shared shell markup (siblings of `#pScroll`, not inside any per-screen template):

```html
<div class="mobile-search-trigger" id="mobileSearchTrigger">
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
  <span>Search</span>
</div>
<div class="mobile-search-overlay" id="mobileSearchOverlay" style="display:none;">
  <div class="mobile-search-header">
    <input type="text" id="mobileSearchInput" placeholder="Search devices, settings…" autocomplete="off">
    <button id="mobileSearchClose">Cancel</button>
  </div>
  <div class="mobile-search-results" id="mobileSearchResults"></div>
</div>
```

- [ ] **Step 2:** Add CSS reusing the same visual language as the desktop version (adapted for the phone frame's width) — trigger bar styled like a subtle input-shaped button, overlay covering the full `.phone-inner` content area with its own header/input/results list, using the same `.search-result-row`-equivalent styling scaled down for ~380px width.
- [ ] **Step 3:** Verify: screenshot the shell with the overlay open (toggled via a quick Playwright `page.click('#mobileSearchTrigger')`) to confirm it covers the content area correctly without breaking the phone frame chrome (status bar, bottom nav still visible or intentionally hidden while search is open — decide during implementation, document the choice inline as a comment if non-obvious).
- [ ] **Step 4: Commit**

```bash
git add sadd-mobile-app.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(mobile): add shared search trigger and full-screen search overlay to shell"
```

---

### Task 7: Build the mobile `searchIndex` and wire up the same filter/highlight logic

**Files:**
- Modify: `sadd-mobile-app.html` (new `const searchIndex` near existing `state`/`goTo`; reuse of `searchMatch`/`groupResults`/`highlightText`/`highlightAndScroll` logic adapted from Task 2/4, scoped to the mobile app's 16 screens' actual content — devices, network settings, notifications toggles, about content, onboarding steps)

- [ ] **Step 1:** Author the mobile `searchIndex` (~20–30 records — this app is much smaller than the desktop one): the 4 devices (Unknown device, Emma's iPhone, Living Room TV, Nest Thermostat), Wi-Fi/Guest network settings, Admin password, Notifications toggles (New device joins, Threats blocked, Network goes offline), About entries (App version, Where made, Pricing promise, Built on OpenWrt), and the onboarding screens (Scan Barcode, Connect via Bluetooth, comfort-level options).
- [ ] **Step 2:** Reuse the same `searchMatch`/`groupResults`/`highlightText` functions from Task 4 (copy, adapted to reference the mobile file's own `screens`/`state`/`goTo`), plus a `highlightAndScroll` using the mobile app's own row-class selectors (`.list-item`, `.li-main`, checked against actual classes used: e.g. also include any settings-row equivalents specific to this file).
- [ ] **Step 3:** Wire `#mobileSearchTrigger` click to open the overlay and focus the input; `#mobileSearchClose` and an Escape-key handler to close it; input event to call `renderSearchResults`; click on a result row to call `goTo` + close overlay + `highlightAndScroll`.
- [ ] **Step 4:** Verify via Playwright: open the overlay, type "emma", confirm Emma's iPhone appears; click it, confirm navigation to `devices` and the highlight pulse fires.
- [ ] **Step 5: Commit**

```bash
git add sadd-mobile-app.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(mobile): add search index and wire up filtering/navigation/highlight"
```

---

### Task 8: Full mobile verification pass

**Files:** none (verification only)

- [ ] **Step 1:** Screenshot all 16 mobile screens (existing `shot_mobile_screens.py` pattern) plus the search trigger and an open-overlay-with-results state, confirm no layout breakage and no console errors.
- [ ] **Step 2:** Run 3 representative queries end-to-end (device name, a settings page, a notifications toggle) and confirm correct navigation + highlight.

---

## Self-review notes

- **Spec coverage:** placement (Task 3/6), scope/index (Task 2/7), instant results + grouping + highlighting (Task 4/7), click-through + exact-record highlight (Task 4/7 `highlightAndScroll`), demo log data (Task 1), keyboard nav (Task 4) — every design section maps to a task.
- **Mobile refinement:** documented at the top of this plan and reflected in Task 6/7 — shared shell icon instead of 16 per-screen edits, a strict implementation improvement over the spec's literal wording with the same user-visible outcome.
- **No placeholders:** every code step above shows real, complete code — the only content deliberately left to write-time is the full ~100–120-entry desktop index and ~20–30-entry mobile index, which are data-authoring tasks explicitly called out as their own step (Task 2 Step 1, Task 7 Step 1) rather than hidden inside vague instructions.
