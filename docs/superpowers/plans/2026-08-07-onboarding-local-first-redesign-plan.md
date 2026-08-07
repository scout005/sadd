# Onboarding Local-First Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorder onboarding in `sadd-website.html` so every required security step (admin password, Wi-Fi naming, local recovery code) happens before any account/cloud step, matching SRS FR-01 and backlog US14.1/US14.3 ("local-first, cloud-second"). Account creation (`signup`→`mfa`) becomes a separate, optional flow reachable from the dashboard.

**Architecture:** Same single-file JS-driven SPA as Phases A/B. `screens`/`screenMeta`/`pageTitles` are single-line JS object literals edited via the `json.loads`/`json.dumps` round-trip technique; `forwardMap`/`textLinkMap`/`state`/`render()`/the click handler are normal multi-line source edited via the Edit tool. Three new screens are added (`changepassword`, `recoverycode`, `wancheck`); `welcome` is rebuilt in place; `setup`/`discover` get minor step-numbering/navigation updates; `signup`'s back-link and `success`/`mfa`'s forward targets are repointed; one new state flag + a dashboard content variant are added, following the exact pattern already used for `dashboardOffline` in Phase B.

**Tech Stack:** Plain HTML/CSS/JS, no build step, no test runner. Verification is Python `json.loads` sanity checks plus `grep`-based assertions, same as Phases A/B.

---

## Before you start

**Line numbers move.** As of the start of this plan: `const screens = ` is on line 590, `const screenMeta = ` on line 591, `const pageTitles = ` on line 592, `const state = ` on line 594, `const forwardMap = ` on line 630, `const textLinkMap = ` on line 634 (all 1-indexed; subtract 1 for Python's 0-indexed `lines[]`). **Every task below must re-confirm current line numbers with**:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = \|^  const screenMeta = \|^  const pageTitles = \|^  const state = \|const forwardMap\|const textLinkMap" sadd-website.html | cut -c1-50
```
before running any script, adjusting indices if they've drifted.

Standard mutation pattern for `screens` (same for `screenMeta`, just change the variable name/line index — `pageTitles` is NOT touched by this plan, since none of the 3 new screens are `app`-type):
```python
import json
path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]  # confirm this index first!
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])
# ... mutate obj ...
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
```

Git identity convention (no global identity configured on this machine; `git config` is off-limits):
```bash
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git ...
```
You have explicit user consent to commit and push directly to `main`.

---

### Task 1: Rebuild `welcome` as the router-connect step

**Files:** Modify `sadd-website.html` (`screens` object key `welcome`; `forwardMap` in `<script>`)

- [ ] **Step 1: Verify current state**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print(\"welcome has 'Start Setup':\", 'Start Setup' in obj['welcome'])
"
grep -n "const forwardMap" sadd-website.html
```
Expected: `welcome has 'Start Setup': True`.

- [ ] **Step 2: Replace `welcome`'s content**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

obj['welcome'] = (
    '\n        <div class=\"split\">\n'
    '          <div class=\"split-brand\">\n'
    '            <div>\n'
    '              <div style=\"display:flex;align-items:center;gap:10px;margin-bottom:40px;\"><div style=\"width:34px;height:34px;border-radius:14px;background:rgba(255,255,255,.15);display:flex;align-items:center;justify-content:center;\"><svg width=\"17\" height=\"17\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M3 10.5 12 3l9 7.5\"/><path d=\"M5 9v10a1 1 0 0 0 1 1h3v-6h6v6h3a1 1 0 0 0 1-1V9\"/></svg></div><span style=\"font-weight:800;font-size:18px;\">Sadd</span></div>\n'
    '              <div class=\"split-headline\">Welcome home.</div>\n'
    '              <div class=\"split-sub\">A few minutes now means a Wi-Fi network that quietly takes care of your family from here on.</div>\n'
    '            </div>\n'
    '            <div class=\"split-quote\">No jargon, no manuals \u2014 just a few plain questions and you\\'re online.</div>\n'
    '          </div>\n'
    '          <div class=\"split-form\"><div class=\"inner\" style=\"text-align:center;\">\n'
    '            <h1 class=\"scr-title\">Let\\'s find your router</h1>\n'
    '            <p class=\"scr-sub\">Scan the code on the bottom of your router, or connect a cable.</p>\n'
    '            <div class=\"conn-toggle pill-toggle\" data-group=\"connectrtr\" style=\"max-width:300px;margin:0 auto;\">\n'
    '              <button class=\"active\" data-method=\"qr\">Scan QR code</button>\n'
    '              <button data-method=\"cable\">Use a cable</button>\n'
    '            </div>\n'
    '            <div data-panel=\"qr\" data-group=\"connectrtr\" style=\"margin-top:18px;\">\n'
    '              <div class=\"qr-card\" style=\"max-width:220px;margin:0 auto;\">\n'
    '                <div class=\"qr-box\"></div>\n'
    '                <span style=\"font-size:12px;color:var(--muted);\">Look for the sticker on the underside of your router</span>\n'
    '              </div>\n'
    '              <button class=\"btn btn-primary\" style=\"width:auto;padding:14px 40px;margin:24px auto 0;\">Scan QR Code</button>\n'
    '            </div>\n'
    '            <div data-panel=\"cable\" data-group=\"connectrtr\" style=\"display:none;margin-top:18px;\">\n'
    '              <div class=\"scan-banner\" style=\"max-width:320px;margin:0 auto;\"><div class=\"dot\"><svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 6 9 17l-5-5\"/></svg></div><div><strong>Cable connected</strong><span>Your device is talking to the router</span></div></div>\n'
    '              <button class=\"btn btn-primary\" style=\"width:auto;padding:14px 40px;margin:24px auto 0;\">Continue</button>\n'
    '            </div>\n'
    '            <p class=\"foot-link\">Already have an account? <a href=\"#\" data-goto=\"login\">Log in</a></p>\n'
    '          </div></div>\n'
    '        </div>\n'
    '      </div>'
)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected: `done`.

