# Sadd Website Bug Fixes (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 4 bugs found in the tester/reviewer pass on `sadd-website.html` — dead onboarding back-navigation, 3 unreachable Advanced screens on mobile, an orphaned unreferenced screen, and a misleading UI affordance.

**Architecture:** `sadd-website.html` is a single-file JS-driven SPA. A `<script>` block (starting at the literal line containing `const screens = {...}`) holds three big JS object literals as one-line-each JSON-compatible strings — `screens` (28 keys, each value is that screen's inner HTML as a string), `screenMeta` (screen key → `'auth'`/`'app'`), `pageTitles` (screen key → display title) — followed by multi-line, normally-formatted navigation logic (`forwardMap`, `backMap`, `textLinkMap`, and a single delegated click handler on `document.body`). Because `screens`/`screenMeta`/`pageTitles` are each single enormous lines, edits to their *content* go through a small Python script (`json.loads` the object, mutate the Python dict, `json.dumps` it back with `ensure_ascii=True` to match the existing escaping style, splice the line back into the file) rather than the file-editing tool directly. Edits to the multi-line navigation logic and `<style>` block use direct text edits, since those parts are normal multi-line source.

**Tech Stack:** Plain HTML/CSS/JS (no build step, no framework, no test runner). Verification is via a small Python `json.loads` sanity check (the embedded object must still parse) plus `grep`-based assertions, since there is no test suite for this static prototype.

---

## Before you start

All edits target one file: `c:\Users\hamzaz.SQU\Documents\projects\router\sadd-website.html`. Every task below that touches the `screens`/`screenMeta` objects uses this same load/mutate/save pattern — read it once so the later tasks make sense:

```python
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

# --- for the `screens` object (currently line 586, 0-indexed lines[585]) ---
line = lines[585]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

# ... mutate obj here ...

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[585] = prefix + new_obj_str + suffix

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
```

The `screenMeta` object is on line 587 (`lines[586]`), same pattern, prefix text `'const screenMeta = '`. If a prior task in this plan changes the file's total line count (it won't — every task here only mutates content *within* existing lines 586/587, never adds/removes lines before them), re-verify the line index with `grep -n "const screens = " sadd-website.html` before proceeding.

---

### Task 1: Add back-navigation to the onboarding wizard

**Files:**
- Modify: `sadd-website.html` (the `screens` object, keys `signup`, `mfa`, `setup`, `discover`)

- [ ] **Step 1: Verify the bug**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
for k in ['signup','mfa','setup','discover']:
    print(k, '-> has page-crumb:', 'page-crumb' in obj[k])
