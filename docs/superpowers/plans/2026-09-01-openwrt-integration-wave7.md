# OpenWrt Integration — Wave 7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Per-Device Controls' "Bedtime" toggle real — a genuine, cron-enforced recurring schedule that blocks and unblocks a specific device's internet access twice daily, not the profile-level feature Wave 5's original scoping assumed it needed.

**Architecture:** Same shape as Wave 5's Pause-internet feature (which this directly extends): a `src=lan`/`dest=wan` per-MAC `uci firewall` REJECT rule, this time made persistent (not auto-expiring) and toggled active/inactive by a new cron sweep keyed on time-of-day rather than a fixed timestamp — using `uci firewall` rule sections' own `enabled` option (confirmed live, `docker/facts.md` §16, to be honored by `fw4` independently of the section's existence). Every command below was proven live against the running VM before this plan was written.

**Tech Stack:** Unchanged — OpenWrt 23.05.5 Lua CGI, `uci`/`fw4`/cron, vanilla JS/HTML/CSS in `sadd-website.html`, no build step.

---

## Before you start (context every task shares)

- VM: `cd docker && docker compose up -d --build`, wait for `docker inspect --format='{{.State.Health.Status}}' openwrt` to report `healthy`.
- SSH: `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost`. SCP requires `-O`.
- Git identity: `GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com"`.
- **Read `docker/provision/www/api/device-pause` in full first** — every helper (`run`, `shell_quote`, `json_escape`, `read_request_body`, `json_parse_flat_object`, `send_headers`), the stable-id-rename discipline, and the `src=lan`/`dest=wan` rule shape this wave's new endpoint reuses verbatim come from there. Also read `docker/provision/lib/devpause-sweep.sh` in full — this wave's new sweep script mirrors its structure (fresh-scan-per-iteration where relevant, explicit `uci commit`/`fw4 reload` failure logging, the deliberate absence of top-level `set -e`) but solves a different condition (time-window membership, not expiry).
- **Timezone honesty, non-negotiable**: this VM has no configured timezone (confirmed live, `docker/facts.md` §16 — UTC only, no `zonename` set). The sweep script and every piece of documentation/UI copy this wave touches must describe the schedule as a fixed UTC 21:00–07:00 window, never claim or imply it tracks real local time.
- **Known shell gotcha already resolved, do not reintroduce it**: `date -u +%H`'s zero-padded output (e.g. `"08"`, `"09"`) breaks POSIX arithmetic expansion (`$((HOUR))`) via octal misinterpretation — confirmed live to error on this VM's busybox ash, which also does NOT support the `10#$HOUR` base-prefix workaround (confirmed live: `ash: arithmetic syntax error`). The fix, also confirmed live: use plain `[ "$HOUR" -ge 21 ]`/`[ "$HOUR" -lt 7 ]` string-based numeric comparisons — `test`/`[`'s `-ge`/`-lt` parse the zero-padded string correctly with no octal reinterpretation. **Never wrap `$HOUR` in `$(( ))` anywhere in this wave's code.**
- After all tasks, dispatch one final whole-wave integration-level code-quality review, fix anything it raises, then report Wave 7 complete.

---

### Task 1: Provision the Bedtime cron sweep

**Files:**
- Create: `docker/provision/lib/bedtime-sweep.sh` (deployed onto the VM as `/usr/bin/bedtime-sweep.sh`)
- Create: `docker/provision/15-provision-bedtime-api.sh`
- Modify: `docker/README.md` (Provisioning section: add step 15)

This is the baseline-state half of the feature: a script that runs every 5 minutes on the VM and reconciles every `bedtime-<mac>` firewall rule's `enabled` option to match whether the current UTC hour falls in the 21:00–07:00 window. Real device-pause creation (this wave's Task 2, not yet built when this task starts) is what creates these rules in the first place — this sweep only ever adjusts the `enabled` flag on rules that already exist, mirroring `devpause-sweep.sh`'s own "provision the enforcement half first, safe to run standalone" precedent.

- [ ] **Step 1: Write the sweep script**