- [ ] **Step 3: Update `forwardMap['welcome']` to point to the new `changepassword` screen**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    welcome:'signup', login:'dashboard', signup:'mfa', mfa:'setup',
```
- new_string:
```
    welcome:'changepassword', login:'dashboard', signup:'mfa', mfa:'dashboard',
```
(This also repoints `mfa`'s forward target from `'setup'` to `'dashboard'`, since `mfa` is no longer followed by the Wi-Fi-naming step — completing the now-optional account flow returns the user to the dashboard. `signup:'mfa'` is unchanged.)

- [ ] **Step 4: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
s = obj['welcome']
print('has conn-toggle:', 'conn-toggle pill-toggle' in s)
print('has qr panel:', 'data-panel=\"qr\"' in s)
print('has cable panel:', 'data-panel=\"cable\"' in s and 'style=\"display:none;' in s)
print('login link intact:', 'data-goto=\"login\"' in s)
"
grep -n "welcome:'changepassword'" sadd-website.html
grep -n "mfa:'dashboard'" sadd-website.html
```
Expected: `JSON valid, keys: 28`, all `True`, both greps return one match each.

- [ ] **Step 5: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: rebuild welcome screen as router-connect step (QR + cable), decouple from account flow"
```

---

### Task 2: Add the `changepassword` screen

**Files:** Modify `sadd-website.html` (`screens` and `screenMeta` objects; `forwardMap`)

- [ ] **Step 1: Add the screen and its metadata**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = \|^  const screenMeta = " sadd-website.html
```
(confirm indices, adjust below if needed)

```bash
python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

obj['changepassword'] = (
    '\n        <div class=\"wizard-desk\"><div class=\"wizard-card\">\n'
    '          <div class=\"page-crumb\" data-goto=\"welcome\"><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"m15 18-6-6 6-6\"/></svg>Back</div>\n'
    '          <div class=\"progress-wrap\">\n'
    '            <div class=\"progress-steps\"><span>Step 1 of 5</span><span class=\"cur\">Secure your router</span></div>\n'
    '            <div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:20%;\"></div></div>\n'
    '          </div>\n'
    '          <h1 class=\"scr-title\">Change the admin password</h1>\n'
    '          <p class=\"scr-sub\">Your router came with a unique default password. Replace it with one only you know.</p>\n'
    '          <div class=\"field\">\n'
    '            <label>New admin password</label>\n'
    '            <div class=\"input-wrap\"><input class=\"input with-icon pw-input\" type=\"password\" value=\"\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\"><button class=\"icon-btn-inline pw-toggle\"><svg width=\"19\" height=\"19\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7Z\"/><circle cx=\"12\" cy=\"12\" r=\"3\"/></svg></button></div>\n'
    '            <div class=\"strength\"><div class=\"strength-bars\"><span class=\"on\"></span><span class=\"on\"></span><span class=\"on\"></span><span></span></div><span class=\"strength-label\">Good</span></div>\n'
    '          </div>\n'
    '          <div class=\"tip-box\"><svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"10\"/><path d=\"M12 16v-4M12 8h.01\"/></svg><span>This protects your router\\'s settings \u2014 separate from your Wi-Fi password, which you\\'ll set next.</span></div>\n'
    '          <div style=\"display:flex;justify-content:flex-end;gap:12px;margin-top:24px;\">\n'
    '            <button class=\"btn btn-secondary\" style=\"width:auto;padding:13px 24px;\">Back</button>\n'
    '            <button class=\"btn btn-primary\" style=\"width:auto;padding:13px 34px;\">Continue</button>\n'
    '          </div>\n'
    '        </div></div>\n'
    '      </div>'
)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix

line2 = lines[590]
prefix2 = line2[:line2.index('const screenMeta = ') + len('const screenMeta = ')]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
suffix2 = line2[end2+1:]
meta = json.loads(line2[start2:end2+1])
meta['changepassword'] = 'auth'
lines[590] = prefix2 + json.dumps(meta, ensure_ascii=True) + suffix2

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 1')
"
```
Expected: `done step 1`.

