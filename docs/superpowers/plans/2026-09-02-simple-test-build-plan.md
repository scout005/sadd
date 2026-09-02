# Simple Test Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce `sadd-website-simple.html`, a standalone copy of `sadd-website.html` with a simplified username/password login (skipping the full onboarding flow), a redesigned flat-rows Parental Controls layout, and a whole-app light/dark theme toggle — `sadd-website.html` itself never modified.

**Architecture:** One new HTML file, edited entirely with small Node.js scripts that `JSON.parse`/edit/`JSON.stringify` the file's two JS object literals (`screens`, `screenMeta` — both confirmed strict, valid JSON) plus a handful of plain string edits to the surrounding `<script>`/`<style>` sections. No backend, no OpenWrt VM — this is pure frontend markup/CSS/JS.

**Tech Stack:** Vanilla HTML/CSS/JS (matching the existing file exactly), Node.js for scripted edits (no framework, no build step).

**Full design context:** `docs/superpowers/specs/2026-09-02-simple-test-build-design.md` — read it before starting; this plan assumes its contents as background.

---

### Task 1: Create `sadd-website-simple.html` with the simplified login flow

**Files:**
- Create: `sadd-website-simple.html` (copy of `sadd-website.html`)

**Context you need:** `sadd-website.html` has two JS object literals that are strict, valid JSON despite being JS `const` declarations — `screens` (48 keys, each screen's HTML as a string value) and `screenMeta` (48 keys, each mapping a screen name to `"auth"` or `"app"`). `screenMeta === "auth"` screens render into a full-viewport `#authView` container (no sidebar/topbar chrome); `"app"` screens render into `#appContent` inside the persistent `#appShell` (sidebar + topbar). This is decided in `render()` (`sadd-website.html:721-793`). Navigation is fully generic: any element with `data-goto="X"` calls `goTo(screen)` via the global click handler, which just does `state.screen = screen; render();` — no other wiring is needed to make a new screen reachable.

There is currently no "Log out" or "Sign out" affordance anywhere in the app (confirmed by search) — nothing currently links back to `welcome`/`login`, so changing the entry point is safe and self-contained.

- [ ] **Step 1: Copy the file and verify the copy is identical**

```bash
cp sadd-website.html sadd-website-simple.html
diff sadd-website.html sadd-website-simple.html
```
Expected: no output from `diff` (files identical).

- [ ] **Step 2: Add the `simplelogin` screen to `screenMeta` as an `"auth"` screen**

```js
const fs = require('fs');
const path = 'sadd-website-simple.html';
let html = fs.readFileSync(path, 'utf8');

const metaMatch = html.match(/const screenMeta = (\{.*?\});/s);
if (!metaMatch) throw new Error('screenMeta not found');
const screenMeta = JSON.parse(metaMatch[1]);
if (screenMeta.simplelogin) throw new Error('simplelogin already exists in screenMeta');
screenMeta.simplelogin = 'auth';
html = html.replace(metaMatch[0], 'const screenMeta = ' + JSON.stringify(screenMeta) + ';');

fs.writeFileSync(path, html);
console.log('OK — screenMeta now has', Object.keys(screenMeta).length, 'keys');
```
Expected output: `OK — screenMeta now has 49 keys`.

- [ ] **Step 3: Add the `simplelogin` screen markup to `screens`**

```js
const fs = require('fs');
const path = 'sadd-website-simple.html';
let html = fs.readFileSync(path, 'utf8');

const screensMatch = html.match(/const screens = (\{.*?\});/s);
if (!screensMatch) throw new Error('screens not found');
const screens = JSON.parse(screensMatch[1]);
if (screens.simplelogin) throw new Error('simplelogin already exists in screens');

screens.simplelogin = '\n        <div class="wizard-desk"><div class="wizard-card" style="max-width:360px;">\n          <div style="display:flex;align-items:center;gap:10px;margin-bottom:28px;">\n            <div class="logo-mark"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.5 12 3l9 7.5"/><path d="M5 9v10a1 1 0 0 0 1 1h3v-6h6v6h3a1 1 0 0 0 1-1V9"/></svg></div>\n            <span style="font-weight:800;font-size:18px;">Sadd</span>\n          </div>\n          <h1 class="scr-title">Log in</h1>\n          <p class="scr-sub">Test build — enter the credentials below.</p>\n          <div class="field"><label>Username</label><input class="input" id="simpleLoginUsername" type="text" autocomplete="off"></div>\n          <div class="field"><label>Password</label><input class="input" id="simpleLoginPassword" type="password" autocomplete="off"></div>\n          <p style="font-size:11.5px;color:var(--muted-2);margin:-8px 0 18px;">For testing: admin / admin</p>\n          <div id="simpleLoginError" style="display:none;color:var(--error);font-size:12.5px;margin-bottom:14px;"></div>\n          <button class="btn btn-primary" id="simpleLoginBtn" style="width:100%;">Log In</button>\n        </div></div>\n      ';

html = html.replace(screensMatch[0], 'const screens = ' + JSON.stringify(screens) + ';');
fs.writeFileSync(path, html);
console.log('OK — screens now has', Object.keys(screens).length, 'keys');
```
Expected output: `OK — screens now has 49 keys`.

- [ ] **Step 4: Change the initial screen from `welcome` to `simplelogin`**

```bash
grep -c "screen: 'welcome'" sadd-website-simple.html
```
Expected: `1` (confirms there's exactly one occurrence to replace, in the `const state = {...}` initializer — this is plain JS text, not inside `screens`/`screenMeta`, safe to edit directly, not via JSON round-trip).

Then edit that one line: change `screen: 'welcome'` to `screen: 'simplelogin'` inside the `const state = { ... }` declaration (search for `const state = { screen:` to find it). Use a direct text edit (not a Node script) since this is a single literal string inside a `const` declaration, not a JSON value.

- [ ] **Step 5: Add the `handleSimpleLogin` function**

Find the last function definition before the global click handler (search for `function labelAccessibly` — defined right after `render()` — as a landing point, or any convenient spot among the other top-level function declarations) and insert:

```js
  // ---- Simplified test-build login (sadd-website-simple.html only — this
  //      function does not exist in the original sadd-website.html). Pure
  //      client-side check against one hardcoded credential — no network
  //      call, no session, no real auth. Appropriate only for a local
  //      personal test build, never for anything resembling production. ----
  function handleSimpleLogin(){
    const userEl = document.getElementById('simpleLoginUsername');
    const passEl = document.getElementById('simpleLoginPassword');
    const errEl = document.getElementById('simpleLoginError');
    const username = userEl ? userEl.value : '';
    const password = passEl ? passEl.value : '';
    if(errEl){ errEl.style.display = 'none'; errEl.textContent = ''; }
    if(username === 'admin' && password === 'admin'){
      goTo('dashboard');
    } else if(errEl){
      errEl.style.display = 'block';
      setEscapedText(errEl, 'Incorrect username or password.');
    }
  }
```

- [ ] **Step 6: Wire the Log In button in the global click handler**

Find the global click handler (search for `const gotoEl = e.target.closest('[data-goto]')` — this is inside the function that handles every click in the document) and add, near the top of that function, before the generic `data-goto` handling:

```js
    const simpleLoginBtn = e.target.closest('#simpleLoginBtn');
    if(simpleLoginBtn){
      handleSimpleLogin();
      return;
    }
```

- [ ] **Step 7: Verify — syntax, JSON integrity, and key counts**

```js
const fs = require('fs');
const html = fs.readFileSync('sadd-website-simple.html', 'utf8');

// screens: 49 keys, valid JSON, simplelogin present
const screensMatch = html.match(/const screens = (\{.*?\});/s);
const screens = JSON.parse(screensMatch[1]);
console.log('screens keys:', Object.keys(screens).length);
console.log('simplelogin present:', !!screens.simplelogin);

// screenMeta: 49 keys, simplelogin === 'auth'
const metaMatch = html.match(/const screenMeta = (\{.*?\});/s);
const screenMeta = JSON.parse(metaMatch[1]);
console.log('screenMeta keys:', Object.keys(screenMeta).length);
console.log('simplelogin meta:', screenMeta.simplelogin);

// state initializer
console.log('state has simplelogin entry:', html.includes("screen: 'simplelogin'"));
console.log('state no longer has welcome entry:', !html.includes("screen: 'welcome'"));

// every one of the original 48 screens must be byte-identical to the
// original file — this task only ADDS simplelogin, it never edits an
// existing screen's content
const origHtml = fs.readFileSync('sadd-website.html', 'utf8');
const origScreens = JSON.parse(origHtml.match(/const screens = (\{.*?\});/s)[1]);
let allMatch = true;
for (const key in origScreens) {
  if (screens[key] !== origScreens[key]) {
    console.log('MISMATCH in screen:', key);
    allMatch = false;
  }
}
console.log('all 48 original screens byte-identical:', allMatch);
```
Expected: `screens keys: 49`, `simplelogin present: true`, `screenMeta keys: 49`, `simplelogin meta: auth`, `state has simplelogin entry: true`, `state no longer has welcome entry: true`, no `MISMATCH` lines, `all 48 original screens byte-identical: true`.

Then check the `<script>` block parses as valid JS:
```js
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync('sadd-website-simple.html', 'utf8');
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
new vm.Script(scriptMatch[1]);
console.log('script syntax OK');
```
Expected: `script syntax OK`.

Finally, confirm `sadd-website.html` (the original) is completely untouched:
```bash
git status --short sadd-website.html
```
Expected: no output (not modified — only `sadd-website-simple.html` should be untracked/new).

- [ ] **Step 8: Commit**

```bash
git add sadd-website-simple.html
```
Use git identity: `GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com"`. Write the commit message to a heredoc file and use `git commit -F <file>` (embedded quotes in `-m` have broken this shell before in this project). Message: "feat: create sadd-website-simple.html with simplified login flow" plus a body noting this is a new standalone file, the original is untouched, and summarizing the simplelogin screen/handler added.

---

### Task 2: Redesign Parental Controls into flat rows

**Files:**
- Modify: `sadd-website-simple.html` (the `parental` entry in `screens` only)

**CRITICAL context — read before starting:** The current `parental` screen already has REAL, working backend-integration ids wired to actual JS functions elsewhere in this same file (from prior, unrelated work integrating this prototype with a real router backend): `id="parentalSafeSearchSwitch"`, `id="parentalBlockedSiteInput"`, `id="parentalBlockedSiteAddBtn"`, `id="parentalBlockedSiteError"`, `id="parentalBlockedSitesList"`. These ids are read by `renderParentalSafeSearchScreen`/`renderParentalBlockedSitesScreen`/`submitParentalBlockedSite` functions that already exist in the `<script>` section (unrelated to this task, already working, copied over automatically since this file is a full copy). **This task must preserve every one of these five ids exactly, in elements of the same type (a `<div class="switch">` for the switch, an `<input>` for the site input, etc.), unchanged in count and unchanged in what they wrap** — only the surrounding layout/styling changes. Breaking or duplicating any of these ids will break real, working functionality. Do not touch the JS functions that reference them.

**Step 1: Read the current `parental` screen's exact content first**

```js
const fs = require('fs');
const html = fs.readFileSync('sadd-website-simple.html', 'utf8');
const screensMatch = html.match(/const screens = (\{.*?\});/s);
const screens = JSON.parse(screensMatch[1]);
console.log(screens.parental);
```
Run this and read the full output before writing the replacement — confirm the five ids listed above are present exactly once each, and note their exact current surrounding markup (you'll be replacing the surrounding structure but preserving these elements' own tags/ids/classes that carry real behavior).

- [ ] **Step 2: Replace the detail-pane content (everything from the header row through the closing of the split-desk-detail div) with the new flat-rows layout**

The Family sidebar (`.split-desk-list` — Emma/Leo/Add child) is NOT part of this change and must remain completely untouched. Only the `.split-desk-detail` content changes.

Write the new `.split-desk-detail` inner content as:

```html
<div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:20px;"><div><strong style="font-size:17px;">Emma's controls</strong></div><button class="btn btn-secondary" style="width:auto;padding:10px 16px;font-size:12.5px;">Copy to another child</button><button class="btn btn-ghost" style="width:auto;padding:10px 16px;font-size:12.5px;" data-goto="usagereport">View weekly usage report</button></div>
<div class="setting-row" style="margin:0 0 16px;"><div class="sr-main"><strong>Email me this report weekly</strong><span>Sent every Sunday, opt-in</span></div><div class="switch"></div></div>
<div class="psec">Schedule</div>
<div class="prow"><div class="prow-main"><strong>Bedtime</strong><span>9:00 PM – 7:00 AM</span></div></div>
<div class="prow"><div class="prow-main"><strong>Pause now</strong><span>Instantly stop Wi-Fi</span></div><div class="switch"></div></div>
<div class="prow"><div class="prow-main"><strong>Homework mode</strong><span>Until 5:00 PM</span></div><div class="switch on"></div></div>
<div class="prow-block"><strong>Custom schedule</strong><div style="display:flex;gap:5px;margin:10px 0;"><span class="timer-chip" style="flex:1;text-align:center;padding:6px 0;">S</span><span class="timer-chip active" style="flex:1;text-align:center;padding:6px 0;">M</span><span class="timer-chip active" style="flex:1;text-align:center;padding:6px 0;">T</span><span class="timer-chip active" style="flex:1;text-align:center;padding:6px 0;">W</span><span class="timer-chip active" style="flex:1;text-align:center;padding:6px 0;">Th</span><span class="timer-chip active" style="flex:1;text-align:center;padding:6px 0;">F</span><span class="timer-chip" style="flex:1;text-align:center;padding:6px 0;">S</span></div><div class="grid-2"><div class="field"><label>From</label><input class="input" value="8:00 AM"></div><div class="field"><label>To</label><input class="input" value="4:00 PM"></div></div><div class="conn-toggle pill-toggle" style="max-width:260px;"><button class="active">Allow only</button><button>Block only</button></div></div>
<div class="psec">Content &amp; filtering</div>
<div class="prow-block"><strong>Filter level</strong><div class="conn-toggle pill-toggle" style="max-width:360px;margin-top:8px;"><button class="active">Kid-safe</button><button>Teen</button><button>Off</button><button>Custom</button></div></div>
<div class="prow-block"><strong>Blocked categories</strong><div style="margin-top:8px;">
<span class="catchip on">Adult content</span><span class="catchip on">Gambling</span><span class="catchip on">Violence</span><span class="catchip on">Weapons</span><span class="catchip on">Drugs &amp; alcohol</span><span class="catchip">Social media</span><span class="catchip">Gaming</span><span class="catchip">Video streaming</span><span class="catchip">P2P &amp; torrents</span><span class="catchip">Chat &amp; messaging</span><span class="catchip">Dating</span><span class="catchip">Hate speech</span><span class="catchip">Piracy</span><span class="catchip">Proxies &amp; VPNs</span><span class="catchip">Malware &amp; phishing</span>
</div></div>
<div class="prow"><div class="prow-main"><strong>Safe Search</strong><span>Filters results on Google, Bing, YouTube &amp; DuckDuckGo</span></div><div class="switch on" id="parentalSafeSearchSwitch"></div></div>
<div class="prow-block"><strong>Custom blocked sites</strong><div style="display:flex;gap:8px;margin:10px 0;"><input class="input" id="parentalBlockedSiteInput" placeholder="e.g. example.com or 203.0.113.4" style="flex:1;"><button class="btn btn-secondary" id="parentalBlockedSiteAddBtn" style="width:auto;padding:9px 16px;">+ Add</button></div><div id="parentalBlockedSiteError" style="display:none;color:var(--error);font-size:12px;margin-bottom:8px;"></div><div id="parentalBlockedSitesList"><div class="tech-row"><div class="tr-label">extra-homework-site.com</div><div class="tr-val">Blocked</div></div></div><button class="btn btn-ghost" style="width:auto;padding:8px 0;font-size:12px;">Export list</button></div>
<div class="psec">Apps</div>
<div class="prow"><div class="prow-main"><div class="ab-icon" style="background:#000;display:inline-flex;width:22px;height:22px;border-radius:6px;color:#fff;align-items:center;justify-content:center;font-size:11px;margin-right:8px;">T</div><strong>TikTok</strong><span>Reliable blocking</span></div><div class="switch on"></div></div>
<div class="prow"><div class="prow-main"><div class="ab-icon" style="background:#DB2777;display:inline-flex;width:22px;height:22px;border-radius:6px;color:#fff;align-items:center;justify-content:center;font-size:11px;margin-right:8px;">I</div><strong>Instagram</strong><span>Reliable blocking</span></div><div class="switch on"></div></div>
<div class="prow"><div class="prow-main"><div class="ab-icon" style="background:#DC2626;display:inline-flex;width:22px;height:22px;border-radius:6px;color:#fff;align-items:center;justify-content:center;font-size:11px;margin-right:8px;">Y</div><strong>YouTube</strong><span>Reliable blocking</span></div><div class="switch"></div></div>
<div class="prow"><div class="prow-main"><div class="ab-icon" style="background:#059669;display:inline-flex;width:22px;height:22px;border-radius:6px;color:#fff;align-items:center;justify-content:center;font-size:11px;margin-right:8px;">R</div><strong>Roblox</strong><span>Best-effort blocking</span></div><div class="switch"></div></div>
<p style="font-size:11px;color:var(--muted-2);margin:4px 0 0;">Best-effort apps use traffic patterns that can change — we can't promise 100% blocking the way we can for Reliable ones.</p>
<div class="prow-block"><strong>Exceptions</strong><p style="font-size:11.5px;color:var(--muted-2);margin:4px 0 10px;">Overrides to the category defaults above, just for Emma.</p><div class="tech-row"><div class="tr-label">wikipedia.org allowed even though Social media is blocked</div><div class="tr-val">Active</div></div><button class="btn btn-ghost" style="width:auto;padding:8px 0;font-size:12px;">+ Add an exception</button></div>
```

Every real toggle state above is copied exactly from the current screen's real data (5 of 15 categories on: Adult content, Gambling, Violence, Weapons, Drugs & alcohol; TikTok/Instagram blocked, YouTube/Roblox allowed; Homework mode on, Pause now off; Safe Search on) — do not invent or guess values, use what's read back in Step 1.

- [ ] **Step 3: Add the new CSS classes used above (`.psec`, `.prow`, `.prow-main`, `.prow-block`, `.catchip`)**

These are new, not in the original file. Add them to the `<style>` block (search for `.setting-row{` as a landing point to insert nearby, keeping related row/card styles together):

```css
  .psec{font-size:11px;font-weight:700;letter-spacing:.06em;color:var(--teal-dark);text-transform:uppercase;margin:22px 0 8px;}
  .psec:first-of-type{margin-top:0;}
  .prow{display:flex;align-items:center;justify-content:space-between;padding:13px 0;border-bottom:1px solid var(--border);}
  .prow:last-child{border-bottom:none;}
  .prow-main{display:flex;align-items:center;}
  .prow-main strong{display:block;font-size:14px;color:var(--text);}
  .prow-main span{font-size:12px;color:var(--muted);}
  .prow-block{padding:13px 0;border-bottom:1px solid var(--border);}
  .prow-block strong{display:block;font-size:14px;color:var(--text);}
  .catchip{display:inline-flex;padding:5px 11px;font-size:11.5px;border-radius:14px;background:var(--teal);color:#fff;margin:0 5px 5px 0;}
  .catchip:not(.on){background:var(--bg);color:var(--muted-2);border:1px solid var(--border);}
```
Note: `.catchip.on` in the markup above should actually be selected as `.catchip.on{background:var(--teal);color:#fff;}` and the default (no `.on`) should be the muted style — adjust the CSS so `.catchip` alone is the OFF/muted style and `.catchip.on` is the teal/active style, matching how `.switch`/`.switch.on` already works elsewhere in this file (the `on` class added by JS to modify a base class, not two separate independent styles) — write it as:
```css
  .catchip{display:inline-flex;padding:5px 11px;font-size:11.5px;border-radius:14px;background:var(--bg);color:var(--muted-2);border:1px solid var(--border);margin:0 5px 5px 0;}
  .catchip.on{background:var(--teal);color:#fff;border-color:var(--teal);}
```

- [ ] **Step 4: Apply the Step 2 replacement via a Node script**

Read the exact current `.split-desk-detail` inner content (from Step 1's output) into `oldBlock` in a script structured exactly like Task 1's edit scripts (`JSON.parse` the `screens` object, verify `screens.parental.includes(oldBlock)` before replacing, `.split(oldBlock).join(newBlock)`, re-stringify, write back) — follow the same pattern used throughout this file's editing history (see Task 1 Step 3 for the exact script shape). Since the exact current text depends on Step 1's live output, construct `oldBlock` from what you actually read, not from a guess.

- [ ] **Step 5: Verify**

```js
const fs = require('fs');
const html = fs.readFileSync('sadd-website-simple.html', 'utf8');
const screensMatch = html.match(/const screens = (\{.*?\});/s);
const screens = JSON.parse(screensMatch[1]);
const p = screens.parental;
['parentalSafeSearchSwitch','parentalBlockedSiteInput','parentalBlockedSiteAddBtn','parentalBlockedSiteError','parentalBlockedSitesList'].forEach(id => {
  const count = (p.match(new RegExp('id="' + id + '"', 'g')) || []).length;
  console.log(id + ':', count);
});
console.log('total screens keys (should still be 49):', Object.keys(screens).length);
```
Expected: each of the five ids prints `1` (present exactly once, not zero, not duplicated), and `49` keys total. Also confirm every OTHER screen besides `parental` is byte-identical to the post-Task-1 state (diff the two JSON objects key by key, expect only `parental` to differ).

Run the same `<script>` syntax check as Task 1 Step 7.

- [ ] **Step 6: Commit**

```bash
git add sadd-website-simple.html
```
Same git identity as Task 1. Heredoc + `git commit -F`. Message: "feat: redesign Parental Controls into flat single-column rows" plus a body noting the five preserved real-functionality ids were verified unchanged in count/location.

---

### Task 3: Whole-app light/dark theme toggle

**Files:**
- Modify: `sadd-website-simple.html` (`<style>` block, app shell markup, new JS)

**Context you need:** The `:root` block (`sadd-website.html:12-20`) already defines the app's core palette as CSS custom properties. `body{background:#EEF2F6;...}` (line 22) is the one structural color set directly on `body`, not via a variable. The persistent app shell has a `.sidebar-foot` (search for `class="sidebar-foot"`) containing a "Settings" row and a user info block — this is where the toggle goes for every logged-in screen; the `simplelogin` screen (Task 1) needs its own toggle too, since it renders outside the shell.

- [ ] **Step 1: Add the dark palette to `:root` and a body-background variable**

Find the `:root{...}` block and add a `--page-bg` variable, then add a `:root[data-theme="dark"]` override block immediately after it:

```css
  :root{
    color-scheme: light;
    --teal:#0D9488; --teal-dark:#0F766E; --teal-light:#CCFBF1; --teal-tint:#F0FDFA;
    --success:#16A34A; --success-tint:#F0FDF4;
    --warning:#D97706; --warning-tint:#FFFBEB;
    --error:#DC2626; --error-tint:#FEF2F2;
    --bg:#F8FAFC; --card:#FFFFFF; --border:#E2E8F0;
    --text:#0F172A; --muted:#64748B; --muted-2:#94A3B8;
    --page-bg:#EEF2F6;
  }
  :root[data-theme="dark"]{
    color-scheme: dark;
    --teal:#14B8A6; --teal-dark:#2DD4BF; --teal-light:#134E4A; --teal-tint:#0F2E2B;
    --success:#22C55E; --success-tint:#052E16;
    --warning:#F59E0B; --warning-tint:#451A03;
    --error:#EF4444; --error-tint:#450A0A;
    --bg:#0F172A; --card:#161E2E; --border:#253046;
    --text:#F1F5F9; --muted:#94A3B8; --muted-2:#64748B;
    --page-bg:#0B1120;
  }
```
(insert the dark block immediately after the existing `:root{...}` block, keeping the original light block's values completely unchanged — this is additive, not a replacement of the light palette).

- [ ] **Step 2: Point `body`'s background at the new variable**

Find `body{margin:0;font-family:'Inter',system-ui,sans-serif;background:#EEF2F6;color:var(--text);}` and change `background:#EEF2F6;` to `background:var(--page-bg);`.

- [ ] **Step 3: Convert the mechanical, exact-value matches to `var()` — safe, unambiguous find-and-replace**

Search the `<style>` block for each of these literal hex values and replace with the shown variable, ONLY where the color is being used as a plain `color`/`background`/`background-color`/`border-color` value (not inside a `box-shadow`'s rgba, not inside a data URI, not inside a comment) — these 12 values are each single- or double-occurrence and exactly equal an existing (now also dark-mode-aware) variable's light value, so this conversion is mechanical, not judgment-based:

| Literal value | Replace with |
|---|---|
| `#0F766E` | `var(--teal-dark)` |
| `#CCFBF1` | `var(--teal-light)` |
| `#F0FDFA` | `var(--teal-tint)` |
| `#16A34A` | `var(--success)` |
| `#F0FDF4` | `var(--success-tint)` |
| `#D97706` | `var(--warning)` |
| `#FFFBEB` | `var(--warning-tint)` |
| `#DC2626` | `var(--error)` |
| `#FEF2F2` | `var(--error-tint)` |
| `#E2E8F0` | `var(--border)` |
| `#64748B` | `var(--muted)` |
| `#0D9488` (both occurrences) | `var(--teal)` |

- [ ] **Step 4: Review and convert the remaining, judgment-requiring occurrences**

For each of the following, read every CSS rule it appears in (grep the `<style>` block for the literal hex, read the full selector + property it's attached to) and decide, per-occurrence — **the same literal value can play a structural role in one rule and a non-structural role in another; do not treat a color value as inherently "structural" or "accent," read each rule**:

- **`#fff` (56 occurrences) and `#FFFFFF` (1 occurrence)**: where it's a card/panel/page background (e.g. `.card{background:#fff}`), convert to `var(--card)`. Where it's text or an icon stroke sitting on top of a colored (non-white-in-dark-mode) surface — e.g. white text on a teal button, a white checkmark icon on a green circle — leave it as literal `#fff`/`#FFFFFF`, since that surface stays the same brand color in both themes and needs to keep contrasting against it.
- **`#0F172A` (3 occurrences, excluding the one already inside `:root` itself from Step 1) and `#94A3B8` (3 occurrences)**: these are the literal light-mode values of `--text` and `--muted-2` respectively, hardcoded again outside `:root` — almost certainly should become `var(--text)`/`var(--muted-2)`, but confirm each occurrence is genuine body/label text and not, for example, an SVG icon `stroke` color that's meant to stay dark regardless of theme (unlikely here, but check).
- **`#F1F5F9` (5 occurrences)**: doesn't exactly match any existing variable. Read each of the 5 rules — if it's a light, subtle background fill (e.g. a muted pill/chip background, a hover state), it's structural and should darken in dark mode; introduce a new variable for it (add `--bg-subtle:#F1F5F9;` to the light `:root` block and `--bg-subtle:#1E293B;` to the dark block from Step 1, then point all 5 occurrences at `var(--bg-subtle)`).
- **`#1E293B` (4 occurrences)**: read each rule this appears in. If any of the 4 are being used as a decorative dark surface that's ALREADY dark in the light theme (e.g. a phone-mockup device frame, a "dark card" component intentionally shown dark regardless of overall theme, common in marketing-screen device previews elsewhere in this file), leave those specific occurrences as literal `#1E293B` — they're not meant to respond to the theme at all. If any are actually meant to be body/heading text that just happens to duplicate a value close to `--text`, convert those specific occurrences to `var(--text)`.
- **Everything else** (`#FDE68A`, `#BBF7D0`, `#166534`, `#92400E`, `#CBD5E1`, `#FCA5A5`, `#FCD34D`, `#86EFAC`, `#99F6E4`, `#0F5D57`, `#0B5F58`, `#B7E9E4`, `#DFF7F4`, `#FECACA`, `#0B1120`, `#F8FAFC` where it's not already handled above): these are single/low-occurrence status-pill and decorative colors (light-background/dark-text badge pairs). Per the design spec's approved scope ("brand/status accent colors stay literal in both themes"), leave these as literal values, unchanged. Do not convert them.

- [ ] **Step 5: Convert the 13 inline colors inside `screens` content the same way**

Re-run the audit script from the design spec to re-locate them post-Task-2 (Task 2 may have changed which screen some occurrences are in, though not the total set — the Parental Controls edit didn't introduce or remove any of the original 13):

```js
const fs = require('fs');
const html = fs.readFileSync('sadd-website-simple.html', 'utf8');
const screensMatch = html.match(/const screens = (\{.*?\});/s);
const screens = JSON.parse(screensMatch[1]);
const hexRe = /#[0-9a-fA-F]{3,8}\b/g;
for (const key in screens) {
  const matches = screens[key].match(hexRe) || [];
  if (matches.length) console.log(key, ':', matches.join(', '));
}
```
For each hit, apply the same per-occurrence judgment as Step 4 (structural → `var(--x)`, even inside an inline `style="..."` attribute, which CSS variables work fine in; brand/status accent → leave literal). Based on the design spec's audit, expect mostly avatar/icon/status accents (Leo's avatar purple `#7C3AED`, TikTok's `#000`, Instagram's `#DB2777`, status reds/greens) that should stay literal — but verify against the actual current content rather than assuming the spec's audit (taken against the ORIGINAL file) still applies exactly to this now-modified copy.

- [ ] **Step 6: Add the toggle UI — sidebar footer (logged-in screens) and the login page**

In the `.sidebar-foot` markup (search for `class="sidebar-foot"`), add a new row before the existing "Settings" `.foot-item`:

```html
<div class="foot-item" id="themeToggleRow" style="cursor:pointer;"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg><span id="themeToggleLabel">Dark mode</span></div>
```
(this markup edit happens inside the app shell's static HTML — outside the `screens`/`screenMeta` objects, so edit it directly, same as Task 1 Step 4/6's direct text edits, not via a JSON round-trip.)

On the `simplelogin` screen (from Task 1), add a small toggle in the corner of the `wizard-card` — edit `screens.simplelogin` (a `JSON.parse`/edit/`JSON.stringify` round-trip, same pattern as Task 1 Step 3) to insert this as the first child inside `<div class="wizard-card" style="max-width:360px;">`:

```html
<div id="loginThemeToggle" style="position:absolute;top:20px;right:20px;cursor:pointer;color:var(--muted);" title="Toggle dark mode"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg></div>
```
and add `position:relative;` to the `wizard-card` div's inline style (`style="max-width:360px;position:relative;"`) so the toggle positions correctly within it.

- [ ] **Step 7: Add the theme toggle JS — apply on load, toggle function, persistence**

Insert near the top of the `<script>` block, before `const state = {...}` (so the theme is applied before the first `render()` call, avoiding a flash of the wrong theme):

```js
  (function applyStoredTheme(){
    let saved = null;
    try { saved = localStorage.getItem('sadd-simple-theme'); } catch(e) {}
    if(saved === 'dark'){ document.documentElement.setAttribute('data-theme', 'dark'); }
  })();

  function toggleTheme(){
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    const next = isDark ? 'light' : 'dark';
    if(next === 'dark'){ document.documentElement.setAttribute('data-theme', 'dark'); }
    else { document.documentElement.removeAttribute('data-theme'); }
    try { localStorage.setItem('sadd-simple-theme', next); } catch(e) {}
    const label = document.getElementById('themeToggleLabel');
    if(label) label.textContent = next === 'dark' ? 'Light mode' : 'Dark mode';
  }
```

Wire both toggle elements in the global click handler, near the `simpleLoginBtn` block added in Task 1 Step 6:

```js
    const themeToggleRow = e.target.closest('#themeToggleRow');
    if(themeToggleRow){
      toggleTheme();
      return;
    }
    const loginThemeToggle = e.target.closest('#loginThemeToggle');
    if(loginThemeToggle){
      toggleTheme();
      return;
    }
```

Finally, make sure the sidebar's `#themeToggleLabel` text reflects the current theme on every render, not just right after a toggle click (in case the page loaded with dark mode already applied from `localStorage`) — add this line inside `render()`'s `else` branch (the `"app"` / logged-in path), anywhere after `shellEl.classList.add('show');`:

```js
      const themeLabelEl = document.getElementById('themeToggleLabel');
      if(themeLabelEl) themeLabelEl.textContent = document.documentElement.getAttribute('data-theme') === 'dark' ? 'Light mode' : 'Dark mode';
```

- [ ] **Step 8: Verify**

Run the Task 1 Step 7-style syntax/JSON checks again (script parses, `screens`/`screenMeta` still valid JSON with 49 keys each).

Re-run the color audit script from Step 5 and confirm every remaining literal hex value in both the `<style>` block and `screens` content is one you deliberately decided to leave literal in Steps 3-5 (i.e., you can account for every remaining hardcoded color, none are accidentally-still-hardcoded structural colors you meant to convert).

Manually trace: does `document.documentElement.setAttribute('data-theme', 'dark')` (or its removal) genuinely change what `:root[data-theme="dark"]` selects, given the IIFE in Step 7 runs before `<body>` even exists yet (it only touches `document.documentElement`, i.e. `<html>`, which is available as soon as its own opening tag is parsed — confirm this by checking the IIFE's placement is inside a `<script>` tag that appears AFTER the opening `<html>` tag in document order, which it necessarily is since the whole app's `<script>` block is inside `<body>`).

- [ ] **Step 9: Commit**

```bash
git add sadd-website-simple.html
```
Same git identity. Heredoc + `git commit -F`. Message: "feat: add whole-app light/dark theme toggle" plus a body summarizing which colors were converted to variables vs. deliberately left literal (reference the categories from Step 4), and noting the toggle's two entry points (sidebar footer, login page) and localStorage persistence.

---

### Task 4: Final verification and a file-header note

**Files:**
- Modify: `sadd-website-simple.html` (a new header comment only)

- [ ] **Step 1: Add a header comment explaining what this file is**

Immediately after the `<!DOCTYPE html>` line, insert:

```html
<!--
  sadd-website-simple.html — a standalone test-build copy of sadd-website.html.
  Three differences from the original, documented in
  docs/superpowers/specs/2026-09-02-simple-test-build-design.md:
    1. Simplified login (username/password, admin/admin) replaces the full
       onboarding flow — lands straight on the Dashboard.
    2. Parental Controls is a flat single-column rows layout instead of the
       original's dense 2-column grid.
    3. A light/dark theme toggle (sidebar footer + login page), structural
       colors only — brand/status accent colors are unchanged in both themes.
  sadd-website.html itself is never modified by any of the above.
-->
```

- [ ] **Step 2: Full-file verification pass**

Run every verification script from Tasks 1-3 one final time in sequence against the final state of the file, confirming all still pass. Additionally:

```bash
diff sadd-website.html sadd-website-simple.html | head -5
```
Expected: real differences shown (confirms the files have genuinely diverged — an empty diff here would mean something went wrong).

```bash
git status --short sadd-website.html
```
Expected: no output (the original file was never touched across all 4 tasks).

- [ ] **Step 3: Commit**

```bash
git add sadd-website-simple.html
```
Same git identity. Heredoc + `git commit -F`. Message: "docs: add file-header note to sadd-website-simple.html" plus a body confirming the final verification pass results (script syntax, JSON validity, key counts, original-file-untouched confirmation).

---

## After all tasks

Dispatch one final whole-file code-quality review (a fresh `superpowers:code-reviewer` subagent, given the full diff across all 4 tasks) — pay particular attention to: whether the five real backend-integration ids on the redesigned Parental Controls screen (`parentalSafeSearchSwitch`, `parentalBlockedSiteInput`, `parentalBlockedSiteAddBtn`, `parentalBlockedSiteError`, `parentalBlockedSitesList`) are genuinely unchanged and still wired correctly to their existing JS functions; whether the dark-mode conversion actually achieved what Task 3's per-occurrence judgment calls intended (spot-check a sample of the "leave literal" and "convert to var()" decisions against the actual rules they're used in); and whether `sadd-website.html` remains byte-for-byte untouched across the whole plan. Fix anything it raises, commit, then report this feature complete.
