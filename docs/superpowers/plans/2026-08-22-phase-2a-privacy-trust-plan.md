# Phase 2a — Privacy & Trust Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 5 P0 gaps identified in the Phase 2 gap analysis (`docs/superpowers/specs/2026-08-22-phase-2-gap-analysis-findings.md`): add a Privacy screen and an About screen to `sadd-website.html`, add an SSH-access toggle to its existing `advapi` screen, and wire up the already-present but inert "Help & About" row in `sadd-mobile-app.html` to a matching About screen.

**Architecture:** `sadd-website.html` stores all screens in `const screens = {...}`, a **single-line JSON-escaped object** (double-quoted strings) — per this project's established convention (see prior phase plans), edits to it are done via a Python `json.loads`/`json.dumps` round-trip script, never raw string editing on the single giant line, to avoid escaping bugs. `screenMeta` is the same single-line-JSON pattern. `textLinkMap` is a normal multi-line JS object literal and can be edited directly. `sadd-mobile-app.html` stores screens as ES6 template literals (multi-line, real text) and is edited directly with the `Edit` tool using the boundary-anchoring pattern already established for that file.

**Tech Stack:** Static HTML/CSS/vanilla JS, Python 3 (round-trip script for `sadd-website.html`), Node (verification), Git.

---

### Task 1: Add `privacy` and `about` screens to `sadd-website.html`, wire up Settings

**Files:** Modify `sadd-website.html`

- [ ] **Step 1: Re-check current line numbers** (they may have shifted since this plan was written):

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = " sadd-website.html
grep -n "^  const screenMeta = " sadd-website.html
grep -n "const textLinkMap = {" sadd-website.html
```

- [ ] **Step 2: Add the two new screens and update `screenMeta` via a Python round-trip script**

Write and run this script (adjust the `screens =` / `screenMeta =` line-number variables if Step 1showed different numbers than below — use the grep output, don't assume):

```python
import json, re

with open('sadd-website.html', 'r', encoding='utf-8') as f:
    content = f.read()

# --- screens ---
m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))

screens['privacy'] = (
    '<div class="page-crumb" data-goto="settings"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>Back to Settings</div>'
    '<div class="wizard-desk"><div class="wizard-card" style="max-width:560px;">'
    '<h1 class="scr-title">Privacy</h1>'
    '<div class="setting-row mt-24" style="align-items:flex-start;">'
    '<div class="sr-main"><strong>Local by default</strong><span>All traffic inspection runs on your router. Nothing leaves your home unless you turn the option below on.</span></div>'
    '</div>'
    '<div class="setting-row" style="align-items:flex-start;">'
    '<div class="sr-main"><strong>Share diagnostic data with the cloud</strong><span>Off by default. If turned on, we only share device counts and threat categories — never browsing history or content.</span></div>'
    '<div class="switch"></div>'
    '</div>'
    '<div class="sec-label mt-24">How long we keep local logs</div>'
    '<div class="radio-card"><div class="rc-dot"></div><div class="rc-main"><strong>7 days</strong></div></div>'
    '<div class="radio-card active"><div class="rc-dot"></div><div class="rc-main"><strong>30 days</strong></div></div>'
    '<div class="radio-card"><div class="rc-dot"></div><div class="rc-main"><strong>90 days</strong></div></div>'
    '<span style="font-size:12.5px;color:var(--muted-2);display:block;margin-top:-4px;margin-bottom:20px;">Cloud retention only applies if diagnostic sharing above is on.</span>'
    '<div class="setting-row" style="border-top:1px solid var(--border);padding-top:16px;">'
    '<div class="sr-main"><strong>Delete my account and data</strong><span>Removes your account and all associated data within 30 days</span></div>'
    '</div>'
    '</div></div>'
)

screens['about'] = (
    '<div class="page-crumb" data-goto="settings"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>Back to Settings</div>'
    '<div class="wizard-desk"><div class="wizard-card" style="max-width:560px;">'
    '<h1 class="scr-title">About</h1>'
    '<div class="setting-row mt-24"><div class="sr-main"><strong>App version</strong><span>1.0.0</span></div></div>'
    '<div class="setting-row" style="align-items:flex-start;"><div class="sr-main"><strong>Where your Sadd router is made</strong><span>Designed and assembled in the USA. See our compliance statement for full supply-chain details.</span></div></div>'
    '</div></div>'
)