- [ ] **Step 2: Update `forwardMap['changepassword']`**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    welcome:'changepassword', login:'dashboard', signup:'mfa', mfa:'dashboard',
    setup:'discover', discover:'success', success:'dashboard'
```
- new_string:
```
    welcome:'changepassword', login:'dashboard', signup:'mfa', mfa:'dashboard',
    changepassword:'setup', setup:'discover', discover:'success', success:'dashboard'
```
(This step only adds `changepassword:'setup'` — `setup`'s own forward target changes to `recoverycode` in Task 3, not here.)

- [ ] **Step 3: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('changepassword present:', 'changepassword' in obj)
line2 = lines[590]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
meta = json.loads(line2[start2:end2+1])
print('screenMeta has changepassword:', meta.get('changepassword'))
"
grep -n "changepassword:'setup'" sadd-website.html
```
Expected: `JSON valid, keys: 29`, `changepassword present: True`, `screenMeta has changepassword: auth`, one grep match.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: add changepassword screen as step 1 of local-first onboarding"
```

---

### Task 3: Update `setup` (Name your Wi-Fi) for its new position

**Files:** Modify `sadd-website.html` (`screens` object key `setup`; `forwardMap`)

- [ ] **Step 1: Verify current state**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = " sadd-website.html
```
```bash
python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('has old crumb target:', 'data-goto=\"mfa\"' in obj['setup'])
print('has old progress text:', 'Step 3 of 5' in obj['setup'])
"
```
Expected: both `True`.

- [ ] **Step 2: Update the back-crumb and progress step/width**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['setup']
old_crumb = '<div class=\"page-crumb\" data-goto=\"mfa\">'
assert s.count(old_crumb) == 1
s = s.replace(old_crumb, '<div class=\"page-crumb\" data-goto=\"changepassword\">')

old_progress = '<div class=\"progress-steps\"><span>Step 3 of 5</span><span class=\"cur\">Name your Wi-Fi</span></div>\n            <div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:60%;\"></div></div>'
assert s.count(old_progress) == 1, 'progress anchor not found -- re-inspect obj[setup] before proceeding'
new_progress = '<div class=\"progress-steps\"><span>Step 2 of 5</span><span class=\"cur\">Name your Wi-Fi</span></div>\n            <div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:40%;\"></div></div>'
s = s.replace(old_progress, new_progress)

obj['setup'] = s
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected: `done`. If the `assert` on `old_progress` fails, STOP and re-print `obj['setup']` to see the exact current whitespace/text before adjusting.

- [ ] **Step 3: Update `forwardMap['setup']`**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    changepassword:'setup', setup:'discover', discover:'success', success:'dashboard'
```
- new_string:
```
    changepassword:'setup', setup:'recoverycode', discover:'success', success:'dashboard'
```

- [ ] **Step 4: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
s = obj['setup']
print('crumb updated:', 'data-goto=\"changepassword\"' in s)
print('old crumb gone:', 'data-goto=\"mfa\"' not in s)
print('progress updated:', 'Step 2 of 5' in s and 'width:40%' in s)
"
grep -n "setup:'recoverycode'" sadd-website.html
```
Expected: `JSON valid, keys: 29`, all `True`, one grep match.

- [ ] **Step 5: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "fix: reposition setup screen as step 2 of 5 in local-first flow"
```

---

### Task 4: Add the `recoverycode` screen

**Files:** Modify `sadd-website.html` (`screens` and `screenMeta` objects; `forwardMap`)

- [ ] **Step 1: Add the screen and its metadata**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = \|^  const screenMeta = " sadd-website.html
```
(confirm indices, adjust below)

