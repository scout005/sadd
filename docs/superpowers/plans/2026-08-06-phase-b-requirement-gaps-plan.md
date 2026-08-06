# Phase B Requirement Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 5 requirement gaps found by review against the SRS/backlog: MFA default method, device Block action + auto-quarantine VLAN, remote-access scope split, manual update approval screen, and an offline "can't reach your router" state.

**Architecture:** Same single-file `sadd-website.html` SPA as Phase A. `screens`/`screenMeta`/`pageTitles` are single-line JS object literals edited via the `json.loads`/`json.dumps` round-trip technique; `textLinkMap`/CSS/`render()`/the click handler are normal multi-line source edited via the Edit tool. One new screen (`advupdates`) is added; everything else modifies existing screens.

**Tech Stack:** Plain HTML/CSS/JS, no build step, no test runner. Verification is Python `json.loads` sanity checks plus `grep`-based assertions, same as Phase A.

---

## Before you start

**Line numbers move.** As of the start of this plan: `const screens = ` is on line 584, `const screenMeta = ` on line 585, `const pageTitles = ` on line 586 (all 1-indexed; subtract 1 for Python's 0-indexed `lines[]`). Every task below **must** re-confirm with:

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = \|^  const screenMeta = \|^  const pageTitles = " sadd-website.html | cut -c1-40
```
before running any script, and adjust the line index used if it has drifted from 584/585/586.

Standard mutation pattern for `screens` (same for `screenMeta`/`pageTitles`, just change the variable name and line index):

```python
import json
path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]  # confirm this index first!
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])
# ... mutate obj ...
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
```

All git commits in this plan use the same identity convention as Phase A (no global git identity is configured on this machine, and running `git config` is off-limits):
```bash
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git ...
```
You have explicit user consent to commit and push directly to `main`.

---

### Task 1: MFA default method (SMS/push, not authenticator app)

**Files:** Modify `sadd-website.html` (`screens` object, key `mfa`)

- [ ] **Step 1: Verify current default**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('app is active:', '<button class=\"active\" data-method=\"app\">' in obj['mfa'])
print('sms is active:', '<button class=\"active\" data-method=\"sms\">' in obj['mfa'])
"
```
Expected: `app is active: True`, `sms is active: False` (there's no `active` class on the sms button yet).

- [ ] **Step 2: Swap the default**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['mfa']
assert s.count('<button class=\"active\" data-method=\"app\">Authenticator app</button>') == 1
assert s.count('<button data-method=\"sms\">Text message</button>') == 1
s = s.replace('<button class=\"active\" data-method=\"app\">Authenticator app</button>', '<button data-method=\"app\">Authenticator app</button>')
s = s.replace('<button data-method=\"sms\">Text message</button>', '<button class=\"active\" data-method=\"sms\">Text message</button>')

assert s.count('<div data-panel=\"app\" data-group=\"d1\" class=\"center\">') == 1
assert s.count('<div data-panel=\"sms\" data-group=\"d1\" class=\"center\" style=\"display:none;\">') == 1
s = s.replace('<div data-panel=\"app\" data-group=\"d1\" class=\"center\">', '<div data-panel=\"app\" data-group=\"d1\" class=\"center\" style=\"display:none;\">')
s = s.replace('<div data-panel=\"sms\" data-group=\"d1\" class=\"center\" style=\"display:none;\">', '<div data-panel=\"sms\" data-group=\"d1\" class=\"center\">')
obj['mfa'] = s

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected: `done`.

- [ ] **Step 3: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
s = obj['mfa']
print('sms active:', '<button class=\"active\" data-method=\"sms\">' in s)
print('app not active:', '<button data-method=\"app\">' in s and '<button class=\"active\" data-method=\"app\">' not in s)
print('app panel hidden:', 'data-panel=\"app\" data-group=\"d1\" class=\"center\" style=\"display:none;\"' in s)
print('sms panel visible:', 'data-panel=\"sms\" data-group=\"d1\" class=\"center\">' in s and 'data-panel=\"sms\" data-group=\"d1\" class=\"center\" style=\"display:none;\"' not in s)
"
```
Expected: all `True`, `keys: 27`.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "fix: default MFA to SMS/push per spec, authenticator app as alternative"
```

---

### Task 2: Device Block action + auto-quarantine VLAN

**Files:** Modify `sadd-website.html` (`screens` object, keys `devices`, `advnetwork`, `advhub`; CSS in `<style>` block)

**Context:** This screen's architecture shows exactly one static detail pane per screen (no dynamic per-row detail switching exists anywhere in the file — every `.split-desk-list` screen shows one fixed device's detail regardless of which list row is visually `.active`). To demonstrate the quarantine/Block UX at the fidelity level the rest of the file uses, this task makes the "Unknown device" row the active one (instead of "Emma's iPhone") and shows its detail pane content — this is a deliberate choice to match existing patterns, not a compromise; every other screen in the file works the same way (one representative static state, not a live multi-state demo).