```sh
#!/bin/sh
# /usr/bin/bedtime-sweep.sh — run every 5 minutes by cron (see
# 15-provision-bedtime-api.sh). Finds every uci firewall rule this project
# created for a per-device Bedtime schedule (named `bedtime-<mac with colons
# stripped>`) and sets its OWN `enabled` uci option to match whether the
# current UTC hour falls in the fixed 21:00-07:00 window — NOT any
# particular real-world local time. This VM has no configured timezone
# (confirmed live, docker/facts.md Section 16: `date` shows UTC, `uci get
# system.@system[0].zonename` returns "Entry not found") — there is no
# concept of "the family's own time" anywhere in this environment or the
# mockup to read a real local schedule from, so a fixed UTC window is the
# honest, disclosed approximation this feature uses, not a bug.
#
# `uci firewall` rule sections support a genuine `enabled` option, distinct
# from the section's existence, that fw4 honors to skip emitting the rule
# entirely without deleting it — confirmed live before this script was
# written (docker/facts.md Section 16): `enabled='0'` + `fw4 reload` makes
# the rule genuinely absent from `nft list ruleset`; `enabled='1'` brings the
# exact same rule back. This is what lets a Bedtime-configured device's rule
# PERSIST across day and night (recording "Bedtime is set up for this
# device") while only actually blocking during the scheduled window.
#
# Real device-pause creation (a separate feature, Wave 5) and real
# device-bedtime creation (this wave's /cgi-bin/api/device-bedtime, a
# different task in this same plan) are what create these rules in the
# first place — this script only ever adjusts an existing rule's `enabled`
# flag, never creates or deletes a rule itself. Safe to run standalone
# before any bedtime rule exists yet (the for-loop below simply iterates
# zero times).
#
# Known shell gotcha this script deliberately avoids (confirmed live before
# writing this script): `date -u +%H` is zero-padded (e.g. "08", "09"),
# which breaks arithmetic expansion (`$((HOUR))`) via octal
# misinterpretation on this VM's busybox ash — and ash does NOT support the
# usual `10#$HOUR` base-prefix workaround either (confirmed live: "ash:
# arithmetic syntax error"). This script therefore NEVER wraps $HOUR in
# `$(( ))` — POSIX `test`/`[`'s `-ge`/`-lt` numeric comparisons parse a
# zero-padded string correctly with no such reinterpretation, confirmed
# live against both "08" and "09".
#
# No top-level `set -e`, deliberately, same reasoning as devpause-sweep.sh:
# one section's uci get/set failing shouldn't cancel the sweep for every
# other section this tick. uci commit/fw4 reload failures are explicitly
# logged rather than silently swallowed.

HOUR="$(date -u +%H)"
if [ "$HOUR" -ge 21 ] || [ "$HOUR" -lt 7 ]; then
  WANT=1
else
  WANT=0
fi

CHANGED=0
for id in $(uci show firewall | grep "\.name='bedtime-" | sed -n "s/^firewall\.\([^.]*\)\.name=.*/\1/p"); do
  current=$(uci -q get "firewall.${id}.enabled")
  if [ "$current" != "$WANT" ]; then
    logger -t bedtime-sweep "firewall.${id}: enabled ${current:-<unset>} -> ${WANT} (UTC hour ${HOUR})"
    uci set "firewall.${id}.enabled=${WANT}"
    CHANGED=1
  fi
done

if [ "$CHANGED" = "1" ]; then
  if uci commit firewall; then
    if ! fw4 reload >/dev/null 2>&1; then
      logger -t bedtime-sweep "ERROR: fw4 reload failed after updating bedtime rule enabled state"
    fi
  else
    logger -t bedtime-sweep "ERROR: uci commit firewall failed after updating bedtime rule enabled state"
  fi
