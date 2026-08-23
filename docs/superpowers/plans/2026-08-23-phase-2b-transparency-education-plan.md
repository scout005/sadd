# Phase 2b — Transparency & Education Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 4 P0 gaps from the Phase 2 gap analysis: a block-detail tap-through with plain-English explanations and an inline allow action (`US-4.1`, `US-4.4`), a standalone Networking glossary (`US-16.1`), and a comfort-level onboarding question in both prototypes (`US-16.2`).

**Architecture:** Same as Phase 2a — `sadd-website.html`'s `screens`/`screenMeta` are single-line JSON, edited via Python `json.loads`/`json.dumps` round-trip; `forwardMap`/`textLinkMap` are plain JS objects, edited directly. `sadd-mobile-app.html`'s `screens` are template literals, edited directly with `Edit`'s boundary-anchoring pattern. Both files already have a generic `[data-goto]` click handler that fires before any row/textLinkMap matching, so new tappable cards/rows can use `data-goto="<screen>"` directly without touching either file's shared click-handler logic.

**Tech Stack:** Static HTML/CSS/vanilla JS, Python 3, Node, Git.

---

### Task 1: `sadd-website.html` — block-detail tap-through

**Files:** Modify `sadd-website.html`

- [ ] **Step 1: Re-check current line numbers**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = " sadd-website.html
```

- [ ] **Step 2: Add `blockdetail` screen and wire the two existing log rows to it, via Python round-trip**

```python
import json, re

path = r'c:\Users\hamzaz.SQU\Documents\projects\router\sadd-website.html'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))

screens['blockdetail'] = (
    '<div class="page-crumb" data-goto="security"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>Back to Security</div>'
    '<div class="wizard-desk"><div class="wizard-card" style="max-width:560px;">'
    '<h1 class="scr-title">Malicious domain blocked</h1>'
    '<div class="setting-row mt-24"><div class="sr-main"><strong>Device</strong><span>Leo\'s Laptop</span></div></div>'
    '<div class="setting-row"><div class="sr-main"><strong>When</strong><span>2 days ago, 4:12 PM</span></div></div>'
    '<div class="setting-row" style="align-items:flex-start;"><div class="sr-main"><strong>Why we blocked it</strong><span>This site is on a list of domains known to spread malware. We stopped the connection before any data was exchanged.</span></div></div>'
    '<button class="btn btn-secondary mt-24" style="width:auto;padding:11px 22px;">This looks wrong \u2014 allow it</button>'
    '</div></div>'
)

old_rows = '<div class="mini-log-row"><strong>Malicious domain blocked</strong><span>2 days ago</span></div>\n                <div class="mini-log-row"><strong>Phishing link blocked</strong><span>5 days ago</span></div>'
new_rows = '<div class="mini-log-row" data-goto="blockdetail"><strong>Malicious domain blocked</strong><span>2 days ago</span></div>\n                <div class="mini-log-row" data-goto="blockdetail"><strong>Phishing link blocked</strong><span>5 days ago</span></div>'
assert old_rows in screens['security'], "mini-log-row block not found in security screen"
screens['security'] = screens['security'].replace(old_rows, new_rows)

content = content[:m.start(1)] + json.dumps(screens) + content[m.end(1):]

m2 = re.search(r'const screenMeta = (\{.*?\});\r?\n', content)
screenMeta = json.loads(m2.group(1))
screenMeta['blockdetail'] = 'app'
content = content[:m2.start(1)] + json.dumps(screenMeta) + content[m2.end(1):]

with open(path, 'w', encoding='utf-8') as f:
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
assert 'blockdetail' in screens
assert screens['security'].count('data-goto=\"blockdetail\"') == 2
print('OK')
"
```

- [ ] **Step 4: Commit** — `"feat: add block-detail screen with plain-English explanation and allow action (US-4.1, US-4.4)"` (standard `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env vars).

---

### Task 2: `sadd-website.html` — standalone Networking glossary

**Files:** Modify `sadd-website.html`

- [ ] **Step 1: Re-check current line number** — `grep -n "^  const screens = " sadd-website.html`

- [ ] **Step 2: Add `glossary` screen and a link row on `help`, via Python round-trip**