```bash
python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

obj['recoverycode'] = (
    '\n        <div class=\"wizard-desk\"><div class=\"wizard-card\">\n'
    '          <div class=\"page-crumb\" data-goto=\"setup\"><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"m15 18-6-6 6-6\"/></svg>Back</div>\n'
    '          <div class=\"progress-wrap\">\n'
    '            <div class=\"progress-steps\"><span>Step 3 of 5</span><span class=\"cur\">Save your recovery code</span></div>\n'
    '            <div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:60%;\"></div></div>\n'
    '          </div>\n'
    '          <h1 class=\"scr-title\">Save your recovery code</h1>\n'
    '          <p class=\"scr-sub\">If you ever lose access to your router, this code gets you back in \u2014 even without internet.</p>\n'
    '          <div class=\"qr-card\" style=\"max-width:320px;margin:0 auto 18px;\">\n'
    '            <strong style=\"display:block;font-size:26px;letter-spacing:.06em;font-family:\\'SF Mono\\',\\'Roboto Mono\\',monospace;\">7F3K-9QXR-4LMN</strong>\n'
    '            <span style=\"font-size:12px;color:var(--muted);\">Write it down or take a screenshot</span>\n'
    '          </div>\n'
    '          <div class=\"checkrow\"><input type=\"checkbox\"><span>I\\'ve saved this code somewhere safe</span></div>\n'
    '          <div style=\"display:flex;justify-content:flex-end;gap:12px;margin-top:24px;\">\n'
    '            <button class=\"btn btn-secondary\" style=\"width:auto;padding:13px 24px;\">Back</button>\n'
    '            <button class=\"btn btn-primary\" style=\"width:auto;padding:13px 34px;\">Continue</button>\n'
    '          </div>\n'
    '        </div></div>\n'
    '      </div>'
)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix

line2 = lines[590]
prefix2 = line2[:line2.index('const screenMeta = ') + len('const screenMeta = ')]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
suffix2 = line2[end2+1:]
meta = json.loads(line2[start2:end2+1])
meta['recoverycode'] = 'auth'
lines[590] = prefix2 + json.dumps(meta, ensure_ascii=True) + suffix2

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 1')
"
```
Expected: `done step 1`.

- [ ] **Step 2: Update `forwardMap['recoverycode']`**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    changepassword:'setup', setup:'recoverycode', discover:'success', success:'dashboard'
```
- new_string:
```
    changepassword:'setup', setup:'recoverycode', recoverycode:'discover', discover:'success', success:'dashboard'
```

- [ ] **Step 3: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('recoverycode present:', 'recoverycode' in obj)
print('has checkrow:', 'checkrow' in obj['recoverycode'])
line2 = lines[590]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
meta = json.loads(line2[start2:end2+1])
print('screenMeta has recoverycode:', meta.get('recoverycode'))
"
grep -n "recoverycode:'discover'" sadd-website.html
```
Expected: `JSON valid, keys: 30`, all checks `True`/`auth`, one grep match.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: add recoverycode screen as step 3 of local-first onboarding"
```

---

### Task 5: Update `discover` (Find devices) for its new position

**Files:** Modify `sadd-website.html` (`screens` object key `discover`; `forwardMap`)

- [ ] **Step 1: Verify current state**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = " sadd-website.html
```
```bash
python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('has old crumb target:', 'data-goto=\"setup\"' in obj['discover'])
print('has old progress text:', 'Step 5 of 5' in obj['discover'])
print('has old button text:', 'Finish setup' in obj['discover'])
"
```
Expected: all `True`.

- [ ] **Step 2: Update back-crumb, progress step/width, and the primary button's label**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['discover']

old_crumb = '<div class=\"page-crumb\" data-goto=\"setup\">'
assert s.count(old_crumb) == 1
s = s.replace(old_crumb, '<div class=\"page-crumb\" data-goto=\"recoverycode\">')

old_progress = '<div class=\"progress-steps\"><span>Step 5 of 5</span><span class=\"cur\">Find your devices</span></div>\n            <div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:100%;\"></div></div>'
assert s.count(old_progress) == 1, 'progress anchor not found -- re-inspect obj[discover] before proceeding'
new_progress = '<div class=\"progress-steps\"><span>Step 4 of 5</span><span class=\"cur\">Find your devices</span></div>\n            <div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:80%;\"></div></div>'
s = s.replace(old_progress, new_progress)

old_btn = '<button class=\"btn btn-primary\" style=\"width:auto;padding:13px 34px;\">Finish setup</button>'
assert s.count(old_btn) == 1
new_btn = '<button class=\"btn btn-primary\" style=\"width:auto;padding:13px 34px;\">Continue</button>'
s = s.replace(old_btn, new_btn)