# add "Privacy" and "About" rows to the settings screen, right after "Notifications" and before the advanced-mode warning
old_settings_fragment = '<div class="sr-main"><strong>Notifications</strong><span>3 enabled</span></div></div>\\n        <div class="adv-warning mt-24">'
new_settings_fragment = (
    '<div class="sr-main"><strong>Notifications</strong><span>3 enabled</span></div></div>\\n        '
    '<div class="setting-row"><div class="sr-icon"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-11V5l-8-3-8 3v6c0 7 8 11 8 11Z"/></svg></div><div class="sr-main"><strong>Privacy</strong><span>Data &amp; cloud sharing</span></div><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--muted-2)" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg></div>\\n        '
    '<div class="setting-row"><div class="sr-icon"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg></div><div class="sr-main"><strong>About</strong><span>Version &amp; compliance</span></div><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--muted-2)" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg></div>\\n        '
    '<div class="adv-warning mt-24">'
)
assert old_settings_fragment in screens['settings'], "settings fragment not found — settings screen content may have changed, inspect manually"
screens['settings'] = screens['settings'].replace(old_settings_fragment, new_settings_fragment)

content = content[:m.start(1)] + json.dumps(screens) + content[m.end(1):]

# --- screenMeta ---
m2 = re.search(r'const screenMeta = (\{.*?\});\r?\n', content)
screenMeta = json.loads(m2.group(1))
screenMeta['privacy'] = 'app'
screenMeta['about'] = 'app'
content = content[:m2.start(1)] + json.dumps(screenMeta) + content[m2.end(1):]

with open('sadd-website.html', 'w', encoding='utf-8') as f:
    f.write(content)

print("Done. New screens object has", len(screens), "keys.")
```

- [ ] **Step 3: Add `textLinkMap` entries** (this one is a plain multi-line JS object, edit directly with the `Edit` tool):

old_string:
```
    'Guest network':'guest','Show advanced settings':'advhub','Ad Blocking':'adblock'
  };
```
new_string:
```
    'Guest network':'guest','Show advanced settings':'advhub','Ad Blocking':'adblock',
    'Privacy':'privacy','About':'about'
  };
```

- [ ] **Step 4: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json, re
content = open('sadd-website.html', encoding='utf-8').read()
m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))
assert 'privacy' in screens and 'about' in screens, 'new screens missing'
m2 = re.search(r'const screenMeta = (\{.*?\});\r?\n', content)
meta = json.loads(m2.group(1))
assert meta.get('privacy') == 'app' and meta.get('about') == 'app'
print('OK: screens and screenMeta round-trip valid, privacy/about present')
"
grep -c "'Privacy':'privacy'" sadd-website.html
grep -c "'About':'about'" sadd-website.html
```
Expected: `OK: ...` line printed, both greps return `1`.

- [ ] **Step 5: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: add Privacy and About screens to sadd-website.html (US-11.1, US-11.2, US-11.3, US-15.1)"
```

---

### Task 2: Add SSH-access toggle to the existing `advapi` screen

**Files:** Modify `sadd-website.html`

- [ ] **Step 1: Re-check current line number** — `grep -n "^  const screens = " sadd-website.html`

- [ ] **Step 2: Add the SSH row via a Python round-trip script**

```python
import json, re

with open('sadd-website.html', 'r', encoding='utf-8') as f:
    content = f.read()

m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))

old_fragment = '<div class="setting-row"><div class="sr-main"><strong>Send events to a URL</strong><span>Not configured</span></div></div>\\n      </div></div>'
new_fragment = (
    '<div class="setting-row"><div class="sr-main"><strong>Send events to a URL</strong><span>Not configured</span></div></div>\\n        '
    '<div class="sec-label mt-24">Remote access</div>'
    '<div class="setting-row"><div class="sr-main"><strong>SSH access</strong><span>Off by default. When enabled, uses a unique key for this device — never a shared or default password.</span></div><div class="switch"></div></div>'
    '\\n      </div></div>'
)
assert old_fragment in screens['advapi'], "advapi fragment not found — screen content may have changed, inspect manually"
screens['advapi'] = screens['advapi'].replace(old_fragment, new_fragment)

content = content[:m.start(1)] + json.dumps(screens) + content[m.end(1):]