```python
import json, re

path = r'c:\Users\hamzaz.SQU\Documents\projects\router\sadd-website.html'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))

terms = [
    ("VPN", "A private, encrypted connection back to your home network from anywhere."),
    ("VLAN", "A way to split your Wi-Fi into separate, isolated zones \u2014 like Kids, Guests, and Smart Home."),
    ("IP address", "The unique number your router or device uses to be found on a network."),
    ("DNS", "The system that turns website names (like google.com) into addresses computers understand."),
    ("Firewall", "A filter that blocks unwanted traffic from reaching your devices."),
    ("Guest network", "A separate Wi-Fi network for visitors, kept apart from your main devices."),
    ("IoT", "Short for \u201cInternet of Things\u201d \u2014 smart-home gadgets like plugs, cameras, and lightbulbs."),
    ("Bandwidth", "How much data your connection can move at once \u2014 think of it as the width of a pipe."),
]
rows = ''.join(
    '<div class="setting-row"' + (' style="margin-top:0;align-items:flex-start;"' if i == 0 else ' style="align-items:flex-start;"') +
    '><div class="sr-main"><strong>' + term + '</strong><span>' + defn + '</span></div></div>'
    for i, (term, defn) in enumerate(terms)
)

screens['glossary'] = (
    '<div class="page-crumb" data-goto="help"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>Back to Help</div>'
    '<div class="wizard-desk"><div class="wizard-card" style="max-width:600px;">'
    '<h1 class="scr-title">Networking glossary</h1>'
    '<p class="scr-sub">Plain-language explanations for terms you might see in the app.</p>'
    + rows +
    '</div></div>'
)

old_suffix = '11.5px;color:var(--muted);">Scan to join instantly</span>\n              </div>\n            </div>\n          </div></div>'
new_suffix = (
    '11.5px;color:var(--muted);">Scan to join instantly</span>\n              </div>\n            </div>\n          </div>'
    '<div class="nav-card mt-24" data-goto="glossary" style="max-width:640px;"><div class="sr-main"><strong>Networking glossary</strong><span>Plain-language definitions for common terms</span></div><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--muted-2)" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg></div>'
    '</div>'
)
assert old_suffix in screens['help'], "help screen suffix not found"
screens['help'] = screens['help'].replace(old_suffix, new_suffix)

content = content[:m.start(1)] + json.dumps(screens) + content[m.end(1):]

m2 = re.search(r'const screenMeta = (\{.*?\});\r?\n', content)
screenMeta = json.loads(m2.group(1))
screenMeta['glossary'] = 'app'
content = content[:m2.start(1)] + json.dumps(screenMeta) + content[m2.end(1):]

with open(path, 'w', encoding='utf-8') as f:
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
assert 'glossary' in screens and screens['glossary'].count('setting-row') == 8
assert 'data-goto=\"glossary\"' in screens['help']
print('OK')
"
```

- [ ] **Step 4: Commit** — `"feat: add standalone Networking glossary (US-16.1)"`.

---

### Task 3: `sadd-website.html` — comfort-level onboarding question

**Files:** Modify `sadd-website.html`

- [ ] **Step 1: Re-check current line number** — `grep -n "^  const screens = " sadd-website.html`

- [ ] **Step 2: Add `comfortlevel` screen, via Python round-trip**

```python
import json, re

path = r'c:\Users\hamzaz.SQU\Documents\projects\router\sadd-website.html'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))

screens['comfortlevel'] = (
    '<div class="wizard-desk"><div class="wizard-card" style="max-width:520px;text-align:center;">'
    '<h1 class="scr-title">How comfortable are you with home networking?</h1>'
    '<p class="scr-sub">This just helps us pace things \u2014 either way, you\'ll end up with a fully protected network.</p>'
    '<div class="nav-card mt-24" data-goto="changepassword" style="text-align:left;"><div class="sr-main"><strong>I\'m new to this</strong><span>Walk me through everything, step by step</span></div></div>'
    '<div class="nav-card" data-goto="changepassword" style="text-align:left;"><div class="sr-main"><strong>I know networking</strong><span>Keep it quick \u2014 I\'ve done this before</span></div></div>'
    '</div></div>'
)

content = content[:m.start(1)] + json.dumps(screens) + content[m.end(1):]

m2 = re.search(r'const screenMeta = (\{.*?\});\r?\n', content)
screenMeta = json.loads(m2.group(1))
screenMeta['comfortlevel'] = 'auth'
content = content[:m2.start(1)] + json.dumps(screenMeta) + content[m2.end(1):]

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done.")
```

- [ ] **Step 3: Retarget onboarding's forwardMap** — `welcome` should now advance to `comfortlevel` instead of `changepassword` (edit directly with `Edit`, this object is plain JS not JSON):