obj['discover'] = s
new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected: `done`. If any `assert` fails, STOP and re-print `obj['discover']` before adjusting.

- [ ] **Step 3: Update `forwardMap['discover']`**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    changepassword:'setup', setup:'recoverycode', recoverycode:'discover', discover:'success', success:'dashboard'
```
- new_string:
```
    changepassword:'setup', setup:'recoverycode', recoverycode:'discover', discover:'wancheck', success:'dashboard'
```
(`discover` now points to `wancheck` instead of `success`; `success:'dashboard'` is unchanged and will be reused once `wancheck` is added in Task 6.)

- [ ] **Step 4: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
s = obj['discover']
print('crumb updated:', 'data-goto=\"recoverycode\"' in s)
print('progress updated:', 'Step 4 of 5' in s and 'width:80%' in s)
print('button relabeled:', 'Continue' in s and 'Finish setup' not in s)
"
grep -n "discover:'wancheck'" sadd-website.html
```
Expected: `JSON valid, keys: 30`, all `True`, one grep match.

- [ ] **Step 5: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "fix: reposition discover screen as step 4 of 5, route forward to wancheck"
```

---

### Task 6: Add the `wancheck` screen

**Files:** Modify `sadd-website.html` (`screens` and `screenMeta` objects; `forwardMap`)

- [ ] **Step 1: Add the screen and its metadata**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = \|^  const screenMeta = " sadd-website.html
```
(confirm indices, adjust below)

```bash
python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

obj['wancheck'] = (
    '\n        <div class=\"wizard-desk\"><div class=\"wizard-card\">\n'
    '          <div class=\"page-crumb\" data-goto=\"discover\"><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"m15 18-6-6 6-6\"/></svg>Back</div>\n'
    '          <div class=\"progress-wrap\">\n'
    '            <div class=\"progress-steps\"><span>Step 5 of 5</span><span class=\"cur\">Checking your connection</span></div>\n'
    '            <div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:100%;\"></div></div>\n'
    '          </div>\n'
    '          <h1 class=\"scr-title\">Checking your internet connection</h1>\n'
    '          <div class=\"check-card check-warn\"><div class=\"cc-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 9v4M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z\"/></svg></div><div><strong>No internet yet</strong><span>That\\'s OK \u2014 your Wi-Fi and security are already set up and working</span></div></div>\n'
    '          <p class=\"scr-sub\">Check your modem or contact your internet provider when you\\'re ready. You can finish setup now and connect later.</p>\n'
    '          <div style=\"display:flex;justify-content:flex-end;gap:12px;margin-top:24px;\">\n'
    '            <button class=\"btn btn-secondary\" style=\"width:auto;padding:13px 24px;\">Check again</button>\n'
    '            <button class=\"btn btn-primary\" style=\"width:auto;padding:13px 34px;\">Continue</button>\n'
    '          </div>\n'
    '        </div></div>\n'
    '      </div>'
)

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix

line2 = lines[590]
prefix2 = line2[:line2.index('const screenMeta = ') + len('const screenMeta = ')]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
suffix2 = line2[end2+1:]
meta = json.loads(line2[start2:end2+1])
meta['wancheck'] = 'auth'
lines[590] = prefix2 + json.dumps(meta, ensure_ascii=True) + suffix2

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 1')
"
```
Expected: `done step 1`.

- [ ] **Step 2: Update `forwardMap['wancheck']`**

Use the Edit tool on `sadd-website.html`:
- old_string:
```
    changepassword:'setup', setup:'recoverycode', recoverycode:'discover', discover:'wancheck', success:'dashboard'
```
- new_string:
```
    changepassword:'setup', setup:'recoverycode', recoverycode:'discover', discover:'wancheck', wancheck:'success', success:'dashboard'
```

- [ ] **Step 3: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('wancheck present:', 'wancheck' in obj)
print('has check-warn:', 'check-card check-warn' in obj['wancheck'])
line2 = lines[590]
start2 = line2.index('const screenMeta = ') + len('const screenMeta = ')
end2 = line2.rstrip().rfind('};')
meta = json.loads(line2[start2:end2+1])
print('screenMeta has wancheck:', meta.get('wancheck'))
"
grep -n "wancheck:'success'" sadd-website.html
```
Expected: `JSON valid, keys: 31`, all checks `True`/`auth`, one grep match.

- [ ] **Step 4: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: add wancheck screen as step 5 of local-first onboarding, never blocks completion"
```