"
```
Expected: all four print `False`.

- [ ] **Step 2: Insert a `.page-crumb` back-link into each of the 4 screens**

The `.page-crumb` markup/CSS already exists and works on other screens (e.g. `guest`); this step reuses the exact same pattern with each screen's correct `data-goto` target (matching the existing `backMap` values, which are correct but currently unused/unreachable — see Task 5).

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

CRUMB = '<div class=\"page-crumb\" data-goto=\"{target}\"><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"m15 18-6-6 6-6\"/></svg>Back</div>'

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

line = lines[585]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

# signup: split layout, crumb goes inside .split-form > .inner, before the h1
anchor = '<div class=\"split-form\"><div class=\"inner\">\n            <h1 class=\"scr-title\">Create your account</h1>'
assert obj['signup'].count(anchor) == 1, 'signup anchor not found or not unique'
obj['signup'] = obj['signup'].replace(
    anchor,
    '<div class=\"split-form\"><div class=\"inner\">\n            ' + CRUMB.format(target='welcome') + '\n            <h1 class=\"scr-title\">Create your account</h1>'
)

# mfa / setup: wizard-desk > wizard-card (no inline style on wizard-card)
for key, target in [('mfa', 'signup'), ('setup', 'mfa')]:
    anchor = '<div class=\"wizard-desk\"><div class=\"wizard-card\">'
    assert obj[key].count(anchor) == 1, key + ' anchor not found or not unique'
    obj[key] = obj[key].replace(anchor, anchor + '\n          ' + CRUMB.format(target=target), 1)

# discover: wizard-card has an inline max-width style
anchor = '<div class=\"wizard-desk\"><div class=\"wizard-card\" style=\"max-width:680px;\">'
assert obj['discover'].count(anchor) == 1, 'discover anchor not found or not unique'
obj['discover'] = obj['discover'].replace(anchor, anchor + '\n          ' + CRUMB.format(target='setup'), 1)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[585] = prefix + new_obj_str + suffix

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected output: `done` (an `AssertionError` means an anchor string didn't match — stop and re-extract the current text for that screen with the same `json.loads` technique before retrying).

- [ ] **Step 3: Verify the fix**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
for k, target in [('signup','welcome'),('mfa','signup'),('setup','mfa'),('discover','setup')]:
    ok = ('data-goto=\"' + target + '\"') in obj[k] and 'page-crumb' in obj[k]
    print(k, '-> crumb to', target, ':', ok)
"
```
Expected: `JSON valid, keys: 28` and all four `True`.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git add sadd-website.html && git commit -m "fix: add back-navigation to onboarding wizard screens"
```

---

### Task 2: Make all 7 Advanced Mode screens reachable on mobile

**Files:**
- Modify: `sadd-website.html` (the `screens` object, key `advhub`)

**Context:** `advhub`'s card grid currently links to only 4 of 7 Advanced sub-screens (Network & VLANs, Firewall & Ports, Traffic & QoS, Multi-WAN & Failover). The other 3 (`advvpn`, `advlogs`, `advapi`) are only reachable via the desktop sidebar, which is `display:none` below 860px. Row navigation on `.dcard` elements works by matching the row's `<strong>` text against the existing `textLinkMap` (see the delegated click handler, `~line 729`) — `textLinkMap` already has correct entries for `'VPN Server (OpenVPN)'`, `'Diagnostics & Logs'`, and `'Developer & API Access'`, so no JS changes are needed — just add 3 more `.dcard` elements with matching label text.

- [ ] **Step 1: Verify the bug**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('dcard count in advhub:', obj['advhub'].count('class=\"dcard\"'))
"
```
Expected: `dcard count in advhub: 4`.

- [ ] **Step 2: Add the 3 missing cards**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

line = lines[585]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

anchor = '<div class=\"dcard-sub\">no cellular backup configured</div></div>\n          </div></div>'
assert obj['advhub'].count(anchor) == 1, 'advhub anchor not found or not unique'

new_cards = (
    '<div class=\"dcard\"><div class=\"dcard-head\"><strong>VPN Server (OpenVPN)</strong></div><div class=\"dcard-big\">2</div><div class=\"dcard-sub\">client certificates issued</div></div>'
    '<div class=\"dcard\"><div class=\"dcard-head\"><strong>Diagnostics &amp; Logs</strong></div><div class=\"dcard-big\">Live</div><div class=\"dcard-sub\">throughput &amp; activity log</div></div>'
    '<div class=\"dcard\"><div class=\"dcard-head\"><strong>Developer &amp; API Access</strong></div><div class=\"dcard-big\">Off</div><div class=\"dcard-sub\">no API keys issued</div></div>'
)

obj['advhub'] = obj['advhub'].replace(
    anchor,
    '<div class=\"dcard-sub\">no cellular backup configured</div></div>' + new_cards + '\n          </div></div>'
)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[585] = prefix + new_obj_str + suffix

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected output: `done`.

- [ ] **Step 3: Verify the fix**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('dcard count in advhub:', obj['advhub'].count('class=\"dcard\"'))
for label in ['VPN Server (OpenVPN)', 'Diagnostics &amp; Logs', 'Developer &amp; API Access']:
    print(label, '->', label in obj['advhub'])
"
```
Expected: `JSON valid, keys: 28`, `dcard count in advhub: 7`, all three labels `True`.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git add sadd-website.html && git commit -m "fix: add VPN Server, Diagnostics, and Developer API cards to Advanced Hub grid"
```