old_string:
```
    welcome:'changepassword', login:'dashboard', signup:'mfa', mfa:'dashboard',
```
new_string:
```
    welcome:'comfortlevel', login:'dashboard', signup:'mfa', mfa:'dashboard',
```

- [ ] **Step 4: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json, re
content = open('sadd-website.html', encoding='utf-8').read()
m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))
assert 'comfortlevel' in screens
m2 = re.search(r'const screenMeta = (\{.*?\});\r?\n', content)
meta = json.loads(m2.group(1))
assert meta.get('comfortlevel') == 'auth'
print('OK')
"
grep -c "welcome:'comfortlevel'" sadd-website.html
```
Expected: `OK`, then `1`.

- [ ] **Step 5: Commit** — `"feat: add comfort-level onboarding question (US-16.2)"`.

---

### Task 4: `sadd-mobile-app.html` — comfort-level onboarding question

**Files:** Modify `sadd-mobile-app.html`

- [ ] **Step 1: Verify current state** — `grep -c "comfortlevel" sadd-mobile-app.html` → expect `0`.

- [ ] **Step 2: Insert the `comfortlevel` screen and retarget `scanfound`/`btfound`**

Use `Edit` with old_string (the exact boundary tail this file's screens object always closes with):
```
  };

  const forwardMap = {
    scanning:'scanfound', scanfound:'admin',
    btsearching:'btfound', btfound:'admin',
    admin:'wifi', wifi:'success', success:'devices'
  };
```
new_string:
```
    comfortlevel: `
      <h1 class="scr-title">How comfortable are you with home networking?</h1>
      <p class="scr-sub">This just helps us pace things &mdash; either way, you'll end up with a fully protected network.</p>
      <div class="method-card" data-goto="admin">
        <strong>I'm new to this</strong>
        <span>Walk me through everything, step by step</span>
      </div>
      <div class="method-card" data-goto="admin">
        <strong>I know networking</strong>
        <span>Keep it quick &mdash; I've done this before</span>
      </div>
    `,

  };

  const forwardMap = {
    scanning:'scanfound', scanfound:'comfortlevel',
    btsearching:'btfound', btfound:'comfortlevel',
    admin:'wifi', wifi:'success', success:'devices'
  };
```

Note: this `comfortlevel` screen intentionally omits the `.mc-icon` div used by `connect`'s method-cards — `.method-card` doesn't require an icon child, and these two options aren't icon-representable the way camera/Bluetooth are. Verify visually in Step 4 that the card still renders acceptably without one.

- [ ] **Step 3: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && node -e "
const fs = require('fs');
const html = fs.readFileSync('sadd-mobile-app.html', 'utf-8');
const match = html.match(/<script>([\s\S]*)<\/script>/);
try { new Function(match[1]); console.log('Script parses as valid JS: true'); }
catch (e) { console.log('SYNTAX ERROR:', e.message); }
"
grep -c "    comfortlevel: \`" sadd-mobile-app.html
grep -c "scanfound:'comfortlevel'" sadd-mobile-app.html
grep -c "btfound:'comfortlevel'" sadd-mobile-app.html
```
Expected: `Script parses as valid JS: true`, then `1`, `1`, `1`.

- [ ] **Step 4: Commit** — `"feat: add comfort-level onboarding question (US-16.2)"`.

---

### Task 5: Final verification and push

**Files:** none (verification only)

- [ ] **Step 1: Full round-trip check on `sadd-website.html`**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json, re
content = open('sadd-website.html', encoding='utf-8').read()
m = re.search(r'const screens = (\{.*?\});\r?\n', content)
screens = json.loads(m.group(1))
print('screens keys:', len(screens))
for k in ('blockdetail','glossary','comfortlevel'):
    assert k in screens, k + ' missing'
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

- [ ] **Step 3: Manual browser check** — in `sadd-website.html`: start onboarding from `welcome`, confirm the new comfort-level screen appears and either card advances to the password-change step; go to Security, tap a blocked-item row, confirm it opens the block-detail screen with a working back-crumb; go to Help, tap "Networking glossary," confirm all 8 terms render and the back-crumb returns to Help. In `sadd-mobile-app.html`: start onboarding via either Scan Barcode or Bluetooth, confirm the comfort-level screen appears after the found/connected step and either card advances to the admin/password screen.

- [ ] **Step 4: Push**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git push origin main
```