---

### Task 7: Detach account creation from onboarding; add optional dashboard entry point

**Files:** Modify `sadd-website.html` (`screens` object keys `signup`, `dashboard`; new top-level JS constant `dashboardFreshSetup`; `state`; `render()`; click handler; `textLinkMap`)

**Context:** `signup`'s back-crumb currently points to `welcome` (the old first onboarding screen) — it must now point to `dashboard`, since `signup` is only reached from there. A new `state.freshSetup` flag (set when a user completes the local-only flow via `success`) selects a dashboard variant with a "Set up remote access" banner and an accurate (not-yet-configured) Remote Access summary card — mirroring the exact pattern already used for `state.offline`/`dashboardOffline` in Phase B.

- [ ] **Step 1: Verify current state**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = \|^  const state = " sadd-website.html
```
```bash
python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('signup crumb targets welcome:', 'data-goto=\"welcome\"' in obj['signup'])
print(obj['dashboard'])
"
```
Expected: `signup crumb targets welcome: True`, and the printed `dashboard` content should match exactly:
```
<div class="dash-main"><h2>Good afternoon, Jenna</h2>
            <p class="dash-date">Wednesday, August 5</p>
            <div class="status-card">
              <div class="s-dot"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg></div>
              <div><strong>Everything is working</strong><span>12 devices connected · Updated just now</span></div>
            </div>
            <div class="quick-actions" style="max-width:420px;">
              <div class="qa-btn danger">Pause All</div>
              <div class="qa-btn">Guest Wi-Fi</div>
              <div class="qa-btn">Restart</div>
            </div>
            <div class="card-grid mt-24">
              <div class="dcard"><div class="dcard-head"><strong>Devices</strong><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="var(--muted-2)" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg></div><div class="dcard-big">12</div><div class="dcard-sub">1 device needs attention</div></div>
              <div class="dcard"><div class="dcard-head"><strong>Parental Controls</strong><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="var(--muted-2)" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg></div><div class="dcard-big">3</div><div class="dcard-sub">devices have bedtime rules</div></div>
              <div class="dcard"><div class="dcard-head"><strong>Security</strong><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="var(--muted-2)" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg></div><div class="dcard-big">214</div><div class="dcard-sub">threats blocked this month</div></div>
              <div class="dcard"><div class="dcard-head"><strong>Remote Access</strong><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="var(--muted-2)" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg></div><div class="dcard-big">On</div><div class="dcard-sub">2 family members connected</div></div>
            </div></div>
```
If it differs at all (e.g. an earlier task in this plan somehow touched it, which it shouldn't have), STOP and re-derive the `dashboardFreshSetup` content in Step 3 below from whatever the actual current content is, rather than using the version given.

- [ ] **Step 2: Fix `signup`'s back-crumb**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

old = '<div class=\"page-crumb\" data-goto=\"welcome\">'
assert obj['signup'].count(old) == 1
obj['signup'] = obj['signup'].replace(old, '<div class=\"page-crumb\" data-goto=\"dashboard\">')

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done step 2')
"
```
Expected: `done step 2`.

- [ ] **Step 3: Add the `dashboardFreshSetup` constant and `state.freshSetup` flag**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const state = " sadd-website.html
```
Use the Edit tool on `sadd-website.html` (adjust if the current `state` line differs from Phase B's — it should read exactly this, since nothing since Phase B has touched it):
- old_string:
```
  const state = { screen: 'welcome', offline: false };
```
- new_string:
```
  const state = { screen: 'welcome', offline: false, freshSetup: false };

  const dashboardFreshSetup = '<div class=\"dash-main\"><h2>Good afternoon, Jenna</h2>\n            <p class=\"dash-date\">Wednesday, August 5</p>\n            <div class=\"nav-card\" style=\"border-color:var(--teal);background:var(--teal-tint);\"><div class=\"nc-icon\"><svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"3\" y=\"11\" width=\"18\" height=\"10\" rx=\"2\"/><path d=\"M7 11V7a5 5 0 0 1 10 0v4\"/></svg></div><div class=\"nc-main\"><strong>Want to check on things when you\\'re away?</strong><span>Set up remote access \u2014 optional, takes about a minute</span></div><svg class=\"nc-chev\" width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div>\n            <div class=\"status-card\">\n              <div class=\"s-dot\"><svg width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 6 9 17l-5-5\"/></svg></div>\n              <div><strong>Everything is working</strong><span>12 devices connected \u00b7 Updated just now</span></div>\n            </div>\n            <div class=\"quick-actions\" style=\"max-width:420px;\">\n              <div class=\"qa-btn danger\">Pause All</div>\n              <div class=\"qa-btn\">Guest Wi-Fi</div>\n              <div class=\"qa-btn\">Restart</div>\n            </div>\n            <div class=\"card-grid mt-24\">\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Devices</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">12</div><div class=\"dcard-sub\">1 device needs attention</div></div>\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Parental Controls</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">3</div><div class=\"dcard-sub\">devices have bedtime rules</div></div>\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Security</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">214</div><div class=\"dcard-sub\">threats blocked this month</div></div>\n              <div class=\"dcard\"><div class=\"dcard-head\"><strong>Remote Access</strong><svg width=\"15\" height=\"15\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"var(--muted-2)\" stroke-width=\"2\"><path d=\"m9 18 6-6-6-6\"/></svg></div><div class=\"dcard-big\">Off</div><div class=\"dcard-sub\">not set up yet</div></div>\n            </div></div>';