---

### Task 3: Remove the orphaned `connectrouter` screen

**Files:**
- Modify: `sadd-website.html` (the `screens` object and the `screenMeta` object)

**Context:** `connectrouter` is unreferenced by any `data-goto`, `forwardMap`, `backMap`, or `textLinkMap` entry, and is absent from `docs/sadd-sitemap.html`'s documented onboarding flow. It is not present in `pageTitles` (already confirmed absent — no change needed there).

- [ ] **Step 1: Verify the bug**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -c '"connectrouter"' sadd-website.html
```
Expected: `2` (one match inside the `screens` line, one inside the `screenMeta` line).

- [ ] **Step 2: Delete the key from both objects**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

for line_idx, var_name in [(585, 'const screens = '), (586, 'const screenMeta = ')]:
    line = lines[line_idx]
    prefix = line[:line.index(var_name) + len(var_name)]
    start = line.index(var_name) + len(var_name)
    end = line.rstrip().rfind('};')
    suffix = line[end+1:]
    obj = json.loads(line[start:end+1])
    assert 'connectrouter' in obj, var_name + ' missing connectrouter key'
    del obj['connectrouter']
    new_obj_str = json.dumps(obj, ensure_ascii=True)
    lines[line_idx] = prefix + new_obj_str + suffix

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected output: `done`.

- [ ] **Step 3: Verify the fix**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -c '"connectrouter"' sadd-website.html
python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('screens keys:', len(obj))
line2 = lines[586]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
meta = json.loads(line2[start2:end2+1])
print('screenMeta keys:', len(meta))
"
```
Expected: `0` from grep, `screens keys: 27`, `screenMeta keys: 27`.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git add sadd-website.html && git commit -m "fix: remove orphaned connectrouter screen"
```

---

### Task 4: Remove the misleading Bedtime chevron

**Files:**
- Modify: `sadd-website.html` (the `screens` object, key `parental`)

**Context:** The Bedtime `.setting-row` in the `parental` screen's detail pane ends with a trailing chevron `<svg>` that implies a drill-down destination, but no `data-goto`/click behavior exists for it beyond the row itself (which has no `textLinkMap` entry either — it's purely decorative and misleading).

- [ ] **Step 1: Verify the bug**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
target = '<strong>Bedtime</strong><span>9:00 PM\u20137:00 AM</span></div><svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg>'
print('chevron present:', target in obj['parental'])
"
```
Expected: `chevron present: True`.

- [ ] **Step 2: Remove the chevron**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

line = lines[585]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

old = '<strong>Bedtime</strong><span>9:00 PM\u20137:00 AM</span></div><svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg>'
new = '<strong>Bedtime</strong><span>9:00 PM\u20137:00 AM</span></div>'
assert obj['parental'].count(old) == 1, 'bedtime anchor not found or not unique'
obj['parental'] = obj['parental'].replace(old, new)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[585] = prefix + new_obj_str + suffix

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected output: `done`.

- [ ] **Step 3: Verify the fix**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
target = '<strong>Bedtime</strong><span>9:00 PM\u20137:00 AM</span></div><svg'
print('chevron still present:', target in obj['parental'])
print('Bedtime label still present:', '<strong>Bedtime</strong>' in obj['parental'])
"
```
Expected: `JSON valid, keys: 27`, `chevron still present: False`, `Bedtime label still present: True`.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git add sadd-website.html && git commit -m "fix: remove non-functional chevron from Bedtime row"
```

---

### Task 5: Remove dead `.back-btn` / `backMap` code

**Files:**
- Modify: `sadd-website.html` (CSS around line 120 and 458, JS around lines 627–633 and 720–722 — line numbers approximate; use the Grep tool to relocate exact lines before editing, since earlier tasks in this plan do not change line counts but this task should still confirm)