fi
```

- [ ] **Step 2: Write the provisioning script**

Base on `docker/provision/13-provision-devpause-api.sh`'s current full shape (read it first — it was itself refined through a code-review fix cycle, so match its CURRENT actual `SSH_OPTS`/variable-name/deploy idiom, not a guess). It should:
1. `scp -O` the sweep script to `/usr/bin/bedtime-sweep.sh`, `chmod +x` + `ls -la` (with the established `-O`-required explanatory comment).
2. Idempotently seed a `*/5 * * * * /usr/bin/bedtime-sweep.sh` line into `/etc/crontabs/root` (a `grep -qF` guard before appending, same as `13-provision-devpause-api.sh`'s own crontab-seeding step — cron itself should already be running from Wave 5's provisioning, but verify with `pgrep crond` defensively anyway, same discipline).
3. Print a clear final "done" message.

- [ ] **Step 3: Run and verify against the live VM**

```bash
mkdir -p docker/provision/lib   # already exists from Wave 5; harmless if so
chmod +x docker/provision/15-provision-bedtime-api.sh
./docker/provision/15-provision-bedtime-api.sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "cat /etc/crontabs/root; pgrep crond"
```
Expected: the crontab shows both `* * * * * /usr/bin/devpause-sweep.sh` (Wave 5) and the new `*/5 * * * * /usr/bin/bedtime-sweep.sh` line, and `pgrep crond` returns a real PID.

Then fault-inject to prove the sweep genuinely works, in BOTH directions — this is the one thing that actually needs live proof, not just code reading:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
  uci add firewall rule
  uci set firewall.@rule[-1].name='bedtime-aabbccddeeff'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].src_mac='aa:bb:cc:dd:ee:ff'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].target='REJECT'
  uci set firewall.@rule[-1].enabled='0'
  uci commit firewall
  fw4 reload
  /usr/bin/bedtime-sweep.sh
  date -u +%H
  uci get firewall.@rule[-1].enabled
"
```
Run this once with the VM's current real UTC hour in-window (if it's not currently between 21:00-07:00 UTC when you run this, either wait for a real boundary or temporarily fake it for the test — e.g. `date -u -s '23:00'` if this VM's `date` supports `-s`, confirm first, then restore the real time afterward with `date -u -s <original time>` — do NOT leave the VM's clock permanently altered) and confirm the sweep flips `enabled` from `0` to `1` when the hour is in-window, and leaves/flips it to `0` when out-of-window. Confirm via `nft list ruleset | grep aa:bb:cc:dd:ee:ff` that the real REJECT rule's presence/absence in `forward_lan` matches the `enabled` value at each step. Clean up the test rule afterward (`uci -q delete firewall.@rule[-1]; uci commit firewall; fw4 reload`) and restore the VM's real clock if you changed it.

- [ ] **Step 4: Commit**

```bash
git add docker/provision/lib/bedtime-sweep.sh docker/provision/15-provision-bedtime-api.sh docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): provision a real cron sweep for per-device Bedtime schedules"
```

---

### Task 2: `/api/device-bedtime` endpoint (GET status + POST create/remove)

**Files:**
- Create: `docker/provision/www/api/device-bedtime`
- Modify: `docker/provision/15-provision-bedtime-api.sh` (append deploy-and-verify)

- [ ] **Step 1: Write the endpoint**