```

Note: `dashboardFreshSetup` is byte-identical to the live `dashboard` screen except for (a) the new `.nav-card` banner inserted right after the `<p class="dash-date">` line, and (b) the Remote Access `dcard`'s value changed from `On`/`2 family members connected` to `Off`/`not set up yet` — consistent with a router that just finished local-only setup and has no account/remote access configured. The banner reuses the existing `.nav-card`/`.nc-icon`/`.nc-main`/`.nc-chev` classes (already used elsewhere for clickable dashboard rows) with an inline teal accent border/background to make it stand out as a suggestion rather than a neutral nav row.

- [ ] **Step 4: Update `render()` to use `dashboardFreshSetup` when appropriate**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "state.screen === 'dashboard' && state.offline" sadd-website.html
```
Use the Edit tool on `sadd-website.html`:
- old_string:
```
      const content = (state.screen === 'dashboard' && state.offline) ? dashboardOffline : screens[state.screen];
```
- new_string:
```
      const content = (state.screen === 'dashboard' && state.offline) ? dashboardOffline
        : (state.screen === 'dashboard' && state.freshSetup) ? dashboardFreshSetup
        : screens[state.screen];
```

- [ ] **Step 5: Fix `success`'s dead "Go to Dashboard" button, and set `state.freshSetup` for either exit path**