with open('sadd-website.html', 'w', encoding='utf-8') as f:
    f.write(content)

print("Done.")
```

- [ ] **Step 3: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json, re
content = open('sadd-website.html', encoding='utf-8').read()
m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))
assert 'SSH access' in screens['advapi'], 'SSH row missing from advapi'
print('OK: SSH access row present in advapi')
"
```

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: add SSH access toggle to advapi screen (US-14.3)"
```

---

### Task 3: Wire up the "Help & About" row in `sadd-mobile-app.html`

**Files:** Modify `sadd-mobile-app.html`

- [ ] **Step 1: Verify current state**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -c "about:" sadd-mobile-app.html
```
Expected: `0`.

- [ ] **Step 2: Add `data-goto="about"` to the existing row and add the `about` screen**

Use the `Edit` tool with old_string:
```
      <div class="setting-row">
        <div class="sr-icon"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg></div>
        <div class="sr-main"><strong>Help &amp; About</strong><span>App version 1.0.0</span></div>
      </div>
      <button class="btn btn-danger-soft mt-24">Forget this router</button>
    `,

  };
```
new_string:
```
      <div class="setting-row" data-goto="about">
        <div class="sr-icon"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg></div>
        <div class="sr-main"><strong>Help &amp; About</strong><span>App version 1.0.0</span></div>
      </div>
      <button class="btn btn-danger-soft mt-24">Forget this router</button>
    `,

    about: `
      <div class="page-crumb" data-goto="settings"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>Back</div>
      <h1 class="scr-title">About</h1>
      <div class="setting-row"><div class="sr-main"><strong>App version</strong><span>1.0.0</span></div></div>
      <div class="setting-row"><div class="sr-main"><strong>Where your Sadd router is made</strong><span>Designed and assembled in the USA.</span></div></div>
    `,

  };
```

- [ ] **Step 3: Update `mainScreens` and `render()`'s tab-mapping so the bottom nav stays visible and Settings stays highlighted on the About screen**

old_string:
```
  const mainScreens = ['devices','devicedetail','network','settings'];
```
new_string:
```
  const mainScreens = ['devices','devicedetail','network','settings','about'];
```

old_string:
```
    const activeTab = state.screen === 'devicedetail' ? 'devices' : state.screen;
```
new_string:
```
    const activeTab = state.screen === 'devicedetail' ? 'devices' : (state.screen === 'about' ? 'settings' : state.screen);
```

- [ ] **Step 4: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && node -e "
const fs = require('fs');
const html = fs.readFileSync('sadd-mobile-app.html', 'utf-8');
const match = html.match(/<script>([\s\S]*)<\/script>/);
try { new Function(match[1]); console.log('Script parses as valid JS: true'); }
catch (e) { console.log('SYNTAX ERROR:', e.message); }
"
grep -c "    about: \`" sadd-mobile-app.html
grep -c "data-goto=\"about\"" sadd-mobile-app.html
```
Expected: `Script parses as valid JS: true`, `about: \`` count `1`, `data-goto="about"` count `1`.

- [ ] **Step 5: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-mobile-app.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: wire up Help & About row to a real About screen (US-15.1)"
```

---

### Task 4: Final verification and push

**Files:** none (verification only)

- [ ] **Step 1: Full round-trip check on `sadd-website.html`**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json, re
content = open('sadd-website.html', encoding='utf-8').read()
m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))
print('screens keys:', len(screens))
assert 'privacy' in screens and 'about' in screens and 'SSH access' in screens['advapi']
print('OK')
"
```

- [ ] **Step 2: Full parse check on `sadd-mobile-app.html`**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && node -e "
const fs = require('fs');
const html = fs.readFileSync('sadd-mobile-app.html', 'utf-8');
new Function(html.match(/<script>([\s\S]*)<\/script>/)[1]);
console.log('OK');
"
```

- [ ] **Step 3: Manual browser check** — open both files, navigate Settings → Privacy and Settings → About in `sadd-website.html` (confirm back-crumb returns to Settings, switch/radio-card toggle correctly), Advanced Settings → Developer & API Access (confirm the new SSH toggle works), and Settings → Help & About in `sadd-mobile-app.html` (confirm it now navigates to a real About screen with the bottom nav still showing Settings as active).

- [ ] **Step 4: Push**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git push origin main
```