Design (adapted from `device-pause`'s shape, with the same helpers and stable-id-rename discipline; no expiry/cron-sweep concept lives IN this endpoint — that's `bedtime-sweep.sh`'s job, this endpoint only creates/reads/removes the rule):

- `GET /cgi-bin/api/device-bedtime?mac=<mac>` → `{"enabled": true|false, "active": true|false}`. `enabled` = does a `bedtime-<mac>` rule exist at all (the schedule is configured for this device, regardless of whether it's currently day or night). `active` = is it CURRENTLY enforcing (`uci get firewall.<id>.enabled == "1"`) — i.e. is the device blocked *right now*. Both `false` if no such rule exists.
- `POST /cgi-bin/api/device-bedtime` body `{"mac": "<mac>", "enabled": true|false}`:
  - `enabled: true` → create the rule if it doesn't already exist (idempotent no-op success if it does): `src=lan`, `src_mac=<mac>`, `dest=wan`, `target=REJECT`, stable-renamed id (`bedtime_<mac-no-colons>` — underscore, matching `device-pause`/`qos-priority`'s established uci-section-ids-can't-contain-hyphens precedent), and its own `enabled` option set based on the CURRENT UTC hour at creation time (in-window → `'1'`, so the schedule takes effect immediately if it's already night when the user turns it on, not just at the next sweep tick; out-of-window → `'0'`) — read via `date -u +%H` and the same `[ -ge ]`/`[ -lt ]` comparison `bedtime-sweep.sh` uses (never `$(( ))`). Verified via readback (matching `src_mac`/`dest`/`target`, plus the just-computed `enabled` value), committed, `fw4 reload`.
  - `enabled: false` → delete the rule if it exists (idempotent no-op success if it doesn't).
  - Returns `{"ok":true,"enabled":<bool>,"active":<bool>}` reflecting the resulting state.
- 400 for an invalid/missing `mac`, or `enabled` present-but-not-boolean, or `enabled` missing entirely. 405 for anything but GET/POST.

```lua
#!/usr/bin/lua
-- /api/device-bedtime — GET (status) + POST (create/remove a Bedtime
-- schedule). Real per-device recurring block for the Per-Device Controls
-- screen's "Bedtime" toggle. The recurring enforcement itself is
-- docker/provision/lib/bedtime-sweep.sh's job (a cron job, run every 5
-- minutes — see docker/provision/15-provision-bedtime-api.sh); this
-- endpoint only ever creates, reads, or removes the rule the sweep acts on.
--
-- GET /cgi-bin/api/device-bedtime?mac=<mac>
--   -> {"enabled": true|false, "active": true|false}
--   enabled: is a Bedtime schedule configured for this device at all.
--   active: is it blocking RIGHT NOW (this device's rule's own `enabled`
--   uci option reads "1"). Both false if no rule exists for this MAC.
--
-- POST /cgi-bin/api/device-bedtime  body: {"mac": "<mac>", "enabled": true|false}
--   -> {"ok": true, "enabled": <bool>, "active": <bool>}
--
-- === Rule shape ===
-- Same src=lan/dest=wan REJECT shape device-pause already established
-- (docker/facts.md Section 14) for "block this device's outbound traffic,
-- not just its access to the router itself" — confirmed correct again here,
-- unchanged.
--
-- === Timezone honesty — same disclosure as bedtime-sweep.sh ===
-- This VM has no configured timezone (confirmed live, docker/facts.md
-- Section 16). "Enabled right now" reflects a fixed UTC 21:00-07:00 window,
-- not any real-world local time. When POST creates a new rule, this
-- endpoint computes the CURRENT hour itself (not left at some default) so
-- the schedule takes effect immediately if it's already nighttime when the
-- user turns Bedtime on, rather than waiting for the next 5-minute sweep
-- tick to notice.
--
-- === Stable section ids ===
-- Every created rule is immediately uci-renamed to a stable id
-- (bedtime_<mac-no-colons>, underscore — uci section identifiers can't
-- contain a hyphen, confirmed live in docker/facts.md Section 14; the
-- hyphenated form is kept for the `.name` OPTION's value, which
-- bedtime-sweep.sh's `grep "\.name='bedtime-"` scan depends on matching
-- exactly), verified via section_type() before any field write — same
-- discipline as device-pause/qos-priority, closing the same
-- positional-addressing race those endpoints' own investigations
-- (and, for wireguard-clients, a real found-and-fixed command-injection
-- bug) established the importance of.
--
-- === Security note ===
-- Like device-pause and qos-priority, this endpoint NEVER accepts a
-- client-supplied section id — the id is always derived internally from an
-- already-regex-validated `mac`. See docker/README.md's file note for
-- wireguard-clients for the full command-injection finding this design
-- deliberately avoids by construction.
--
-- === Known shell gotcha this Lua file does NOT hit ===
-- bedtime-sweep.sh's header comment documents a real busybox-ash arithmetic
-- gotcha with zero-padded `date -u +%H` output. This endpoint reads the
-- hour via Lua's own os.date/tonumber (not a shell arithmetic expression),
-- which has no equivalent octal-parsing pitfall — tonumber("08") in Lua
-- correctly returns 8, confirmed live before shipping this file.

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

local function is_valid_mac(v)
  if type(v) ~= "string" then return false end
  return v:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

local function mac_to_rule_name(mac) return "bedtime-" .. mac:lower():gsub(":", "") end
local function mac_to_section_id(mac) return "bedtime_" .. mac:lower():gsub(":", "") end

-- Current UTC hour "should this device currently be blocked" per the fixed
-- window bedtime-sweep.sh also uses. os.date("!*t") returns a UTC-based
-- table (the "!" prefix forces UTC, matching bedtime-sweep.sh's `date -u`);
-- .hour is already a real Lua number, no string-parsing gotcha to guard
-- against here (see header comment).
local function currently_in_window()
  local hour = os.date("!*t").hour
  return hour >= 21 or hour < 7
end

local function list_bedtime_sections()
  local output = run("uci show firewall")
  local order, is_rule, fields = {}, {}, {}
  for line in output:gmatch("[^\n]+") do
    local lhs, rhs = line:match("^(.-)=(.*)$")
    if lhs and rhs then
      local rest = lhs:match("^firewall%.(.+)$")
      if rest then
        local dot = rest:find("%.")
        if dot then
          local id, field = rest:sub(1, dot - 1), rest:sub(dot + 1)
          if is_rule[id] then
            local val = rhs:match("^'(.-)'$")
            fields[id][field] = val or rhs
          end
        else
          local id = rest
          local typ = rhs:match("^'?(.-)'?$")
          if typ == "rule" and not is_rule[id] then
            is_rule[id] = true; order[#order + 1] = id; fields[id] = {}
          end
        end
      end
    end
  end
  return order, fields
end

local function find_bedtime_rule(rule_name)
  local order, fields = list_bedtime_sections()
  for _, id in ipairs(order) do
    if fields[id].name == rule_name then return id, fields[id] end
  end
  return nil, nil
end

local function section_type(id) return run("uci get firewall." .. id) end

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
  local mac = nil
  do
    local qs = os.getenv("QUERY_STRING") or ""
    for pair in qs:gmatch("[^&]+") do
      local k, v = pair:match("^([^=]+)=(.*)$")
      if k == "mac" then
        mac = v:gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
      end
    end
  end
  if not is_valid_mac(mac) then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required query param: mac (must be AA:BB:CC:DD:EE:FF form)"}')
  else
    local _, fields = find_bedtime_rule(mac_to_rule_name(mac))
    send_headers(200)
    if fields then
      print(string.format('{"enabled":true,"active":%s}', fields.enabled == "1" and "true" or "false"))
    else
      print('{"enabled":false,"active":false}')
    end
  end

elseif method == "POST" then
  local body = read_request_body()
  local req = json_parse_flat_object(body)
  local mac = req.mac
  local enabled_req = req.enabled

  if not is_valid_mac(mac) then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: mac (must be AA:BB:CC:DD:EE:FF form)"}')
  elseif enabled_req ~= "true" and enabled_req ~= "false" then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: enabled (must be a JSON boolean true or false)"}')
  else
    local rule_name = mac_to_rule_name(mac)
    local want_enabled = enabled_req == "true"
    local existing_id = find_bedtime_rule(rule_name)

    if want_enabled then
      if existing_id then
        -- Idempotent: schedule already configured. Report its real current state.
        local _, fields = find_bedtime_rule(rule_name)
        send_headers(200)
        print(string.format('{"ok":true,"enabled":true,"active":%s}', fields.enabled == "1" and "true" or "false"))
      else
        local section_id = mac_to_section_id(mac)
        local active_now = currently_in_window()
        local create_failed = false
        local create_error = nil

        local anon = run("uci add firewall rule")
        if anon == "" or anon:find("[^%w_]") then
          create_failed = true
          create_error = "uci add firewall rule failed"
        else
          run("uci rename firewall." .. anon .. "=" .. section_id)
          if section_type(section_id) ~= "rule" then
            create_failed = true
            create_error = "uci rename to " .. section_id .. " failed: section not found under new name"
          end
        end

        if not create_failed then
          run("uci set firewall." .. section_id .. ".name=" .. shell_quote(rule_name))
          run("uci set firewall." .. section_id .. ".src=" .. shell_quote("lan"))
          run("uci set firewall." .. section_id .. ".src_mac=" .. shell_quote(mac))
          run("uci set firewall." .. section_id .. ".dest=" .. shell_quote("wan"))
          run("uci set firewall." .. section_id .. ".target=" .. shell_quote("REJECT"))
          run("uci set firewall." .. section_id .. ".enabled=" .. shell_quote(active_now and "1" or "0"))
        end

        local readback_ok = false
        if not create_failed then
          local order, all_fields = list_bedtime_sections()
          local f = all_fields[section_id]
          readback_ok = f and f.src_mac == mac and f.dest == "wan" and f.target == "REJECT"
            and f.enabled == (active_now and "1" or "0")
          if readback_ok then
            local dup_count = 0
            for _, id2 in ipairs(order) do
              if all_fields[id2].name == rule_name then dup_count = dup_count + 1 end
            end
            if dup_count ~= 1 then
              readback_ok = false
              create_error = "a concurrent request created a duplicate rule for this MAC"
            end
          else
            create_error = "failed to verify the Bedtime rule write"
          end
        end

        if not readback_ok then
          run("uci revert firewall")
          send_headers(500)
          print(string.format('{"ok":false,"error":"%s; reverted"}', json_escape(create_error or "failed to verify the Bedtime rule write")))
        else
          run("uci commit firewall")
          run("fw4 reload")
          send_headers(200)
          print(string.format('{"ok":true,"enabled":true,"active":%s}', active_now and "true" or "false"))
        end
      end
    else
      -- want_enabled == false: remove the schedule if present. Idempotent no-op if absent.
      if existing_id then
        run("uci -q delete firewall." .. shell_quote(existing_id))
        run("uci commit firewall")
        run("fw4 reload")
      end
      send_headers(200)
      print('{"ok":true,"enabled":false,"active":false}')
    end
  end

else
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', json_escape(tostring(method))))
end
```

- [ ] **Step 2: Append the deploy-and-verify block to `15-provision-bedtime-api.sh`**

Mirror `13-provision-devpause-api.sh`'s own `/api/device-pause` deploy step exactly (its CURRENT shape — read it first): `scp -O` to `/www/cgi-bin/api/device-bedtime`, `chmod +x` + `ls -la`, then a real `curl -sf` GET verify for a MAC with no configured schedule, expecting `{"enabled":false,"active":false}`.

- [ ] **Step 3: Run and verify against the live VM**

```bash
./docker/provision/15-provision-bedtime-api.sh
curl -s "http://localhost:8081/cgi-bin/api/device-bedtime?mac=11:22:33:44:55:66"   # expect {"enabled":false,"active":false}
curl -s -X POST -H 'Content-Type: application/json' -d '{"mac":"11:22:33:44:55:66","enabled":true}' http://localhost:8081/cgi-bin/api/device-bedtime
```
Confirm the response's `active` value matches whatever the VM's real current UTC hour implies (check `ssh ... "date -u +%H"` yourself and compute the expected value by hand before comparing). Then:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "uci show firewall | grep -A6 bedtime_112233445566"
curl -s "http://localhost:8081/cgi-bin/api/device-bedtime?mac=11:22:33:44:55:66"   # expect enabled:true, active matching the rule's real enabled option
```
Test idempotency (POST `enabled:true` again for the same MAC — confirm no duplicate rule, `uci show firewall | grep -c "name='bedtime-112233445566'"` stays 1). Test turning it off (`POST {"mac":...,"enabled":false}` — confirm the rule is genuinely gone from `uci show firewall` and `nft list ruleset`). Test turning off a MAC with no schedule (idempotent no-op success). Test 400 (bad mac, missing/non-boolean enabled). Test 405. Also confirm the just-deployed `bedtime-sweep.sh` (Task 1) picks up a rule this endpoint creates — run it manually once (`ssh ... "/usr/bin/bedtime-sweep.sh"`) after creating a test rule and confirm it doesn't unexpectedly flip anything the endpoint already set correctly (the sweep and the endpoint should never disagree about what "correct for the current hour" means, since both compute it the same way — this is worth a real live check, not just an assumption). Clean up all test rules from the VM afterward.

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/device-bedtime docker/provision/15-provision-bedtime-api.sh
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/device-bedtime endpoint (real per-device recurring schedule)"
```

---

### Task 3: Frontend — wire Per-Device Controls' Bedtime toggle to real data

**Files:**
- Modify: `sadd-website.html` (the `devcontrols` entry in `screens`, new JS, `render()` dispatch, the global click handler, `state`)

Read `renderDevcontrolsScreen`/`handleDevicePauseChipClick` (Wave 5) in full first — this is the exact screen and exact "only overlays real data when `state.selectedDevice` is set, otherwise stays fully static" pattern this task extends. The Bedtime toggle sits on the SAME screen as the already-real Pause-internet chips.

- [ ] **Step 1: Add an id to the Bedtime row in `screens['devcontrols']`**

Via the Node.js JSON-parse-edit approach: find `<div class="sec-label mt-24">Bedtime</div><div class="setting-row"><div class="sr-main"><strong>School nights</strong><span>9:00 PM–7:00 AM</span></div><div class="switch on"></div></div>` and add an id to the switch:
`<div class="switch on" id="devcontrolsBedtimeSwitch"></div>`.

- [ ] **Step 2: Add `state.devcontrolsBedtimeRenderId`**

Add `, devcontrolsBedtimeRenderId: 0` to `state`.

- [ ] **Step 3: Add the render/handler JS**

Insert after the last write-control function from the most recent prior wave's frontend work (search for the final function in the file before the Diagnostics & Logs section comment, and confirm you're inserting after whatever that currently is — it may have shifted since this plan was written):

```js
  // ---- Per-Device Controls "Bedtime" toggle (id="devcontrolsBedtimeSwitch"): a REAL
  //      recurring-schedule write control, GET/POST /cgi-bin/api/device-bedtime — only
  //      when reached with a real selected device (state.selectedDevice), mirroring
  //      renderDevcontrolsScreen's own "no real device context, stay static" contract for
  //      the Pause-internet chips on this same screen. Unlike a simple on/off toggle, the
  //      real backend state has two dimensions (enabled: is a schedule configured at all;
  //      active: is it blocking RIGHT NOW) — this control's switch reflects `active` (what
  //      the user visually sees matters more than the schedule's mere existence), and the
  //      description text below it explains the discrepancy explicitly when the schedule
  //      is configured but not currently active (daytime), rather than a switch that looks
  //      "off" for a schedule that's actually working correctly, just not blocking at this
  //      hour. This VM has no configured timezone (docker/facts.md Section 16) — the
  //      description text says "UTC" plainly, not a fabricated local time. ----
  function setDevcontrolsBedtimeVisual(sw, descEl, enabled, active){
    sw.classList.toggle('on', !!active);
    sw.setAttribute('aria-checked', active ? 'true' : 'false');
    if(descEl){
      if(!enabled) setEscapedText(descEl, '9:00 PM–7:00 AM UTC');
      else if(active) setEscapedText(descEl, '9:00 PM–7:00 AM UTC · blocking now');
      else setEscapedText(descEl, '9:00 PM–7:00 AM UTC · scheduled, not active now');
    }
  }

  async function renderDevcontrolsBedtimeScreen(){
    const dev = state.selectedDevice;
    if(!dev || !dev.mac) return; // reached via the original static path — nothing to overlay
    const myRenderId = state.devcontrolsBedtimeRenderId;
    const sw = document.getElementById('devcontrolsBedtimeSwitch');
    if(!sw) return;
    const descEl = sw.closest('.setting-row') ? sw.closest('.setting-row').querySelector('.sr-main span') : null;
    const data = await fetchRouterApi('/cgi-bin/api/device-bedtime?mac=' + encodeURIComponent(dev.mac));
    if(state.screen !== 'devcontrols' || state.devcontrolsBedtimeRenderId !== myRenderId) return;
    if(data && typeof data === 'object'){
      setDevcontrolsBedtimeVisual(sw, descEl, !!data.enabled, !!data.active);
    }
  }

  // Bedtime switch click: REAL write, POST /cgi-bin/api/device-bedtime {mac, enabled}.
  // Optimistic-flip design like the other toggle controls in this file, but the "on"
  // state it flips to is the CURRENT server-computed `active` value from the response,
  // not a simple wasOn/nextOn boolean pair — since turning the schedule on doesn't
  // necessarily mean the switch should show "on" right now (see header comment: enabled
  // vs active). So this optimistically shows "pending" styling only, not a flipped state,
  // and applies the real resulting visual once the response arrives.
  async function handleDevcontrolsBedtimeClick(sw){
    if(sw.dataset.pending === 'true') return;
    const wasEnabled = sw.dataset.bedtimeEnabled === 'true';
    const wasActive = sw.classList.contains('on'); // captured up front — nothing mutates the
      // switch's visual state before the request resolves (see comment above this function:
      // this control shows "pending" styling only, never an optimistic flip), so this is the
      // real prior state to revert to on failure, not a coincidentally-still-correct read.
    const nextEnabled = !wasEnabled;
    const dev = state.selectedDevice;
    if(!dev || !dev.mac) return;
    const descEl = sw.closest('.setting-row') ? sw.closest('.setting-row').querySelector('.sr-main span') : null;
    sw.dataset.pending = 'true';
    sw.classList.add('pending');
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/device-bedtime', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({mac: dev.mac, enabled: nextEnabled})
    }, 3000);
    sw.dataset.pending = 'false';
    sw.classList.remove('pending');
    if(result && result.ok){
      sw.dataset.bedtimeEnabled = String(!!result.data.enabled);
      setDevcontrolsBedtimeVisual(sw, descEl, !!result.data.enabled, !!result.data.active);
    } else {
      // revert to exactly the prior known state — no false-success left showing
      setDevcontrolsBedtimeVisual(sw, descEl, wasEnabled, wasActive);
      let notice = sw.closest('.setting-row') ? sw.closest('.setting-row').nextElementSibling : null;
      if(!notice || !notice.classList || !notice.classList.contains('api-fallback-notice')){
        notice = document.createElement('div');
        notice.className = 'api-fallback-notice';
        if(sw.closest('.setting-row')) sw.closest('.setting-row').insertAdjacentElement('afterend', notice);
      }
      if(notice.dataset.removeTimer) clearTimeout(Number(notice.dataset.removeTimer));
      const msg = (result && result.data && result.data.error) ? result.data.error
        : (result === null ? "Can't reach router — Bedtime not changed." : ('Request failed (status '+result.status+') — Bedtime not changed.'));
      setEscapedText(notice, msg);
      notice.dataset.removeTimer = setTimeout(()=>{ if(notice.parentElement) notice.remove(); }, 4000);
    }
  }
```

Also update `renderDevcontrolsBedtimeScreen`'s success branch to stash `sw.dataset.bedtimeEnabled = String(!!data.enabled)` alongside the visual update (needed by the click handler's revert path) — add that one line into the existing function above before finalizing this step.