**Context:** With Task 1 done, the onboarding screens now use `.page-crumb` (like every other screen with back-navigation), so `.back-btn` and `backMap` — which were never actually placed as clickable elements in any screen's HTML — are now provably 100% dead: `backMap`'s only consumer is the click handler's `.back-btn` branch, and no `.back-btn` element exists anywhere in `screens` (verify this in Step 1).

- [ ] **Step 1: Verify no `.back-btn` elements exist and confirm `backMap` has no other consumer**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
found = [k for k, v in obj.items() if 'back-btn' in v]
print('screens with back-btn element:', found)
"
grep -n "backMap" sadd-website.html
```
Expected: `screens with back-btn element: []`, and the `grep` shows exactly 2 lines — the `const backMap = {...}` definition and the `goTo(backMap[state.screen])` usage inside the `.back-btn` handler branch (no other references).

- [ ] **Step 2: Remove the CSS rule**

Use the Edit tool on `sadd-website.html`:
- old_string: `  .back-btn{width:34px;height:34px;border-radius:9px;border:1.5px solid var(--border);background:#fff;display:flex;align-items:center;justify-content:center;cursor:pointer;color:var(--text);}\n`
- new_string: `` (empty — delete the line)

- [ ] **Step 3: Remove the now-inaccurate comment**

Use the Edit tool on `sadd-website.html`:
- old_string: `/* keep back-btn usable inside the shell for narrow task screens (points back via JS backMap) */\n`
- new_string: `` (empty — delete the line)

- [ ] **Step 4: Remove the `backMap` object definition**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
  const backMap = {
    signup:'welcome', mfa:'signup', setup:'mfa', discover:'setup',
    guest:'settings', help:'dashboard', settings:'dashboard',
    advhub:'settings', advnetwork:'advhub', advfirewall:'advhub', advqos:'advhub',
    advwan:'advhub', advlogs:'advhub', advapi:'advhub', advvpn:'advhub',
    adblock:'security', devcontrols:'parental', connectdevice:'devices', laptopvpn:'vpn'
  };
```
- new_string: `` (empty — delete the whole block)

- [ ] **Step 5: Remove the `.back-btn` handler branch**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    // back arrow
    const back = e.target.closest('.back-btn');
    if(back){ goTo(backMap[state.screen]); return; }

```
- new_string: `` (empty — delete the whole block, including its comment)

- [ ] **Step 6: Verify the fix**

Run:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -c "back-btn\|backMap" sadd-website.html
python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[585]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON still valid, keys:', len(obj))
"
```
Expected: `0` from the grep count, `JSON still valid, keys: 27`.

- [ ] **Step 7: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git add sadd-website.html && git commit -m "chore: remove dead back-btn/backMap code superseded by page-crumb"
```

---

### Task 6: Manual click-through verification

**Files:** none (verification only)

- [ ] **Step 1: Open the file in a browser**

Open `c:\Users\hamzaz.SQU\Documents\projects\router\sadd-website.html` directly in a browser (double-click, or `start sadd-website.html` from the project root on Windows).

- [ ] **Step 2: Walk the onboarding flow**

Click through `Welcome → Create account → Verify identity → Name your Wi-Fi → Find devices`. At each step, click the new "Back" crumb and confirm it lands on the correct previous screen, then click forward again to continue. Confirm `connectrouter`'s old content ("Connect to your router" / temporary `Sadd-Setup` Wi-Fi) no longer appears anywhere in the flow.

- [ ] **Step 3: Check Advanced Hub on a narrow viewport**

Resize the browser window below ~860px wide (or use browser dev tools' device toolbar). From Settings, open "Show advanced settings" and confirm all 7 cards (Network & VLANs, Firewall & Ports, Traffic & QoS, Multi-WAN & Failover, VPN Server (OpenVPN), Diagnostics & Logs, Developer & API Access) are visible and each navigates to its correct screen.

- [ ] **Step 4: Check the Parental Controls screen**

Navigate to Parental Controls → select a child profile → confirm the Bedtime row no longer shows a chevron.

- [ ] **Step 5: Push to GitHub**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git push origin main
```
