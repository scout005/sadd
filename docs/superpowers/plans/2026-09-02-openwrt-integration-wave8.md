# OpenWrt Integration — Wave 8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make two pieces of the still-fully-static **Parental Controls** (`parental`) screen real: the "Safe Search" toggle (real DNS-level SafeSearch enforcement via `dnsmasq` CNAME rewrites) and "Custom blocked sites" (real per-domain DNS blocking, reusing Ad Blocking's own mechanism).

**Architecture:** Both features share Ad Blocking's existing `/etc/dnsmasq.blocklist.d` confdir directory (provisioned in Wave 4) rather than introducing a new one — confirmed live (`docker/facts.md` §17) that `dnsmasq`'s `confdir` loads multiple `.conf` files from the same directory simultaneously, so neither feature ever touches Ad Blocking's own `blocklist.conf` or the `confdir` uci option itself, eliminating any risk of regressing that already-real feature. Safe Search's file content is fully static (a fixed, hardcoded list of `cname=` rewrites) and is written via Lua's native `io.open`/`write` — no shell involved for that file at all, confirmed live to work cleanly, and a cleaner mechanism than shelling out for content with no user-input to interpolate. Custom Blocked Sites' content DOES include user-supplied input (the domain), so it's validated strictly and, consistent with every other write endpoint in this project, quoted where it touches any shell command.

**Tech Stack:** Unchanged — OpenWrt 23.05.5 Lua CGI, `dnsmasq`'s `confdir`, vanilla JS/HTML/CSS in `sadd-website.html`, no build step.

---

## Before you start (context every task shares)