- [ ] **Step 4: Wire the dispatch points**

`render()`: alongside the existing `devcontrols` dispatch line (which already bumps `state.devcontrolsRenderId` and calls `renderDevcontrolsScreen()`), add a second call gated the same way:
```js
      if(state.screen === 'devcontrols'){ state.devcontrolsBedtimeRenderId++; renderDevcontrolsBedtimeScreen(); }
```
(This can be the same `if` block as the existing one — just add the second statement inside it — or a separate adjacent `if(state.screen === 'devcontrols'){...}` block; either is fine, match whatever's cleanest given the current code shape.)

Global click handler — the Bedtime switch needs interception in the existing `.switch` branch, before the generic fallback. Find the chain of `if(sw.id === '...'){ ... return; }` checks (guestWifiSwitch, adblockSwitch, wireguardSwitch, plus Wave 6's `sw.dataset.wireguardClientSwitch` check) and add:
```js
      if(sw.id === 'devcontrolsBedtimeSwitch'){ handleDevcontrolsBedtimeClick(sw); return; }
```

- [ ] **Step 5: Verify against the live VM**

No browser available — verify via grep-confirms, `node --check` on the extracted `<script>`, a fresh valid JSON re-parse of `screens` (48 keys), careful manual code tracing (especially the enabled-vs-active distinction and the optimistic-pending-not-flipped design), and direct curl exercise of the real `/api/device-bedtime` endpoint. Clean up any test schedule created against the live VM afterward.

- [ ] **Step 6: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Per-Device Controls' Bedtime toggle to a real recurring schedule"
```

---

### Task 4: Documentation closeout

**Files:**
- Modify: `docker/README.md` (Provisioning section, Known Limitations)
- Modify: `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` (Architecture diagram, Components, Frontend changes, Testing, Security posture, Full roadmap sections)

- [ ] **Step 1: `docker/README.md`**

Confirm step 15 (both the sweep-script and endpoint deploys) is fully documented (added incrementally by Tasks 1/2) — fix any gap. Add Known Limitations bullets: (a) the Bedtime schedule enforces a fixed UTC 21:00–07:00 window, not real local time, since this VM has no configured timezone (cross-reference `docker/facts.md` §16); (b) the sweep runs every 5 minutes, so a schedule transition (e.g. turning on right at the UTC hour boundary) can lag by up to that long, same "real, not simulated, but worth being explicit about the granularity" framing as the devpause-sweep's own documented limitation; (c) turning Bedtime on takes effect immediately regardless of the sweep's own cadence (the create endpoint computes the current window membership itself), but the *next* transition (e.g. 07:00 UTC unblock) still depends on the sweep's normal cadence. Update the write-endpoint count (eight → nine: `+device-bedtime`).

- [ ] **Step 2: Design spec**

Mirror Wave 6's closeout pattern: a dated Wave 7 paragraph in Testing (what was proven real and how — the real `enabled`-option persist/toggle mechanism, the real fault-injected sweep test in both directions, the shell arithmetic gotcha found and avoided before it ever shipped); `### Device Bedtime API` subsection in Components; extend the Frontend-changes running screen-count sentence; update the Architecture diagram comment; update the Security-posture write-endpoint count; flip Wave 7 from "(in progress)" to "(done)" in the Goal section and the Full roadmap section.

- [ ] **Step 3: Commit**

```bash
git add docker/README.md docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: Wave 7 closeout — README limitations, design spec updates"
```

---

## After all tasks

Dispatch one final whole-wave integration-level code-quality review (a fresh `superpowers:code-reviewer` subagent, given the full diff across all 4 tasks — pay particular attention to whether `bedtime-sweep.sh` and the `/api/device-bedtime` endpoint's own hour-window computation can ever disagree with each other, given they compute the same fixed window two different ways in two different languages, and whether the frontend's enabled-vs-active distinction is genuinely reflected correctly rather than just plausibly), fix anything it raises, commit, then report Wave 7 complete using the same format every prior wave's completion summary used.