**Context for this step (added after Task 6's code review):** `success` currently has two buttons — `.btn-primary` "Set up parental controls now" (works today, via the generic `forwardMap['success']='dashboard'` handler) and `.btn-secondary` "Go to Dashboard" (currently dead — `.btn-secondary` is never wired to any action anywhere in this file). Since Task 6's `wancheck` screen now tells the user "you can finish setup now," and `success` is the very next screen, a broken "Go to Dashboard" button right at the exit of the flow this plan is building undermines that promise. Fix it by giving it an explicit `data-goto="dashboard"` (the same direct-navigation mechanism `.page-crumb` elements already use file-wide), rather than leaving it to the generic primary-button/forwardMap path.

First, fix the button:
```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "^  const screens = " sadd-website.html
```
```bash
python -c "
import json

path = 'sadd-website.html'
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
prefix = line[:line.index('const screens = ') + len('const screens = ')]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
suffix = line[end+1:]
obj = json.loads(line[start:end+1])

s = obj['success']
old = '<button class=\"btn btn-secondary\" style=\"width:auto;padding:13px 26px;\">Go to Dashboard</button>'
assert s.count(old) == 1, 'Go to Dashboard button not found -- re-inspect obj[success] before proceeding'
new = '<button class=\"btn btn-secondary\" data-goto=\"dashboard\" style=\"width:auto;padding:13px 26px;\">Go to Dashboard</button>'
s = s.replace(old, new)
obj['success'] = s

new_obj_str = json.dumps(obj, ensure_ascii=True)
lines[589] = prefix + new_obj_str + suffix
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('done')
"
```
Expected: `done`.

Now, set `state.freshSetup` for EITHER exit path from `success` (not just the primary button) — since `data-goto` clicks are handled earlier in the delegated click handler than the primary-button check and `return` immediately, a flag set only near the primary-button check would never fire for the newly-fixed "Go to Dashboard" button. Insert the flag-setting at the very top of the handler instead, so it fires regardless of which of the two buttons is clicked:

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "document.body.addEventListener('click'" sadd-website.html
```
Use the Edit tool on `sadd-website.html`:
- old_string:
```
  document.body.addEventListener('click', (e)=>{

    // offline-mode preview toggle (Help & Fixes)
```
- new_string:
```
  document.body.addEventListener('click', (e)=>{

    // mark local-only setup as complete (no account yet) when leaving the success screen
    if(state.screen === 'success'){ state.freshSetup = true; }

    // offline-mode preview toggle (Help & Fixes)
```

- [ ] **Step 6: Add the `textLinkMap` entry for the new banner**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -n "const textLinkMap" sadd-website.html
```
Read the current exact content with `sed -n '<N>,<N+10>p' sadd-website.html`, then use the Edit tool to add one entry. If the object still contains a line reading `'Home':'dashboard','Remote Access':'vpn','Help':'help',` (unchanged since Phase A/B):

- old_string:
```
    'Home':'dashboard','Remote Access':'vpn','Help':'help',
```
- new_string:
```
    'Home':'dashboard','Remote Access':'vpn','Help':'help',
    'Want to check on things when you\'re away?':'signup',
```

If the surrounding text differs by the time you run this, locate `textLinkMap`, read its current exact content, and add the entry `'Want to check on things when you\'re away?':'signup'` (matching the banner's exact `<strong>` text from Step 3 — the `.nav-card` click-routing mechanism matches on that element's `<strong>` text) anywhere inside the object, following the existing comma-separated style.

- [ ] **Step 7: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && python -c "
import json
with open('sadd-website.html', encoding='utf-8') as f:
    lines = f.readlines()
line = lines[589]
start = line.index('const screens = ') + len('const screens = ')
end = line.rstrip().rfind('};')
obj = json.loads(line[start:end+1])
print('JSON valid, keys:', len(obj))
print('signup crumb fixed:', 'data-goto=\"dashboard\"' in obj['signup'])
print('signup old crumb gone:', 'data-goto=\"welcome\"' not in obj['signup'])
print('dashboard (live) unchanged Remote Access On:', '<div class=\"dcard-big\">On</div><div class=\"dcard-sub\">2 family members connected</div>' in obj['dashboard'])
print('success Go to Dashboard button now wired:', '<button class=\"btn btn-secondary\" data-goto=\"dashboard\"' in obj['success'])
"
grep -c "const dashboardFreshSetup = " sadd-website.html
grep -c "freshSetup" sadd-website.html
grep -c "Want to check on things when you.re away" sadd-website.html
```
Expected: `JSON valid, keys: 31`, all four `print` checks `True`, `dashboardFreshSetup` grep `1`, `freshSetup` grep `>=3` (state init, render() check, click-handler set), `Want to check...` grep `2` (banner markup + textLinkMap entry).

- [ ] **Step 8: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add sadd-website.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat: detach account creation from onboarding, add optional post-setup dashboard entry point"
```

---

### Task 8: Manual click-through verification and push

**Files:** none (verification only)

- [ ] **Step 1: Open the file in a browser**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && start sadd-website.html
```

- [ ] **Step 2: Walk the full local-only path**

Click through `Welcome (Scan QR Code) → Change admin password → Name your Wi-Fi → Save recovery code (check the box) → Find devices → Checking your connection → All set`. Confirm:
- No screen in this path ever shows a login/account/MFA prompt.
- Each screen's back-crumb returns to the correct previous screen.
- The progress bar reads "Step 1 of 5" through "Step 5 of 5" in order, filling left to right.
- On `wancheck`, "Check again" and "Continue" are both clickable and Continue always advances regardless.

- [ ] **Step 3: Test the "Use a cable" path on `welcome`**

From Welcome, click "Use a cable" — confirm the panel swaps to show "Cable connected" with its own Continue button, and clicking it also advances to "Change admin password."

- [ ] **Step 4: Confirm the dashboard banner appears after fresh setup, via BOTH exit buttons on the success screen**

From "All set," click **"Go to Dashboard"** (the secondary button) — confirm it now actually navigates (it was dead before this plan) and lands on the fresh-setup dashboard variant: the teal "Want to check on things when you're away?" banner near the top, and the Remote Access card reading "Off / not set up yet." Then repeat starting from "All set" again, this time clicking **"Set up parental controls now"** (the primary button) — confirm it lands on the same fresh-setup dashboard variant. Click the banner and confirm it opens Create Account → Verify Identity, and confirm each of those screens' own back-crumb now returns to the dashboard (not to Welcome).

- [ ] **Step 5: Confirm the returning-user path is unaffected**

From the dashboard (or anywhere), navigate to `login` (e.g. via the "Already have an account? Log in" link on Welcome) then continue to the dashboard. Confirm this dashboard shows the original content — green "Everything is working," Remote Access "On / 2 family members connected," no banner.

- [ ] **Step 6: Push to GitHub**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git push origin main
```