- VM: `cd docker && docker compose up -d --build`, wait for `docker inspect --format='{{.State.Health.Status}}' openwrt` to report `healthy`.
- SSH: `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost`. SCP requires `-O`.
- Git identity: `GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com"`.
- **Read `docker/provision/www/api/adblock` in full first** — every helper (`run`, `shell_quote`, `json_escape`, `send_headers`, the write-then-verify-then-restart discipline) both new endpoints below reuse, and it's the endpoint that originally provisioned `/etc/dnsmasq.blocklist.d` (via `docker/provision/09-provision-adblock-api.sh`) and established the "toggle a real dnsmasq confdir file, restart dnsmasq to apply" pattern this wave extends to two more files in the SAME directory.
- **Critical safety rule, non-negotiable**: neither new endpoint may EVER write to, delete, or otherwise touch `/etc/dnsmasq.blocklist.d/blocklist.conf` (Ad Blocking's own file) or the `dhcp.@dnsmasq[0].confdir` uci option. Each new feature manages its own dedicated file(s) in that same directory and nothing else. Any task whose implementation or testing touches either of those must immediately stop and reconsider — this is exactly the mistake the Wave 8 pre-investigation caught itself making and had to revert (`docker/facts.md` §17).
- **Domain-only scope, explicit**: the Custom Blocked Sites input's placeholder ("e.g. example.com or 203.0.113.4") implies domain-OR-IP entry, but this wave only implements the domain case — an IP-shaped input must be rejected with a clear, distinct error message (not silently mishandled as a malformed domain), since IP-based blocking would need a different (firewall-based) mechanism, deferred.
- After all tasks, dispatch one final whole-wave integration-level code-quality review, fix anything it raises, then report Wave 8 complete.

---

### Task 1: `/api/safe-search` endpoint (GET status + POST toggle)

**Files:**
- Create: `docker/provision/www/api/safe-search`
- Create: `docker/provision/16-provision-safe-search-api.sh`
- Modify: `docker/README.md` (Provisioning section: add step 16)

No baseline VM state needed beyond the already-provisioned `/etc/dnsmasq.blocklist.d` directory (Wave 4) — this endpoint only ever creates/reads/removes its own one file inside it.

- [ ] **Step 1: Write the endpoint**

```lua
#!/usr/bin/lua
-- /api/safe-search — GET (status) + POST (toggle). Real DNS-level SafeSearch
-- enforcement for the Parental Controls screen's "Safe Search" toggle,
-- confirmed live before writing this handler (docker/facts.md Section 17):
-- dnsmasq's `cname=` directive genuinely rewrites a query to another
-- hostname (confirmed via real `nslookup` CNAME resolution) — the standard,
-- widely-documented mechanism real routers use to enforce SafeSearch at the
-- DNS level, not something invented for this project.
--
-- GET response shape: {"enabled": true|false}
-- POST body: {"enabled": true|false} -> {"ok": true, "enabled": <bool>}
--
-- === File ownership — critical, do not deviate ===
-- Manages exactly ONE file, /etc/dnsmasq.blocklist.d/safesearch.conf, inside
-- the SAME confdir directory Ad Blocking (Wave 4) already provisions and
-- owns its own separate file (blocklist.conf) in. This endpoint NEVER reads,
-- writes, or deletes blocklist.conf, and NEVER touches the
-- dhcp.@dnsmasq[0].confdir uci option — confirmed live (docker/facts.md
-- Section 17) that dnsmasq's confdir loads multiple .conf files from the
-- same directory simultaneously, so both features' files coexist safely
-- with zero interaction.
--
-- === Fully static content, no shell/uci involved for the write itself ===
-- Every line this file ever contains is a fixed constant — no user-supplied
-- value is ever written here, unlike blocked-sites' per-domain files — so
-- this endpoint writes the file directly via Lua's own io.open/write (no
-- io.popen/shell invocation for the write itself, confirmed live to work
-- cleanly on this VM), which is simpler and has zero shell-injection surface
-- since nothing dynamic ever reaches it. `/etc/init.d/dnsmasq restart` (a
-- fixed, non-interpolated command) is still shelled out via run(), same as
-- every other endpoint that needs to apply a dnsmasq config change.
--
-- === Domain list — a plausible, not-exhaustive baseline ===
-- Covers Google search, YouTube, Bing, and DuckDuckGo (matching the
-- mockup's own "Filters results on Google, Bing, YouTube & DuckDuckGo" copy
-- exactly) via their real, independently-verified-live CNAME targets
-- (docker/facts.md Section 17: forcesafesearch.google.com,
-- restrict.youtube.com, strict.bing.com, safe.duckduckgo.com — all four
-- confirmed still resolving from a real internet-connected host at
-- investigation time). Same "narrow, not exhaustive" precedent as Ad
-- Blocking's own 3-domain list — country-TLD variants (google.co.uk, etc.)
-- and mobile-app-specific endpoints are not covered.
--
-- === Read-only verification, not full write-then-readback-verify-then-commit ===
-- There's no uci layer here to stage/commit/revert — a POST either
-- successfully writes (or removes) the file and restarts dnsmasq, or it
-- doesn't. The endpoint reads the file back after writing to confirm the
-- write genuinely landed before reporting success (catching a full-disk or
-- permission failure, the plain-file equivalent of every other endpoint's
-- uci readback-verify step), and reports 500 rather than a false 200 if the
-- content doesn't match what was just written.

local CONF_PATH = "/etc/dnsmasq.blocklist.d/safesearch.conf"

local CNAME_LINES = {
  "cname=www.google.com,forcesafesearch.google.com",
  "cname=google.com,forcesafesearch.google.com",
  "cname=www.youtube.com,restrict.youtube.com",
  "cname=youtube.com,restrict.youtube.com",
  "cname=m.youtube.com,restrict.youtube.com",
  "cname=www.bing.com,strict.bing.com",
  "cname=bing.com,strict.bing.com",
  "cname=duckduckgo.com,safe.duckduckgo.com",
  "cname=www.duckduckgo.com,safe.duckduckgo.com",
}
local EXPECTED_CONTENT = table.concat(CNAME_LINES, "\n") .. "\n"

local function run(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return "" end
  local out = p:read("*a") or ""
  p:close()
  return (out:gsub("%s+$", ""))
end

local function json_escape(s)
  if s == nil then return "" end
  s = tostring(s)
  s = s:gsub('[\\"\n\r\t]', {
    ['\\'] = '\\\\', ['"'] = '\\"', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
  })
  s = s:gsub('[\1-\31]', '')
  return s
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function is_enabled()
  local content = read_file(CONF_PATH)
  return content == EXPECTED_CONTENT
end

local function read_request_body()
  local len = tonumber(os.getenv("CONTENT_LENGTH") or "")
  if len and len > 0 then return io.read(len) or "" end
  return io.read("*a") or ""
end

-- Same hand-rolled flat-JSON-object parser as every other write endpoint —
-- adapted verbatim from adblock/device-pause.
local function json_parse_flat_object(s)
  local obj = {}
  if type(s) ~= "string" then return obj end
  local i, len = 1, #s
  local function skip_ws() while i <= len and s:sub(i, i):match("%s") do i = i + 1 end end
  local function parse_string()
    i = i + 1
    local buf = {}
    local escapes = { ['"']='"', ['\\']='\\', ['/']='/', ['n']='\n', ['r']='\r', ['t']='\t', ['b']='\b', ['f']='\f' }
    while i <= len do
      local c = s:sub(i, i)
      if c == '"' then i = i + 1; return table.concat(buf)
      elseif c == '\\' then
        local nc = s:sub(i + 1, i + 1)
        if nc == 'u' then i = i + 6
        elseif escapes[nc] then buf[#buf+1] = escapes[nc]; i = i + 2
        else buf[#buf+1] = nc; i = i + 2 end
      else buf[#buf+1] = c; i = i + 1 end
    end
    return table.concat(buf)
  end
  skip_ws()
  if s:sub(i, i) ~= '{' then return obj end
  i = i + 1
  skip_ws()
  if s:sub(i, i) == '}' then return obj end
  while i <= len do
    skip_ws()
    if s:sub(i, i) ~= '"' then break end
    local key = parse_string()
    skip_ws()
    if s:sub(i, i) ~= ':' then break end
    i = i + 1
    skip_ws()
    local val
    if s:sub(i, i) == '"' then val = parse_string()
    else
      local start = i
      while i <= len and not s:sub(i, i):match('[,}%s]') do i = i + 1 end
      val = s:sub(start, i - 1)
    end
    obj[key] = val
    skip_ws()
    if s:sub(i, i) == ',' then i = i + 1
    elseif s:sub(i, i) == '}' then i = i + 1; break
    else break end
  end
  return obj
end

local function send_headers(status)
  local reasons = { [400]="Bad Request", [405]="Method Not Allowed", [500]="Internal Server Error" }
  if status and status ~= 200 then
    print("Status: " .. status .. " " .. (reasons[status] or "Error"))
  end
  print("Content-Type: application/json\n")
end

local method = os.getenv("REQUEST_METHOD") or "GET"

if method == "GET" then
  send_headers(200)
  print(string.format('{"enabled":%s}', is_enabled() and "true" or "false"))

elseif method == "POST" then
  local body = read_request_body()
  local req = json_parse_flat_object(body)
  local enabled_req = req.enabled

  if enabled_req ~= "true" and enabled_req ~= "false" then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: enabled (must be a JSON boolean true or false)"}')
  else
    local want_enabled = enabled_req == "true"

    if want_enabled then
      local f = io.open(CONF_PATH, "w")
      local write_ok = false
      if f then
        f:write(EXPECTED_CONTENT)
        f:close()
        write_ok = true
      end
      if not write_ok then
        send_headers(500)
        print('{"ok":false,"error":"failed to write safesearch.conf"}')
      else
        run("/etc/init.d/dnsmasq restart")
        if read_file(CONF_PATH) == EXPECTED_CONTENT then
          send_headers(200)
          print('{"ok":true,"enabled":true}')
        else
          send_headers(500)
          print('{"ok":false,"error":"safesearch.conf write did not verify on readback"}')
        end
      end
    else
      os.remove(CONF_PATH)
      run("/etc/init.d/dnsmasq restart")
      if read_file(CONF_PATH) == nil then
        send_headers(200)
        print('{"ok":true,"enabled":false}')
      else
        send_headers(500)
        print('{"ok":false,"error":"failed to remove safesearch.conf"}')
      end
    end
  end

else
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', json_escape(tostring(method))))
end
```

- [ ] **Step 2: Write the provisioning script**

Base on `docker/provision/13-provision-devpause-api.sh`'s or `14-provision-qos-priority-api.sh`'s current deploy-and-verify-only shape (read one first, they've both been refined through code-review cycles — match the current actual variable-name/deploy idiom, not a guess). It should:
1. `scp -O` the endpoint to `/www/cgi-bin/api/safe-search`, `chmod +x` + `ls -la`.
2. Verify with a real `curl -sf` GET expecting `{"enabled":false}` on a clean VM (or whatever the actual current state is — don't assume clean if this is re-run against an already-toggled VM; the important thing is the endpoint responds with valid JSON, not a specific value).
3. Print a clear final "done" message.

- [ ] **Step 3: Run and verify against the live VM**

```bash
chmod +x docker/provision/16-provision-safe-search-api.sh
./docker/provision/16-provision-safe-search-api.sh
curl -s http://localhost:8081/cgi-bin/api/safe-search
curl -s -X POST -H 'Content-Type: application/json' -d '{"enabled":true}' http://localhost:8081/cgi-bin/api/safe-search
```
Expected: `{"ok":true,"enabled":true}`. Then confirm the real CNAME rewrite live, independently of the endpoint's own claim:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "nslookup www.google.com 127.0.0.1"
```
Expected: a real `canonical name = forcesafesearch.google.com` line. Also confirm Ad Blocking's own state is completely untouched throughout (`ssh ... "cat /etc/dnsmasq.blocklist.d/blocklist.conf"` should show its original 3 `address=` lines, unchanged; `nslookup doubleclick.net 127.0.0.1` should still show the real `0.0.0.0` block). Toggle off (`POST {"enabled":false}`), confirm `nslookup www.google.com` no longer shows the CNAME, confirm Ad Blocking is STILL untouched. Test the toggle-off-when-already-off and toggle-on-when-already-on idempotent paths. Test 400 (missing/malformed `enabled`). Test 405.

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/safe-search docker/provision/16-provision-safe-search-api.sh docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/safe-search endpoint (real DNS-level SafeSearch)"
```

---

### Task 2: Frontend — wire Parental Controls' Safe Search toggle

**Files:**
- Modify: `sadd-website.html` (the `parental` entry in `screens`, new JS, `render()` dispatch, the global click handler, `state`)

This is the FIRST wave to touch the `parental` screen — read its full raw markup once via a small Node script (`console.log(screens['parental'])`) before editing, since no prior wave has added any ids to it.

- [ ] **Step 1: Add an id to the Safe Search row in `screens['parental']`**

Find `<div class="setting-row mt-24"><div class="sr-main"><strong>Safe Search</strong><span>Filters results on Google, Bing, YouTube &amp; DuckDuckGo</span></div><div class="switch on"></div></div>` and add an id to the switch: `<div class="switch on" id="parentalSafeSearchSwitch"></div>`.

- [ ] **Step 2: Add `state.parentalSafeSearchRenderId`**

Add `, parentalSafeSearchRenderId: 0` to `state`.

- [ ] **Step 3: Add the render/handler JS**

Insert after the last write-control function currently in the file (find it fresh — this has shifted across every wave so far, don't assume a specific prior function is still last):

```js
  // ---- Parental Controls "Safe Search" toggle (id="parentalSafeSearchSwitch"): a REAL
  //      write control, GET/POST /cgi-bin/api/safe-search. Simple boolean on/off (unlike
  //      Bedtime's enabled-vs-active split) — this control DOES optimistically flip, same
  //      pattern as Guest Wi-Fi/Ad Blocking's switches. Honest disclosure, shown in the
  //      description text: this is a real, network-wide setting despite sitting on a
  //      specific child's page in the mockup — DNS-level filtering has no per-device split
  //      in this environment (docker/facts.md Section 17). ----
  function setParentalSafeSearchVisual(sw, descEl, enabled){
    sw.classList.toggle('on', enabled);
    sw.setAttribute('aria-checked', enabled ? 'true' : 'false');
    if(descEl) setEscapedText(descEl, 'Filters results on Google, Bing, YouTube & DuckDuckGo · applies network-wide');
  }

  async function renderParentalSafeSearchScreen(){
    const myRenderId = state.parentalSafeSearchRenderId;
    const sw = document.getElementById('parentalSafeSearchSwitch');
    if(!sw) return;
    const row = sw.closest('.setting-row');
    const descEl = row ? row.querySelector('.sr-main span') : null;
    const data = await fetchRouterApi('/cgi-bin/api/safe-search');
    if(state.screen !== 'parental' || state.parentalSafeSearchRenderId !== myRenderId) return;
    if(data && typeof data === 'object'){
      setParentalSafeSearchVisual(sw, descEl, !!data.enabled);
    }
    // Switch left enabled even on failure — a click still safely round-trips through
    // fetchRouterApiWithStatus and reverts cleanly (see handleParentalSafeSearchClick),
    // same reasoning as every other real switch in this file.
  }

  async function handleParentalSafeSearchClick(sw){
    if(sw.dataset.pending === 'true') return;
    const row = sw.closest('.setting-row');
    const descEl = row ? row.querySelector('.sr-main span') : null;
    const wasOn = sw.classList.contains('on');
    const nextOn = !wasOn;
    sw.dataset.pending = 'true';
    sw.classList.add('pending');
    setParentalSafeSearchVisual(sw, descEl, nextOn); // optimistic flip
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/safe-search', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({enabled: nextOn})
    }, 3000);
    sw.dataset.pending = 'false';
    sw.classList.remove('pending');
    if(result === null || !result.ok){
      setParentalSafeSearchVisual(sw, descEl, wasOn); // revert
      let notice = row ? row.nextElementSibling : null;
      if(!notice || !notice.classList || !notice.classList.contains('api-fallback-notice')){
        notice = document.createElement('div');
        notice.className = 'api-fallback-notice';
        if(row) row.insertAdjacentElement('afterend', notice);
      }
      if(notice.dataset.removeTimer) clearTimeout(Number(notice.dataset.removeTimer));
      const msg = (result && result.data && result.data.error) ? result.data.error
        : (result === null ? "Can't reach router — Safe Search not changed." : ('Request failed (status '+result.status+') — Safe Search not changed.'));
      setEscapedText(notice, msg);
      notice.dataset.removeTimer = setTimeout(()=>{ if(notice.parentElement) notice.remove(); }, 4000);
    }
  }
```

- [ ] **Step 4: Wire the dispatch points**

`render()`: add alongside the other dispatch lines:
```js
      if(state.screen === 'parental'){ state.parentalSafeSearchRenderId++; renderParentalSafeSearchScreen(); }
```

Global click handler — add a `sw.id === 'parentalSafeSearchSwitch'` check in the existing chain of specific-id checks in the `.switch` branch:
```js
      if(sw.id === 'parentalSafeSearchSwitch'){ handleParentalSafeSearchClick(sw); return; }
```

- [ ] **Step 5: Verify against the live VM**

No browser available — verify via grep-confirms, `node --check` on the extracted `<script>`, a fresh valid JSON re-parse of `screens` (48 keys), careful manual code tracing, and direct curl exercise of the real `/api/safe-search` endpoint. Confirm your edit didn't touch anything else on the `parental` screen (this is the first wave to add any id to it — confirm the diff is a single, minimal id addition). Clean up any test state left toggled on the VM afterward.

- [ ] **Step 6: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Parental Controls' Safe Search toggle to a real setting"
```

---

### Task 3: `/api/blocked-sites` endpoint (GET list + POST add, domain-only)

**Files:**
- Create: `docker/provision/www/api/blocked-sites`
- Create: `docker/provision/17-provision-blocked-sites-api.sh` (a NEW, separate provisioning script for this second feature — do not fold it into `16-provision-safe-search-api.sh` just because both endpoints share the same `/etc/dnsmasq.blocklist.d` directory; every prior wave has kept one provisioning script per endpoint, and this wave keeps that convention)
- Modify: `docker/README.md` (Provisioning section: add step 17)

- [ ] **Step 1: Write the endpoint**

```lua
#!/usr/bin/lua
-- /api/blocked-sites — GET (list) + POST (add, idempotent per domain). Real
-- per-domain DNS blocking for the Parental Controls screen's "Custom
-- blocked sites" list, reusing Ad Blocking's own literal mechanism
-- (address=/domain/0.0.0.0) confirmed live in docker/facts.md Section 17 —
-- adapted here to a dynamic, user-supplied list instead of Ad Blocking's own
-- fixed 3-domain one.
--
-- GET response shape: [{"domain":"example.com"}, ...]
-- POST body: {"domain": "<domain>"} -> {"ok": true, "domain": "<domain>"}
--
-- === File ownership — same critical rule as safe-search ===
-- Manages its OWN files (custom-<safe-id>.conf, one per added domain)
-- inside /etc/dnsmasq.blocklist.d — the same directory Ad Blocking
-- (blocklist.conf) and Safe Search (safesearch.conf) already use, never
-- touching either of those files or the confdir uci option.
--
-- === Domain-only, explicit rejection of IP-shaped input ===
-- The screen's own input placeholder ("e.g. example.com or 203.0.113.4")
-- implies domain-OR-IP entry, but IP-based blocking needs a different
-- (firewall-based) mechanism — out of scope this wave. An IP-shaped input
-- is rejected with ITS OWN distinct error message, not silently treated as
-- an invalid domain, so a user isn't left guessing why "203.0.113.4" didn't
-- work.
--
-- === Domain validation ===
-- A reasonably strict domain-shape check (dot-separated alphanumeric/hyphen
-- labels, at least one dot, no leading/trailing hyphen per label) — this is
-- validated BEFORE it's used to derive a filename or interpolated into any
-- shell command, and every shell interpolation also goes through
-- shell_quote() as defense in depth (the same double-layered discipline
-- device-pause/qos-priority/device-bedtime already established — a validated
-- domain can only ever contain filename-safe, shell-safe characters, so this
-- endpoint never accepts a value that could reach a shell command unquoted
-- and unvalidated).

local BLOCKLIST_DIR = "/etc/dnsmasq.blocklist.d"

local function run(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return "" end
  local out = p:read("*a") or ""
  p:close()
  return (out:gsub("%s+$", ""))
end

local function shell_quote(s)
  s = tostring(s or "")
  s = s:gsub('[\1-\9\11-\31]', '')
  s = s:gsub('[\n\r]', ' ')
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function json_escape(s)
  if s == nil then return "" end
  s = tostring(s)
  s = s:gsub('[\\"\n\r\t]', {
    ['\\'] = '\\\\', ['"'] = '\\"', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
  })
  s = s:gsub('[\1-\31]', '')
  return s
end

local function is_ipv4_shaped(v)
  local a, b, c, d = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return false end
  for _, octet in ipairs({a, b, c, d}) do
    local n = tonumber(octet)
    if not n or n < 0 or n > 255 then return false end
  end
  return true
end

-- Dot-separated labels: letters/digits/hyphens, no leading/trailing hyphen
-- per label, at least two labels (a real dot), reasonable overall length.
local function is_valid_domain(v)
  if type(v) ~= "string" then return false end
  v = v:lower()
  if #v == 0 or #v > 253 then return false end
  if not v:match("^[%w]([%w%-]*[%w])?(%.[%w]([%w%-]*[%w])?)+$") then return false end
  return not is_ipv4_shaped(v)
end

local function domain_to_filename(domain)
  return BLOCKLIST_DIR .. "/custom-" .. domain:lower():gsub("[%.%-]", "_") .. ".conf"
end

-- Scans the blocklist directory for this project's own custom-*.conf files
-- (never blocklist.conf or safesearch.conf) and returns the list of domains
-- by parsing each file's actual address=/domain/0.0.0.0 line — the domain
-- is read back from FILE CONTENT, not decoded from the filename, avoiding
-- any lossy-filename-encoding concern.
local function list_custom_domains()
  local files = run("ls " .. BLOCKLIST_DIR .. " 2>/dev/null")
  local domains = {}
  for filename in files:gmatch("[^\r\n]+") do
    if filename:match("^custom%-.-%.conf$") then
      local f = io.open(BLOCKLIST_DIR .. "/" .. filename, "r")
      if f then
        local content = f:read("*a")
        f:close()
        local domain = content:match("^address=/(.-)/0%.0%.0%.0")
        if domain then domains[#domains + 1] = domain end
      end
    end
  end
  return domains
end

local function domain_already_blocked(domain)
  for _, d in ipairs(list_custom_domains()) do
    if d == domain then return true end
  end
  return false
end

local function read_request_body()
  local len = tonumber(os.getenv("CONTENT_LENGTH") or "")
  if len and len > 0 then return io.read(len) or "" end
  return io.read("*a") or ""
end

local function json_parse_flat_object(s)
  local obj = {}
  if type(s) ~= "string" then return obj end
  local i, len = 1, #s
  local function skip_ws() while i <= len and s:sub(i, i):match("%s") do i = i + 1 end end
  local function parse_string()
    i = i + 1
    local buf = {}
    local escapes = { ['"']='"', ['\\']='\\', ['/']='/', ['n']='\n', ['r']='\r', ['t']='\t', ['b']='\b', ['f']='\f' }
    while i <= len do
      local c = s:sub(i, i)
      if c == '"' then i = i + 1; return table.concat(buf)
      elseif c == '\\' then
        local nc = s:sub(i + 1, i + 1)
        if nc == 'u' then i = i + 6
        elseif escapes[nc] then buf[#buf+1] = escapes[nc]; i = i + 2
        else buf[#buf+1] = nc; i = i + 2 end
      else buf[#buf+1] = c; i = i + 1 end
    end
    return table.concat(buf)
  end
  skip_ws()
  if s:sub(i, i) ~= '{' then return obj end
  i = i + 1
  skip_ws()
  if s:sub(i, i) == '}' then return obj end
  while i <= len do
    skip_ws()
    if s:sub(i, i) ~= '"' then break end
    local key = parse_string()
    skip_ws()
    if s:sub(i, i) ~= ':' then break end
    i = i + 1
    skip_ws()
    local val
    if s:sub(i, i) == '"' then val = parse_string()
    else
      local start = i
      while i <= len and not s:sub(i, i):match('[,}%s]') do i = i + 1 end
      val = s:sub(start, i - 1)
    end
    obj[key] = val
    skip_ws()
    if s:sub(i, i) == ',' then i = i + 1
    elseif s:sub(i, i) == '}' then i = i + 1; break
    else break end
  end
  return obj
end

local function send_headers(status)
  local reasons = { [400]="Bad Request", [405]="Method Not Allowed", [500]="Internal Server Error" }
  if status and status ~= 200 then
    print("Status: " .. status .. " " .. (reasons[status] or "Error"))
  end
  print("Content-Type: application/json\n")
end

local method = os.getenv("REQUEST_METHOD") or "GET"

if method == "GET" then
  local rows = {}
  for _, d in ipairs(list_custom_domains()) do
    rows[#rows + 1] = string.format('{"domain":"%s"}', json_escape(d))
  end
  send_headers(200)
  print("[" .. table.concat(rows, ",") .. "]")

elseif method == "POST" then
  local body = read_request_body()
  local req = json_parse_flat_object(body)
  local domain = req.domain
  if type(domain) == "string" then domain = domain:lower() end

  if type(domain) == "string" and is_ipv4_shaped(domain) then
    send_headers(400)
    print('{"ok":false,"error":"IP-address blocking is not supported yet — only domain names (e.g. example.com)"}')
  elseif not is_valid_domain(domain) then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: domain (e.g. example.com)"}')
  elseif domain_already_blocked(domain) then
    -- Idempotent: already blocked, nothing to do.
    send_headers(200)
    print(string.format('{"ok":true,"domain":"%s"}', json_escape(domain)))
  else
    local path = domain_to_filename(domain)
    local f = io.open(path, "w")
    local write_ok = false
    if f then
      f:write("address=/" .. domain .. "/0.0.0.0\n")
      f:close()
      write_ok = true
    end
    if not write_ok then
      send_headers(500)
      print('{"ok":false,"error":"failed to write block file for this domain"}')
    else
      run("/etc/init.d/dnsmasq restart")
      if domain_already_blocked(domain) then
        send_headers(200)
        print(string.format('{"ok":true,"domain":"%s"}', json_escape(domain)))
      else
        os.remove(path)
        send_headers(500)
        print('{"ok":false,"error":"block file write did not verify on readback; removed"}')
      end
    end
  end

else
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', json_escape(tostring(method))))
end
```

- [ ] **Step 2: Write the provisioning script**

Same deploy-and-verify-only shape as Task 1's script (and every other stateless-endpoint script). Deploy to `/www/cgi-bin/api/blocked-sites`, `chmod +x` + `ls -la`, verify with a real `curl -sf` GET expecting a JSON array shape.

- [ ] **Step 3: Run and verify against the live VM**

```bash
chmod +x docker/provision/17-provision-blocked-sites-api.sh
./docker/provision/17-provision-blocked-sites-api.sh
curl -s http://localhost:8081/cgi-bin/api/blocked-sites   # expect [] (or existing state if re-run)
curl -s -X POST -H 'Content-Type: application/json' -d '{"domain":"extra-homework-site.com"}' http://localhost:8081/cgi-bin/api/blocked-sites
curl -s http://localhost:8081/cgi-bin/api/blocked-sites   # expect [{"domain":"extra-homework-site.com"}]
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "nslookup extra-homework-site.com 127.0.0.1"
```
Expected: a real `0.0.0.0` block result. Confirm Ad Blocking's `blocklist.conf` and Safe Search's `safesearch.conf` (if you toggled it on in Task 1's testing) are both still completely intact and functioning (`nslookup doubleclick.net`, `nslookup www.google.com` if safesearch is on). Test idempotency (POST the same domain twice, confirm exactly one `custom-*.conf` file for it). Test IP-rejection (`{"domain":"203.0.113.4"}"` → the DISTINCT IP-specific 400 error, not the generic domain-invalid one). Test malformed-domain 400 (empty string, `"not a domain"`, a string with spaces). Test 405. Add a second, different domain and confirm both coexist correctly in the GET list. Clean up all test block files from the VM afterward (`rm /etc/dnsmasq.blocklist.d/custom-*.conf; /etc/init.d/dnsmasq restart`).

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/blocked-sites docker/provision/17-provision-blocked-sites-api.sh docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/blocked-sites endpoint (real per-domain DNS blocking)"
```

---

### Task 4: Frontend — wire Parental Controls' Custom blocked sites list + Add

**Files:**
- Modify: `sadd-website.html` (the `parental` entry in `screens`, new JS, `render()` dispatch, the global click handler, `state`)

The add-form (input + "+ Add" button) is already static markup on this screen — no NEW form needs to be built (unlike Tasks 2/4 of Wave 6, which had to add a hidden form). This task only needs to add ids to the EXISTING input/button and wire them up.

- [ ] **Step 1: Add ids to the existing Custom-blocked-sites markup in `screens['parental']`**

Find `<div class="sec-label mt-24">Custom blocked sites</div><div style="display:flex;gap:8px;margin-bottom:10px;"><input class="input" placeholder="e.g. example.com or 203.0.113.4" style="flex:1;"><button class="btn btn-secondary" style="width:auto;padding:9px 16px;">+ Add</button></div><div class="tech-row"><div class="tr-label">extra-homework-site.com</div><div class="tr-val">Blocked</div></div><button class="btn btn-ghost" style="width:auto;padding:8px 0;font-size:12px;margin-bottom:8px;">Export list</button>` and make these targeted changes:
1. Add `id="parentalBlockedSiteInput"` to the `<input>`.
2. Add `id="parentalBlockedSiteAddBtn"` to the `+ Add` `<button>`.
3. Wrap the existing demo `.tech-row` in a container: `<div id="parentalBlockedSitesList"><div class="tech-row">...</div></div>`.
4. Add `id="parentalBlockedSiteError"` on a new small error element right after the input row: `<div id="parentalBlockedSiteError" style="display:none;color:#dc2626;font-size:12px;margin-bottom:8px;"></div>` (insert it between the input-row `</div>` and the wrapped list `<div id="parentalBlockedSitesList">`).

Leave "Export list" completely untouched (out of scope, per the design spec).

- [ ] **Step 2: Add `state.parentalBlockedSitesRenderId`**

Add `, parentalBlockedSitesRenderId: 0` to `state`.

- [ ] **Step 3: Add the render/handler JS**

Insert after Task 2's `handleParentalSafeSearchClick`'s closing `}`:

```js
  // ---- Parental Controls "Custom blocked sites": real list + add, POST
  //      /cgi-bin/api/blocked-sites. The add-form is already static markup on this screen
  //      (id="parentalBlockedSiteInput"/"parentalBlockedSiteAddBtn") — no new form to
  //      reveal/hide, unlike every other add-flow in this file. No delete affordance in
  //      the mockup, so none is built (mirrors Priority Devices/WireGuard Clients). ----
  function renderParentalBlockedSiteRow(entry){
    return '<div class="tech-row"><div class="tr-label">'+escapeHtml(entry.domain)+'</div><div class="tr-val">Blocked</div></div>';
  }

  async function renderParentalBlockedSitesScreen(){
    const myRenderId = state.parentalBlockedSitesRenderId;
    const data = await fetchRouterApi('/cgi-bin/api/blocked-sites');
    if(state.screen !== 'parental' || state.parentalBlockedSitesRenderId !== myRenderId) return;
    const listEl = document.getElementById('parentalBlockedSitesList');
    const addBtn = document.getElementById('parentalBlockedSiteAddBtn');
    if(!listEl) return;
    if(Array.isArray(data)){
      listEl.innerHTML = data.map(renderParentalBlockedSiteRow).join('');
      if(addBtn) addBtn.disabled = false;
    } else {
      if(addBtn) addBtn.disabled = true;
      if(!listEl.querySelector('.api-fallback-notice')){
        const notice = document.createElement('div');
        notice.className = 'api-fallback-notice';
        notice.textContent = "Can't reach router — showing demo data";
        listEl.insertAdjacentElement('afterbegin', notice);
      }
    }
  }

  async function submitParentalBlockedSite(){
    const inputEl = document.getElementById('parentalBlockedSiteInput');
    const addBtn = document.getElementById('parentalBlockedSiteAddBtn');
    const errEl = document.getElementById('parentalBlockedSiteError');
    const domain = inputEl ? inputEl.value.trim() : '';
    if(errEl){ errEl.style.display = 'none'; errEl.textContent = ''; }
    if(!domain){
      if(errEl){ errEl.style.display = 'block'; setEscapedText(errEl, 'Enter a domain to block.'); }
      return;
    }
    if(addBtn) addBtn.disabled = true;
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/blocked-sites', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({domain})
    }, 3000);
    if(addBtn) addBtn.disabled = false;
    if(result && result.ok){
      if(inputEl) inputEl.value = '';
      state.parentalBlockedSitesRenderId++;
      renderParentalBlockedSitesScreen();
    } else if(errEl){
      const msg = (result && result.data && result.data.error) ? result.data.error
        : (result === null ? "Can't reach router — site not added." : ('Request failed (status '+result.status+') — site not added.'));
      errEl.style.display = 'block';
      setEscapedText(errEl, msg);
    }
  }
```

- [ ] **Step 4: Wire the dispatch points**

`render()`: add alongside the other `parental` dispatch line from Task 2:
```js
      if(state.screen === 'parental'){ state.parentalBlockedSitesRenderId++; renderParentalBlockedSitesScreen(); }
```
(This can be folded into the SAME `if(state.screen === 'parental'){...}` block Task 2 added, alongside its own `state.parentalSafeSearchRenderId++`/`renderParentalSafeSearchScreen()` call — both real-data overlays for this screen fire together, matching the established "one `if` block per screen, multiple independent calls inside it" pattern used elsewhere, e.g. `advwireguard`'s two calls.)

Global click handler — add near the other add-form branches (Firewall's `fwAddSubmit`, WireGuard's `wgAddSubmit`, QoS's `qosAddSubmit`):
```js
    const parentalBlockedSiteAddBtn = e.target.closest('#parentalBlockedSiteAddBtn');
    if(parentalBlockedSiteAddBtn){
      if(!parentalBlockedSiteAddBtn.disabled) submitParentalBlockedSite();
      return;
    }
```

- [ ] **Step 5: Verify against the live VM**

Same static-verification approach as every prior frontend task. Clean up any test domain added to the VM afterward.

- [ ] **Step 6: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Parental Controls' Custom blocked sites list + Add"
```

---

### Task 5: Documentation closeout

**Files:**
- Modify: `docker/README.md` (Provisioning section, Known Limitations)
- Modify: `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` (Architecture diagram, Components, Frontend changes, Testing, Security posture, Full roadmap sections)

- [ ] **Step 1: `docker/README.md`**

Confirm steps 16 and 17 are fully documented (added incrementally by Tasks 1/3) — read the file to check, don't assume; Wave 6 and Wave 7's own closeouts both found a sibling endpoint left completely undocumented despite the "incremental" assumption, so verify this didn't happen again. Add Known Limitations bullets: (a) Safe Search and Custom blocked sites are both real but NETWORK-WIDE, not scoped to any individual child's devices, despite the mockup's per-child page placement — the same disclosure `docker/facts.md` §17 documents; (b) Custom blocked sites is domain-only — an IP-shaped entry is rejected with its own distinct error, not silently mishandled; (c) neither feature has a remove/delete affordance in the UI (matches Priority Devices/WireGuard Clients' precedent) — real state can only be removed by hand over SSH this wave. Update the write-endpoint count (nine → eleven: `+safe-search`, `+blocked-sites`) — verify the actual current count yourself by listing `docker/provision/www/api/` and checking each file's method dispatch, don't trust a number from this prompt.

- [ ] **Step 2: Design spec**

Mirror Wave 7's closeout pattern: a dated Wave 8 paragraph in Testing (what was proven real and how — the real CNAME rewrite confirmed live via nslookup, the real per-domain block confirmed live, the confdir-multi-file-coexistence finding and how testing specifically confirmed Ad Blocking's own state was never disturbed by either new feature); `### Safe Search API` / `### Blocked Sites API` subsections in Components; extend the Frontend-changes running screen-count sentence (this wave adds a NEW screen to the tally for the first time — `parental` was never wired by any prior wave, unlike Wave 7's Bedtime which was a second control on an already-counted screen — get this right); update the Architecture diagram comment; update the Security-posture write-endpoint count; flip Wave 8 from "(in progress)" to "(done)" in the Goal section and the Full roadmap section.

- [ ] **Step 3: Commit**

```bash
git add docker/README.md docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: Wave 8 closeout — README limitations, design spec updates"
```

---

## After all tasks

Dispatch one final whole-wave integration-level code-quality review (a fresh `superpowers:code-reviewer` subagent, given the full diff across all 5 tasks — pay particular attention to whether EITHER new endpoint ever touches Ad Blocking's `blocklist.conf` or the `confdir` uci option, directly or indirectly, and whether the two new endpoints genuinely agree with each other and with Ad Blocking on every shared convention), fix anything it raises, commit, then report Wave 8 complete using the same format every prior wave's completion summary used.