- [ ] **Step 1: Verify current state**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('Emma is currently the active row:', '<div class=\"list-item active\">' in obj['devices'])
print('Unknown device present:', '<strong>Unknown device</strong>' in obj['devices'])
print('advnetwork VLAN count:', obj['advnetwork'].count('class=\"switch on\" style=\"width:38px;height:22px;\"'))
print('advhub networks count text:', '<div class=\"dcard-big\">4</div><div class=\"dcard-sub\">networks configured</div>' in obj['advhub'])
"
```
Expected: `Emma is currently the active row: True`, `Unknown device present: True`, `advnetwork VLAN count: 4`, `advhub networks count text: True`.

- [ ] **Step 2: Add CSS for the flagged row, badge, and dim quick-action (used by this task and Task 5)**

Locate the `.list-item{` rule:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  \.list-item{" sadd-website.html
```

Use the Edit tool on `sadd-website.html` to add new rules immediately after that line:

- old_string:
```
  .list-item{display:flex;align-items:center;gap:12px;background:#fff;border:1.5px solid var(--border);border-radius:13px;padding:12px 14px;margin-bottom:9px;cursor:pointer;}
```
- new_string:
```
  .list-item{display:flex;align-items:center;gap:12px;background:#fff;border:1.5px solid var(--border);border-radius:13px;padding:12px 14px;margin-bottom:9px;cursor:pointer;}
  .list-item.flagged{background:var(--warning-tint);border-color:#FDE68A;}
  .badge-new{display:inline-flex;align-items:center;font-size:9.5px;font-weight:800;padding:2px 7px;border-radius:999px;background:var(--warning);color:#fff;text-transform:uppercase;letter-spacing:.03em;margin-left:6px;}
```

- [ ] **Step 3: Update the devices list — flag the Unknown device row, make it active instead of Emma's**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['devices']

old_emma = '<div class=\"list-item active\"><div class=\"li-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"7\" y=\"2\" width=\"10\" height=\"20\" rx=\"2\"/></svg></div><div class=\"li-main\"><strong>Emma\'s iPhone</strong></div><span class=\"status-pill online\">Online</span></div>'
new_emma = old_emma.replace('list-item active', 'list-item')
assert s.count(old_emma) == 1, 'emma anchor not found'
s = s.replace(old_emma, new_emma)

old_unknown = '<div class=\"list-item\"><div class=\"li-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"2\" y=\"6\" width=\"20\" height=\"12\" rx=\"2\"/></svg></div><div class=\"li-main\"><strong>Unknown device</strong></div><span class=\"status-pill online\">Online</span></div>'
new_unknown = '<div class=\"list-item flagged active\"><div class=\"li-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"2\" y=\"6\" width=\"20\" height=\"12\" rx=\"2\"/></svg></div><div class=\"li-main\"><strong>Unknown device<span class=\"badge-new\">New</span></strong></div><span class=\"status-pill online\">Online \u00b7 Quarantined</span></div>'
assert s.count(old_unknown) == 1, 'unknown anchor not found'
s = s.replace(old_unknown, new_unknown)

obj['devices'] = s
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 3')
"
```
Expected: `done step 3`.

- [ ] **Step 4: Replace the detail pane content with the Unknown device's quarantine actions**

The current detail pane (confirmed by direct inspection while writing this plan) is everything from `<div class="split-desk-detail">` to the end of the `devices` string — it is Emma's iPhone's Pause/Bedtime/Group/Forget pane, and per this task's Context note above, it gets fully replaced with the Unknown device's pane (list-selection state and detail content move together, matching this file's one-static-state-per-screen convention).

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['devices']

old_detail_and_tail = (
    '<div class=\"split-desk-detail\">\n'
    '            <div class=\"detail-header\"><div class=\"dh-icon\"><svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"7\" y=\"2\" width=\"10\" height=\"20\" rx=\"2\"/></svg></div><div><strong style=\"display:block;font-size:17px;\">Emma\'s iPhone</strong><span style=\"font-size:13px;color:var(--muted);\">Phone \u00b7 Connected 2 hrs ago \u00b7 Kids group</span></div></div>\n'
    '            <div class=\"sec-label\">Pause internet</div>\n'
    '            <div class=\"timer-row\" style=\"max-width:380px;\"><div class=\"timer-chip\">15 min</div><div class=\"timer-chip active\">1 hr</div><div class=\"timer-chip\">Until tomorrow</div></div>\n'
    '            <div class=\"grid-2 mt-24\" style=\"max-width:520px;\">\n'
    '              <div class=\"setting-row\"><div class=\"sr-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M12 7v5l3 2\"/></svg></div><div class=\"sr-main\"><strong>Bedtime</strong><span>9:00 PM\u20137:00 AM</span></div><div class=\"switch on\"></div></div>\n'
    '              <div class=\"setting-row\"><div class=\"sr-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2\"/><circle cx=\"9\" cy=\"7\" r=\"4\"/></svg></div><div class=\"sr-main\"><strong>Group</strong><span>Kids</span></div></div>\n'
    '            </div>\n'
    '            <button class=\"btn btn-danger-soft mt-24\" style=\"width:auto;padding:12px 22px;\">Forget this device</button>\n'
    '          </div>\n'
    '        </div>\n'
    '      </div>'
)
assert s.count(old_detail_and_tail) == 1, 'detail pane anchor not found or not unique -- re-inspect obj[\"devices\"] before proceeding'
assert s.endswith(old_detail_and_tail), 'anchor is not actually the tail of the string -- re-inspect before proceeding'

new_detail_and_tail = (
    '<div class=\"split-desk-detail\">'
    '<div class=\"detail-header\"><div class=\"dh-icon\"><svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"2\" y=\"6\" width=\"20\" height=\"12\" rx=\"2\"/></svg></div>'
    '<div><strong style=\"font-size:16px;\">Unknown device<span class=\"badge-new\" style=\"margin-left:8px;\">New</span></strong><div style=\"font-size:12px;color:var(--muted);margin-top:2px;\">Joined 4 min ago \u00b7 Currently in Quarantine</div></div></div>'
    '<div class=\"adv-warning\" style=\"margin-bottom:18px;\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 9v4M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z\"/></svg><div><strong>This device is isolated by default</strong><span>It can\u2019t reach your other devices until you assign it to a network or block it.</span></div></div>'
    '<div class=\"setting-row\"><div class=\"sr-main\"><strong>Move to\u2026</strong><span>Choose where this device belongs</span></div><select><option>Main Network</option><option>Kids</option><option>IoT / Smart Home</option><option>Guests</option></select></div>'
    '<button class=\"btn btn-danger-soft mt-24\" style=\"width:auto;padding:12px 22px;\">Block this device</button>'
    '</div>'
    '</div>'
)

s = s.replace(old_detail_and_tail, new_detail_and_tail)
obj['devices'] = s
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 4')
"
```
Expected: `done step 4`. If either `assert` fails, STOP — re-run the Step 1 inspection technique on `obj['devices']` to see the current exact content rather than forcing the replacement through with a modified anchor.

- [ ] **Step 5: Add the 5th VLAN row (Quarantine) to Network & VLANs**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['advnetwork']
anchor = '<button class=\"btn btn-secondary mt-24\" style=\"width:auto;padding:11px 22px;\">+ Create VLAN</button>'
assert s.count(anchor) == 1, 'create-vlan anchor not found'

quarantine_row = (
    '<div class=\"adv-row\"><div class=\"ar-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M12 8v4M12 16h.01\"/></svg></div>'
    '<div class=\"ar-main\"><strong>Quarantine</strong></div>'
    '<span class=\"mono-badge\" style=\"width:150px;text-align:center;\">192.168.5.0/24</span>'
    '<span style=\"width:90px;text-align:center;font-size:12.5px;\">1</span>'
    '<div class=\"switch on\" style=\"width:38px;height:22px;\"></div></div>\n        '
)

s = s.replace(anchor, quarantine_row + anchor)
obj['advnetwork'] = s
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 5')
"
```
Expected: `done step 5`.

- [ ] **Step 6: Update the Advanced Hub's network count from 4 to 5**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

old = '<div class=\"dcard-big\">4</div><div class=\"dcard-sub\">networks configured</div>'
new = '<div class=\"dcard-big\">5</div><div class=\"dcard-sub\">networks configured</div>'
assert obj['advhub'].count(old) == 1
obj['advhub'] = obj['advhub'].replace(old, new)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 6')
"
```
Expected: `done step 6`.

- [ ] **Step 7: Verify everything in this task**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('Unknown device row flagged+active:', 'list-item flagged active' in obj['devices'])
print('Unknown device badge in list:', 'Unknown device<span class=\"badge-new\">New</span>' in obj['devices'])
print('Emma no longer active:', '<div class=\"list-item active\">' not in obj['devices'])
print('Move to select present:', '<option>Main Network</option>' in obj['devices'] and '<option>Guests</option>' in obj['devices'])
print('Block button present:', 'Block this device' in obj['devices'])
print('Quarantine VLAN row present:', '<strong>Quarantine</strong>' in obj['advnetwork'] and '192.168.5.0/24' in obj['advnetwork'])
print('advhub shows 5 networks:', '<div class=\"dcard-big\">5</div><div class=\"dcard-sub\">networks configured</div>' in obj['advhub'])
"
grep -c "\.list-item\.flagged{" sadd-website.html
grep -c "\.badge-new{" sadd-website.html
```
Expected: `JSON valid, keys: 27`, all print `True`, both grep counts `1`.

- [ ] **Step 8: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: flag unknown devices, add Block + Move-to actions, auto-quarantine VLAN"
```

---

### Task 3: Remote-access scope split (management-only vs. full-LAN)

**Files:** Modify `sadd-website.html` (`screens` object, key `advvpn`)

**Context:** `advvpn` already has a "Redirect all client traffic" toggle (off by default) that is functionally the same underlying setting as the spec's "full-LAN access" scope — relabel and extend it rather than adding a confusing duplicate toggle next to it.

- [ ] **Step 1: Verify current state**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('has Redirect row:', '<strong>Redirect all client traffic</strong>' in obj['advvpn'])
print('has adv-warning already:', obj['advvpn'].count('adv-warning'))
"
```
Expected: `has Redirect row: True`, `has adv-warning already: 0`.

- [ ] **Step 2: Relabel the row and add the warning banner**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['advvpn']
old = '<div class=\"setting-row\"><div class=\"sr-main\"><strong>Redirect all client traffic</strong><span>Off by default</span></div><div class=\"switch\"></div></div>'
assert s.count(old) == 1, 'redirect row not found'
new = (
    '<div class=\"setting-row\"><div class=\"sr-main\"><strong>Full home network access</strong><span>Off by default \u2014 remote sessions reach router settings only</span></div><div class=\"switch\"></div></div>'
    '<div class=\"adv-warning mt-24\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 9v4M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z\"/></svg><div><strong>This expands what remote sessions can reach</strong><span>Turning this on lets remote connections reach every device on your network, not just router settings. Only enable it if you understand the risk.</span></div></div>'
)
s = s.replace(old, new)
obj['advvpn'] = s
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected: `done`.

- [ ] **Step 3: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
s = obj['advvpn']
print('relabeled:', '<strong>Full home network access</strong>' in s)
print('old label gone:', '<strong>Redirect all client traffic</strong>' not in s)
print('warning added:', 'This expands what remote sessions can reach' in s)
"
```
Expected: `JSON valid, keys: 27`, all `True`.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: label full-LAN remote access scope and add risk warning"
```

---

### Task 4: Firmware Updates screen (manual approval + history)

**Files:** Modify `sadd-website.html` (`screens`, `screenMeta`, `pageTitles` objects; `textLinkMap` in `<script>`; `advhub` and `settings` screens)

- [ ] **Step 1: Add the new `advupdates` screen and its metadata**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

# screens (line index 583)
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

obj['advupdates'] = (
    '<div class=\"page-crumb\" data-goto=\"advhub\"><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"m15 18-6-6 6-6\"/></svg>Back to Advanced Settings</div>'
    '<div class=\"wizard-desk\"><div class=\"wizard-card\" style=\"max-width:680px;\">'
    '<h1 class=\"scr-title\">Firmware Updates</h1>'
    '<p class=\"scr-sub\">Current version <strong>v4.2.1</strong> \u00b7 last checked 2 days ago</p>'
    '<div class=\"setting-row\"><div class=\"sr-main\"><strong>Update automatically</strong><span>Installs during a low-usage window, no action needed</span></div><div class=\"switch on\"></div></div>'
    '<div class=\"sec-label mt-24\">Update history</div>'
    '<div class=\"mini-log\">'
    '<div class=\"mini-log-row\"><strong>v4.2.1</strong><span>Aug 3 \u00b7 Security patch, minor fixes</span></div>'
    '<div class=\"mini-log-row\"><strong>v4.2.0</strong><span>Jul 18 \u00b7 Added guest network time limits</span></div>'
    '<div class=\"mini-log-row\"><strong>v4.1.6</strong><span>Jun 30 \u00b7 Stability improvements</span></div>'
    '</div>'
    '<div class=\"tip-box mt-24\"><svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M12 8v4M12 16h.01\"/></svg>Every update keeps the previous version ready to restore \u2014 if an update fails to start properly, your router automatically rolls back on its own.</div>'
    '</div></div>'
)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix

# screenMeta (line index 584)
line2 = lines[584]
prefix2 = line2[:line2.index('const screenMeta = ') + len('const screenMeta = ')]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
suffix2 = line2[end2+1:]
meta = json.loads(line2[start2:end2+1])
meta['advupdates'] = 'app'
lines[584] = prefix2 + json.dumps(meta, ensure_ascii=True) + suffix2

# pageTitles (line index 585)
line3 = lines[585]
prefix3 = line3[:line3.index('const pageTitles = ') + len('const pageTitles = ')]
start3 = line3.index('const pageTitles = ') + len('const pageTitles = ')
end3 = line3.rstrip().rfind('};')
suffix3 = line3[end3+1:]
titles = json.loads(line3[start3:end3+1])
titles['advupdates'] = 'Firmware Updates'
lines[585] = prefix3 + json.dumps(titles, ensure_ascii=True) + suffix3

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 1')
"
```
Expected: `done step 1`. (If `screenMeta`/`pageTitles` aren't actually on lines 585/586 — i.e. `lines[584]`/`lines[585]` — re-run the line-location grep from "Before you start" first and adjust.)

- [ ] **Step 2: Add the Advanced Hub card and re-wire the Settings row**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

# advhub: add 8th card
anchor = '<div class=\"dcard\"><div class=\"dcard-head\"><strong>Developer &amp; API Access</strong></div><div class=\"dcard-big\">1</div><div class=\"dcard-sub\">API key active</div></div>'
assert obj['advhub'].count(anchor) == 1
new_card = '<div class=\"dcard\"><div class=\"dcard-head\"><strong>Firmware Updates</strong></div><div class=\"dcard-big\">v4.2.1</div><div class=\"dcard-sub\">up to date</div></div>'
obj['advhub'] = obj['advhub'].replace(anchor, anchor + new_card)

# settings: re-add chevron to Update router row
old_row = '<div class=\"sr-main\"><strong>Update router</strong><span>Up to date</span></div></div>'
assert obj['settings'].count(old_row) == 1
new_row = '<div class=\"sr-main\"><strong>Update router</strong><span>Up to date</span></div><svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div>'
obj['settings'] = obj['settings'].replace(old_row, new_row)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 2')
"
```
Expected: `done step 2`.

- [ ] **Step 3: Add `textLinkMap` entries**

Locate the current `textLinkMap`:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "const textLinkMap" sadd-website.html
```

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    'Diagnostics & Logs':'advlogs','Developer & API Access':'advapi',
```
- new_string:
```
    'Diagnostics & Logs':'advlogs','Developer & API Access':'advapi',
    'Firmware Updates':'advupdates','Update router':'advupdates',
```

(If the surrounding lines differ from this exact text by the time you run this — e.g. formatting drift from earlier edits — locate the `textLinkMap` object with the grep above, read its current exact content, and add the two new entries following the same `'Label':'key'` comma-separated style already used, placed anywhere inside the object.)

- [ ] **Step 4: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('advupdates present:', 'advupdates' in obj)
line2 = lines[584]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
meta = json.loads(line2[start2:end2+1])
print('screenMeta has advupdates:', meta.get('advupdates'))
line3 = lines[585]
start3 = line3.index('const pageTitles = ') + len('const pageTitles = ')
end3 = line3.rstrip().rfind('};')
titles = json.loads(line3[start3:end3+1])
print('pageTitles has advupdates:', titles.get('advupdates'))
print('advhub has Firmware Updates card:', '<strong>Firmware Updates</strong>' in obj['advhub'])
print('settings Update router has chevron:', 'Update router</strong><span>Up to date</span></div><svg' in obj['settings'])
"
grep -c "'Firmware Updates':'advupdates'" sadd-website.html
grep -c "'Update router':'advupdates'" sadd-website.html
```
Expected: `keys: 28`, `advupdates present: True`, `screenMeta has advupdates: app`, `pageTitles has advupdates: Firmware Updates`, both other checks `True`, both grep counts `1`.

- [ ] **Step 5: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: add Firmware Updates screen with history and auto/manual toggle"
```

---

### Task 5: Offline "can't reach your router" dashboard state

**Files:** Modify `sadd-website.html` (`screens` object key `help`; new top-level JS constant `dashboardOffline`; `render()` function; click handler; CSS)

- [ ] **Step 1: Add CSS for the offline status card and dimmed quick-action**

Locate `.status-card{`:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  \.status-card{" sadd-website.html
```

Use the Edit tool on `sadd-website.html`:
- old_string:
```
  .status-card{background:var(--success-tint);border:1px solid #BBF7D0;border-radius:16px;padding:18px 20px;display:flex;align-items:center;gap:14px;margin-bottom:18px;}
```
- new_string:
```
  .status-card{background:var(--success-tint);border:1px solid #BBF7D0;border-radius:16px;padding:18px 20px;display:flex;align-items:center;gap:14px;margin-bottom:18px;}
  .status-card.offline{background:var(--bg);border:1.5px dashed var(--muted-2);}
  .status-card.offline .s-dot{background:var(--muted-2);}
  .qa-btn.dim{opacity:.4;cursor:default;}
```

- [ ] **Step 2: Add the `dashboardOffline` constant next to `screens`**

This is a new top-level `const`, built from the existing `dashboard` screen's content with only the status-card and quick-actions swapped. Locate the end of the `screens`/`screenMeta`/`pageTitles`/`state` block:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "const state = " sadd-website.html
```

Use the Edit tool on `sadd-website.html`:
- old_string:
```
  const state = { screen: 'welcome' };
```
- new_string:
```
  const state = { screen: 'welcome', offline: false };

  const dashboardOffline = '<div class=\"dash-main\"><h2>Good afternoon, Jenna</h2>\n            <p class=\"dash-date\">Wednesday, August 5</p>\n            <div class=\"status-card offline\">\n              <div class=\"s-dot\"><svg width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 8v4M12 16h.01\"/></svg></div>\n              <div><strong>Can\\u2019t reach your router</strong><span>Last seen 2 hours ago \\u00b7 Check it\\u2019s powered on</span></div>\n            </div>\n            <div class=\"sec-label\" style=\"margin-top:14px;\">Still available on this Wi-Fi</div>\n            <div class=\"quick-actions\" style=\"max-width:420px;margin-top:0;\">\n              <div class=\"qa-btn danger\">Pause All</div>\n              <div class=\"qa-btn\">Guest Wi-Fi</div>\n              <div class=\"qa-btn\">Restart</div>\n            </div>\n            <div class=\"sec-label\">Needs internet</div>\n            <div class=\"quick-actions\" style=\"max-width:140px;margin-top:0;\">\n              <div class=\"qa-btn dim\">Remote Access</div>\n            </div>\n            <div class=\"card-grid mt-24\">\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Devices</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">12</div><div class=\"dcard-sub\">1 device needs attention</div></div>\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Parental Controls</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">3</div><div class=\"dcard-sub\">devices have bedtime rules</div></div>\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Security</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">214</div><div class=\"dcard-sub\">threats blocked this month</div></div>\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Remote Access</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">Off</div><div class=\"dcard-sub\">unavailable while offline</div></div>\n            </div></div>';
```

**Important:** this `new_string`'s `dashboardOffline` value must stay text-identical to the live `dashboard` screen's structure (same `dcard` grid, same icons) except for the 3 documented differences (status-card, quick-actions split, Remote Access dcard's "Off"/"unavailable while offline" text instead of "On"/"2 family members connected" — this last change makes the always-visible dashboard grid consistent with the offline framing). Before writing this edit, re-confirm the live `dashboard` screen's exact current content with the Step-1-style inspection technique from earlier tasks, in case any earlier task in this plan altered it (none should have — `dashboard` isn't touched by Tasks 1-4 — but verify rather than assume).

- [ ] **Step 3: Update `render()` to use `dashboardOffline` when appropriate**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "document.getElementById('appContent').innerHTML" sadd-website.html
```

Use the Edit tool on `sadd-website.html`:
- old_string:
```
      document.getElementById('appContent').innerHTML = screens[state.screen] || '';
```
- new_string:
```
      const content = (state.screen === 'dashboard' && state.offline) ? dashboardOffline : screens[state.screen];
      document.getElementById('appContent').innerHTML = content || '';
```

- [ ] **Step 4: Add the "Simulate offline" link to Help & Fixes**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['help']
anchor = '<div class=\"grid-2 mt-24\" style=\"align-items:start;\">'
assert s.count(anchor) == 1
link = '<p style=\"font-size:11.5px;color:var(--muted-2);text-align:right;margin:0 0 4px;\"><a href=\"#\" data-toggle-offline style=\"color:inherit;\">Simulate offline mode &rarr;</a></p>'
s = s.replace(anchor, link + anchor)
obj['help'] = s

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[583] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 4')
"
```
Expected: `done step 4`.

- [ ] **Step 5: Wire up the `data-toggle-offline` click handler**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "any explicit data-goto link" sadd-website.html
```

Use the Edit tool on `sadd-website.html` (add a new branch immediately before the existing `data-goto` handling, so the offline-toggle link is checked first since it's more specific):
- old_string:
```
    // any explicit data-goto link (sidebar items, breadcrumbs, etc.)
    const gotoEl = e.target.closest('[data-goto]');
```
- new_string:
```
    // offline-mode preview toggle (Help & Fixes)
    const offlineToggle = e.target.closest('[data-toggle-offline]');
    if(offlineToggle){
      state.offline = !state.offline;
      goTo('dashboard');
      return;
    }

    // any explicit data-goto link (sidebar items, breadcrumbs, etc.)
    const gotoEl = e.target.closest('[data-goto]');
```

- [ ] **Step 6: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[583]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('help has offline link:', 'data-toggle-offline' in obj['help'])
"
grep -c "const dashboardOffline = " sadd-website.html
grep -c "data-toggle-offline" sadd-website.html
grep -c "state.offline" sadd-website.html
grep -c "offline: false" sadd-website.html
```
Expected: `JSON valid, keys: 28`, `help has offline link: True`, `dashboardOffline` grep `1`, `data-toggle-offline` grep `2` (one in the `help` screen markup, one in the click handler), `state.offline` grep `>=2`, `offline: false` grep `1`.

- [ ] **Step 7: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: add offline dashboard state with local-vs-cloud action grouping"
```

---

### Task 6: Manual click-through verification and push

**Files:** none (verification only)

- [ ] **Step 1: Open the file in a browser**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && start sadd-website.html
```

- [ ] **Step 2: Check MFA default**

Log in / start onboarding through to the "Verify it's you" screen. Confirm "Text message" is the active tab by default, showing the phone-number code entry, with "Authenticator app" as a clickable alternative tab.

- [ ] **Step 3: Check device quarantine**

Navigate to Devices. Confirm "Unknown device" shows an amber-tinted row with a "New" badge and is the currently-selected/active row. Confirm its detail pane shows the quarantine warning, a "Move to…" dropdown (Main Network / Kids / IoT / Smart Home / Guests), and a "Block this device" button. Navigate to Settings → Show advanced settings → Network & VLANs, confirm a 5th "Quarantine" row (192.168.5.0/24) appears. Confirm the Advanced Hub's "Network & VLANs" card now reads "5".

- [ ] **Step 4: Check remote-access scope**

Navigate to Settings → Show advanced settings → VPN Server (OpenVPN). Confirm the row previously labeled "Redirect all client traffic" now reads "Full home network access" with a warning banner beneath it.

- [ ] **Step 5: Check Firmware Updates**

From Advanced Hub, confirm an 8th card "Firmware Updates" appears and navigates correctly. From Settings, confirm "Update router" has its chevron back and also navigates to the same screen. Confirm the screen shows the auto-update toggle, version history, and rollback note.

- [ ] **Step 6: Check offline state**

Navigate to Help & Fixes, click "Simulate offline mode →". Confirm you land on the Dashboard showing the grey "Can't reach your router" status card, with quick actions split into "Still available on this Wi-Fi" (Pause All, Guest Wi-Fi, Restart — normal-looking) and "Needs internet" (Remote Access — dimmed). Click the link again (still reachable via Help & Fixes) to confirm it toggles back to the normal green state.

- [ ] **Step 7: Push to GitHub**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git push origin main
```
