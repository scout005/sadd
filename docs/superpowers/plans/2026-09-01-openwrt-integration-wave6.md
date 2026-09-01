# OpenWrt Integration — Wave 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend two mechanisms Wave 5 already proved real. **VPN Server (WireGuard)**'s "Client devices" list + "Add client" button become real (a genuine per-client keypair, a real `wireguard_wg0` uci peer, a real per-client enable/disable toggle). **Traffic & QoS**'s "Priority devices" list + "Add priority device" button become real (a genuine per-device `uci firewall` traffic-marking rule).

**Architecture:** Same shape as every prior wave: a Lua CGI endpoint per feature under `docker/provision/www/api/`, no baseline provisioning script needed this time (both features create state dynamically per-request, like `device-pause`, not via a pre-seeded baseline like `wireguard`'s own `wg0` interface), consumed by two new small add-forms in `sadd-website.html` following the existing `firewallAddForm` precedent (search for `firewallAddForm`/`data-firewall-add-submit` — read that whole flow first, it's this wave's closest template for "a button reveals a form, submitting POSTs and re-renders the list"). Every command below was proven live against the running VM before this plan was written — see `docker/facts.md` §15.

**Tech Stack:** Unchanged from every prior wave — OpenWrt 23.05.5 Lua CGI, `uci`/`fw4`/`nft`/`wg`, vanilla JS/HTML/CSS in `sadd-website.html`, no build step.

---

## Before you start (context every task shares)

- VM: `bash docker/fetch-boot-image.sh` (no-op if fetched) then `cd docker && docker compose up -d --build`, wait for `docker inspect --format='{{.State.Health.Status}}' openwrt` to report `healthy`. Wave 5's real `wg0` server should already be up (`bash docker/provision/11-provision-wireguard-api.sh` re-provisions/verifies it idempotently if not).
- SSH: `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost`. SCP requires `-O`.
- Git identity: `GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com"`.
- **Every new Lua endpoint must copy these helpers verbatim from `docker/provision/www/api/device-pause`** (the most recently hardened endpoint, post-code-review): `run()`, `shell_quote()`, `json_escape()` (the canonical table-based version — do NOT reinvent it, a prior wave's code review already caught and fixed one deviation), `read_request_body()`, `json_parse_flat_object()`, `send_headers()`, and the `list_*_sections()` id/field-parsing pattern (generalize it to whatever config/section-type each new endpoint needs, the same way `device-pause` generalized `firewall-rules`' original `list_redirect_sections()` to `rule` sections). Also copy `device-pause`'s **stable-id-rename discipline**: immediately after any `uci add`, rename to a stable name (verified via `section_type(id) == expected_type` before any field write) — never leave a section addressed by `@type[-1]`/`@type[N]` across more than the single `uci add` call, per the race this exact pattern was fixed for in Wave 5.
- Frontend: read `renderFirewallScreen`/`submitFirewallAddRule`/the firewall add-form's static markup and click-handler wiring (search `data-firewall-add-cancel`, `data-firewall-add-submit`, `data-firewall-delete-id`) as the template for both new add-forms this wave builds. Also re-read `handleWireguardSwitchClick`/`handleSshRotateClick`/`handleDevicePauseChipClick` (search each by name) for the established optimistic-write and timer-tracking idioms.
- After all tasks, dispatch one final whole-wave integration-level code-quality review, fix anything it raises, then report Wave 6 complete.

---

### Task 1: `/api/wireguard-clients` endpoint (GET list + POST create/toggle)

**Files:**
- Create: `docker/provision/www/api/wireguard-clients`
- Modify: `docker/provision/11-provision-wireguard-api.sh` (append a deploy-and-verify step, same shape as its existing `/api/wireguard` deploy block)

- [ ] **Step 1: Write the endpoint**

Design:
- `GET /cgi-bin/api/wireguard-clients` → `[{"id":"...", "name":"...", "publicKey":"...", "enabled":true|false, "added":"..."}, ...]` — real list of every `wireguard_wg0` peer section under `network.wg0`, parsed from `uci show network` (adapt `device-pause`'s `list_rule_sections()`-style parser: same id/field-split algorithm, generalized from `firewall`+`rule` to `network`+`wireguard_wg0`). `enabled` is `true` unless the section's `disabled` option reads `'1'`. `added`/`name` are custom uci options this endpoint itself writes on create (uci tolerates and netifd's `wireguard.sh` proto script ignores unrecognized options — same established pattern as `device-pause`'s `paused_until`).
- `POST /cgi-bin/api/wireguard-clients` with body `{"name": "<string>"}` (id absent) → **create**: generates a real client keypair (`wg genkey`/`wg pubkey`, same as `docker/provision/11-provision-wireguard-api.sh`'s own server-key generation), assigns the next free `/32` address in `10.9.0.0/24` starting at `.2` (`.1` is the server itself — scan existing peers' `allowed_ips` to find the lowest unused octet in `[2,254]`, defaulting to `.2` if none exist), adds a real `wireguard_wg0` section (`public_key`, `allowed_ips='10.9.0.<n>/32'`, `route_allowed_ips='1'`, custom `name`/`added` options), renamed to a stable id (`wgc_<unix-time>_<6 hex from /dev/urandom>` — adapt `firewall-rules`' `random_hex()` verbatim), verified via readback, committed, `ifdown wg0; ifup wg0` to apply. Returns `{"ok":true,"id":"...","publicKey":"<client's own new pubkey>","config":"<full real wg-quick-style client config text>"}`. The `config` field is a real, importable client config built from real values: the client's own newly-generated private key (returned exactly once, in this response — **never persisted server-side**, matching real WireGuard practice: the server only ever stores each peer's PUBLIC key), the client's assigned address, the real server public key (`wg show wg0 public-key`), `Endpoint = <same Hostname field the mockup already shows>:51820` (this VM has no real externally-reachable hostname — reuse the existing static `smith-family.saddvpn.com` placeholder already on this screen, consistent with how every other WAN-adjacent feature in this project treats a non-testable-but-plausible endpoint address), and `AllowedIPs = 10.9.0.0/24`.
- `POST /cgi-bin/api/wireguard-clients` with body `{"id": "<string>", "enabled": true|false}` (name absent) → **toggle**: sets that peer section's `disabled` option (`0` for enabled, `1` for disabled), verified via readback, committed, `ifdown wg0; ifup wg0`. Returns `{"ok":true,"enabled":<bool>}`. 404 if `id` doesn't match any existing peer section.
- 400 if the body matches neither shape (both `name` and `id` present or absent, `name` empty/whitespace-only, `enabled` present but not a JSON boolean). 405 for anything but GET/POST.

```lua
#!/usr/bin/lua
-- /api/wireguard-clients — GET (list) + POST (create OR toggle, dispatched by
-- which fields the body has). Real WireGuard client-peer management for the
-- VPN Server (WireGuard) screen's "Client devices" section, extending the
-- real wg0 server docker/provision/11-provision-wireguard-api.sh already
-- provisions (docker/facts.md Section 15 has the confirmed-live investigation
-- this endpoint is built on: real wireguard_wg0 peer creation, real per-peer
-- disabled toggle, both proven before this file was written).
--
-- GET response shape:
--   [{"id":"...", "name":"...", "publicKey":"...", "enabled":true|false, "added":"..."}, ...]
--
-- === Security note: private keys never leave the server except at the
-- moment of creation ===
-- A client's PRIVATE key is generated here, returned ONCE in the create
-- response, and then discarded — never written to uci, never logged, never
-- retrievable again after that single response. This matches real-world
-- WireGuard practice (the server only ever needs to know each peer's PUBLIC
-- key to route/verify traffic) and means this endpoint's own uci state has
-- no secret material a later GET could leak.
--
-- === Stable section ids ===
-- Every created peer section is immediately uci-renamed to a stable id
-- (wgc_<time>_<6 hex>), the same firewall-rules precedent device-pause
-- already generalized — never left addressed by a positional @wireguard_wg0[N]
-- reference across more than the single uci add call.
--
-- === Address assignment ===
-- The server itself owns 10.9.0.1 (network.wg0.addresses). Each client peer
-- gets the next unused /32 in 10.9.0.2-10.9.0.254, computed by scanning
-- existing peers' allowed_ips for the lowest unused integer in that range.
--
-- === Write discipline ===
-- Same write-then-readback-verify-then-commit-or-revert as every other write
-- endpoint in this directory, adapted for a section ADD (create) and a
-- single-option SET (toggle).

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

-- Canonical table-based json_escape — copied verbatim from
-- docker/provision/www/api/device-pause / vlans. Do not reinvent.
local function json_escape(s)
  if s == nil then return "" end
  s = tostring(s)
  s = s:gsub('[\\"\n\r\t]', {
    ['\\'] = '\\\\', ['"'] = '\\"', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
  })
  s = s:gsub('[\1-\31]', '')
  return s
end

local function random_hex(nbytes)
  local f = io.open("/dev/urandom", "rb")
  if not f then return tostring(os.time()) end
  local bytes = f:read(nbytes) or ""
  f:close()
  local hex = {}
  for k = 1, #bytes do hex[#hex + 1] = string.format("%02x", bytes:byte(k)) end
  return table.concat(hex)
end

-- Parses `uci show network` into id -> fields for every `wireguard_wg0`-type
-- section — same id/field-split algorithm as firewall-rules'
-- list_redirect_sections() / device-pause's list_rule_sections(), generalized
-- to a different config (network) and type (wireguard_wg0).
local function list_client_sections()
  local output = run("uci show network")
  local order, is_client, fields = {}, {}, {}
  for line in output:gmatch("[^\n]+") do
    local lhs, rhs = line:match("^(.-)=(.*)$")
    if lhs and rhs then
      local rest = lhs:match("^network%.(.+)$")
      if rest then
        local dot = rest:find("%.")
        if dot then
          local id, field = rest:sub(1, dot - 1), rest:sub(dot + 1)
          if is_client[id] then
            local val = rhs:match("^'(.-)'$")
            fields[id][field] = val or rhs
          end
        else
          local id = rest
          local typ = rhs:match("^'?(.-)'?$")
          if typ == "wireguard_wg0" and not is_client[id] then
            is_client[id] = true
            order[#order + 1] = id
            fields[id] = {}
          end
        end
      end
    end
  end
  return order, fields
end

local function section_type(id)
  return run("uci get network." .. id)
end

local function next_free_address()
  local _, fields = list_client_sections()
  local used = {}
  for _, f in pairs(fields) do
    local octet = f.allowed_ips and f.allowed_ips:match("^10%.9%.0%.(%d+)/32$")
    if octet then used[tonumber(octet)] = true end
  end
  for n = 2, 254 do
    if not used[n] then return n end
  end
  return nil -- subnet exhausted (254 clients) — extremely unlikely in this dev/test context
end

local function read_request_body()
  local len = tonumber(os.getenv("CONTENT_LENGTH") or "")
  if len and len > 0 then return io.read(len) or "" end
  return io.read("*a") or ""
end

-- Same hand-rolled flat-JSON-object parser as every other write endpoint —
-- copy verbatim from device-pause.
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
  local reasons = { [400]="Bad Request", [404]="Not Found", [405]="Method Not Allowed", [500]="Internal Server Error" }
  if status and status ~= 200 then
    print("Status: " .. status .. " " .. (reasons[status] or "Error"))
  end
  print("Content-Type: application/json\n")
end

local method = os.getenv("REQUEST_METHOD") or "GET"

if method == "GET" then
  local order, fields = list_client_sections()
  local rows = {}
  for _, id in ipairs(order) do
    local f = fields[id]
    rows[#rows + 1] = string.format(
      '{"id":"%s","name":"%s","publicKey":"%s","enabled":%s,"added":"%s"}',
      json_escape(id), json_escape(f.name or ""), json_escape(f.public_key or ""),
      (f.disabled ~= "1") and "true" or "false", json_escape(f.added or "")
    )
  end
  send_headers(200)
  print("[" .. table.concat(rows, ",") .. "]")

elseif method == "POST" then
  local body = read_request_body()
  local req = json_parse_flat_object(body)

  if req.id ~= nil then
    -- === Toggle path ===
    local id = req.id
    if type(id) ~= "string" or id == "" or (req.enabled ~= "true" and req.enabled ~= "false") then
      send_headers(400)
      print('{"ok":false,"error":"toggle requires string id and boolean enabled"}')
    elseif section_type(id) ~= "wireguard_wg0" then
      send_headers(404)
      print('{"ok":false,"error":"no such client"}')
    else
      local enabled = req.enabled == "true"
      run("uci set network." .. id .. ".disabled=" .. shell_quote(enabled and "0" or "1"))
      local readback = run("uci get network." .. id .. ".disabled")
      local ok = enabled and (readback == "0" or readback == "") or (not enabled and readback == "1")
      if not ok then
        run("uci revert network")
        send_headers(500)
        print('{"ok":false,"error":"failed to verify the toggle write; reverted"}')
      else
        run("uci commit network")
        run("ifdown wg0"); run("ifup wg0")
        send_headers(200)
        print(string.format('{"ok":true,"enabled":%s}', enabled and "true" or "false"))
      end
    end

  else
    -- === Create path ===
    local name = req.name
    if type(name) ~= "string" or name:match("^%s*$") then
      send_headers(400)
      print('{"ok":false,"error":"missing or invalid required field: name (non-empty string)"}')
    else
      local octet = next_free_address()
      if not octet then
        send_headers(500)
        print('{"ok":false,"error":"no free addresses left in 10.9.0.0/24"}')
      else
        local priv = run("wg genkey")
        local pub = run("printf '%s' " .. shell_quote(priv) .. " | wg pubkey")
        local id = "wgc_" .. os.time() .. "_" .. random_hex(3)
        local client_ip = "10.9.0." .. octet

        local anon = run("uci add network wireguard_wg0")
        local create_failed = anon == "" or anon:find("[^%w_]")
        if not create_failed then
          run("uci rename network." .. anon .. "=" .. id)
          create_failed = section_type(id) ~= "wireguard_wg0"
        end

        if not create_failed then
          run("uci set network." .. id .. ".public_key=" .. shell_quote(pub))
          run("uci set network." .. id .. ".allowed_ips=" .. shell_quote(client_ip .. "/32"))
          run("uci set network." .. id .. ".route_allowed_ips=" .. shell_quote("1"))
          run("uci set network." .. id .. ".name=" .. shell_quote(name))
          run("uci set network." .. id .. ".added=" .. shell_quote(os.date("%b %d")))
        end

        local readback_ok = false
        if not create_failed then
          local _, fields = list_client_sections()
          local f = fields[id]
          readback_ok = f and f.public_key == pub and f.allowed_ips == client_ip .. "/32"
        end

        if not readback_ok then
          run("uci revert network")
          send_headers(500)
          print('{"ok":false,"error":"failed to verify the new client write; reverted"}')
        else
          run("uci commit network")
          run("ifdown wg0"); run("ifup wg0")
          local server_pub = run("wg show wg0 public-key")
          local config = "[Interface]\n" ..
            "PrivateKey = " .. priv .. "\n" ..
            "Address = " .. client_ip .. "/32\n\n" ..
            "[Peer]\n" ..
            "PublicKey = " .. server_pub .. "\n" ..
            "Endpoint = smith-family.saddvpn.com:51820\n" ..
            "AllowedIPs = 10.9.0.0/24\n" ..
            "PersistentKeepalive = 25\n"
          send_headers(200)
          print(string.format('{"ok":true,"id":"%s","publicKey":"%s","config":"%s"}',
            json_escape(id), json_escape(pub), json_escape(config)))
        end
      end
    end
  end

else
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', json_escape(tostring(method))))
end
```

- [ ] **Step 2: Append the deploy-and-verify block to `11-provision-wireguard-api.sh`**

Read the script's current end (it was restructured once already, in a prior wave's fix cycle — find its true final line, not the plan's memory of an earlier shape) and append a block mirroring its own existing `/api/wireguard` deploy step exactly: `scp -O` the new file to `/www/cgi-bin/api/wireguard-clients`, `chmod +x` + `ls -la`, then a real `curl -sf` GET verify expecting a JSON array (`[]` on a clean VM, or containing entries if any exist).

- [ ] **Step 3: Run and verify against the live VM**

```bash
./docker/provision/11-provision-wireguard-api.sh
curl -s http://localhost:8081/cgi-bin/api/wireguard-clients   # expect []
curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"Test Phone"}' http://localhost:8081/cgi-bin/api/wireguard-clients
```
Expected: `{"ok":true,"id":"wgc_...","publicKey":"<real>","config":"[Interface]\nPrivateKey = ...\n..."}`. Then:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "wg show wg0"   # expect a real 2nd peer, matching the returned publicKey, allowed ips 10.9.0.2/32
curl -s http://localhost:8081/cgi-bin/api/wireguard-clients   # expect one real entry, name "Test Phone", enabled:true
```
Extract the returned `id`, then test the toggle path both directions and confirm real peer count changes in `wg show wg0` (disabling should drop it from 1→0 additional peers, re-enabling should bring it back with the same public key). Test a second client add and confirm it gets `10.9.0.3/32` (next free address, not colliding). Test 400 (empty name, malformed toggle body) and 404 (toggle with a bogus id) and 405 (e.g. DELETE). Clean up both test clients from the VM afterward (`uci -q delete network.<id>; uci commit network; ifdown wg0; ifup wg0` for each).

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/wireguard-clients docker/provision/11-provision-wireguard-api.sh
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/wireguard-clients endpoint (real per-client peer create/toggle)"
```

---

### Task 2: Frontend — wire WireGuard Client devices list + Add client + per-row toggle

**Files:**
- Modify: `sadd-website.html` (the `advwireguard` entry in `screens`, new JS, `render()` dispatch, the global click handler, `state`)

- [ ] **Step 1: Add markup to `screens['advwireguard']`**

Via the Node.js JSON-parse-edit-reserialize approach (same as every prior frontend task — never hand-edit the JSON blob):

1. Wrap the two static client rows in a container and add an id to the "+ Add client" button:
   `<div class="desk-table-head">...</div><div class="rule-row">...Jenna's iPhone...</div><div class="rule-row">...Mark's Phone...</div><button class="btn btn-secondary mt-24" style="width:auto;padding:11px 22px;">+ Add client (generates QR code)</button>`
   →
   `<div class="desk-table-head">...</div><div id="wireguardClientList"><div class="rule-row">...Jenna's iPhone...</div><div class="rule-row">...Mark's Phone...</div></div><button class="btn btn-secondary mt-24" id="wireguardAddToggleBtn" style="width:auto;padding:11px 22px;">+ Add client (generates QR code)</button>`
   (find the two existing `.rule-row` elements — Jenna's iPhone and Mark's Phone — by their literal text and wrap exactly those two, no more, in the new `#wireguardClientList` div; leave every other part of that button's text unchanged even though "(generates QR code)" no longer describes the real flow — out of scope for this wave, matching the established discipline of not rewriting copy beyond what's needed).

2. Immediately after the button, insert a new hidden add-form block and a config-display block:
```html
<div class="field mt-24" id="wireguardAddForm" style="display:none;max-width:340px;">
  <label>Client name</label>
  <input class="input" id="wireguardClientNameField" placeholder="e.g. Jenna's iPhone">
  <div style="display:flex;gap:10px;margin-top:10px;">
    <button class="btn btn-primary" style="width:auto;padding:9px 18px;" data-wireguard-add-submit>Add</button>
    <button class="btn btn-secondary" style="width:auto;padding:9px 18px;" data-wireguard-add-cancel>Cancel</button>
  </div>
  <div id="wireguardAddError" style="display:none;color:#dc2626;font-size:12px;margin-top:8px;"></div>
</div>
<div id="wireguardClientConfig" style="display:none;margin-top:14px;"></div>
```

- [ ] **Step 2: Add `state.wireguardClientsRenderId`**

Add `, wireguardClientsRenderId: 0` to `state` (search for `wireguardRenderId: 0` from Wave 5 and add this alongside it).

- [ ] **Step 3: Add the render/handler JS**

Insert after `handleDevicePauseChipClick`'s closing `}` (the last write-control function from Wave 5):

```js
  // ---- VPN Server (WireGuard) "Client devices": real list + add + per-row toggle, POST
  //      /cgi-bin/api/wireguard-clients. The two static demo rows (Jenna's iPhone, Mark's
  //      Phone) are replaced entirely by real data on a successful fetch — same "static
  //      first, real overlays on top, no blank flash" contract as every list screen in
  //      this file. No delete affordance exists in the mockup for these rows, so none is
  //      built (mirrors Network & VLANs' precedent). ----
  function renderWireguardClientRow(c){
    const name = c.name ? escapeHtml(c.name) : c.publicKey.slice(0, 12) + '…';
    return '<div class="rule-row" data-client-id="'+escapeHtml(c.id)+'"><div class="rr-main"><strong>'+name+'</strong></div><span class="mono-badge" style="width:140px;text-align:center;">'+escapeHtml(c.added||'')+'</span><div class="switch'+(c.enabled?' on':'')+'" style="width:38px;height:22px;" data-wireguard-client-switch="'+escapeHtml(c.id)+'"></div></div>';
  }

  async function renderWireguardClientsScreen(){
    const myRenderId = state.wireguardClientsRenderId;
    const data = await fetchRouterApi('/cgi-bin/api/wireguard-clients');
    if(state.screen !== 'advwireguard' || state.wireguardClientsRenderId !== myRenderId) return;
    const listEl = document.getElementById('wireguardClientList');
    const addToggleBtn = document.getElementById('wireguardAddToggleBtn');
    if(!listEl) return;
    if(Array.isArray(data)){
      listEl.innerHTML = data.map(renderWireguardClientRow).join('');
      if(addToggleBtn) addToggleBtn.disabled = false;
    } else if(addToggleBtn){
      addToggleBtn.disabled = true;
    }
  }

  async function submitWireguardAddClient(){
    const form = document.getElementById('wireguardAddForm');
    if(!form) return;
    const nameEl = document.getElementById('wireguardClientNameField');
    const errEl = document.getElementById('wireguardAddError');
    const submitBtn = form.querySelector('[data-wireguard-add-submit]');
    const name = nameEl ? nameEl.value.trim() : '';
    if(errEl){ errEl.style.display = 'none'; errEl.textContent = ''; }
    if(!name){
      if(errEl){ errEl.style.display = 'block'; setEscapedText(errEl, 'Client name is required.'); }
      return;
    }
    if(submitBtn) submitBtn.disabled = true;
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/wireguard-clients', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({name})
    }, 3000);
    if(submitBtn) submitBtn.disabled = false;
    if(result && result.ok && result.data && result.data.config){
      form.style.display = 'none';
      if(nameEl) nameEl.value = '';
      const configEl = document.getElementById('wireguardClientConfig');
      if(configEl){
        configEl.style.display = 'block';
        configEl.innerHTML = '';
        const label = document.createElement('div');
        label.className = 'sec-label';
        setEscapedText(label, 'New client config — save this now, it will not be shown again');
        const pre = document.createElement('pre');
        pre.style.cssText = 'background:var(--bg-2,#f4f4f5);padding:12px;border-radius:8px;font-size:12px;white-space:pre-wrap;word-break:break-all;';
        setEscapedText(pre, result.data.config);
        configEl.appendChild(label);
        configEl.appendChild(pre);
      }
      state.wireguardClientsRenderId++;
      renderWireguardClientsScreen();
    } else if(errEl){
      const msg = (result && result.data && result.data.error) ? result.data.error
        : (result === null ? "Can't reach router — client not added." : ('Request failed (status '+result.status+') — client not added.'));
      errEl.style.display = 'block';
      setEscapedText(errEl, msg);
    }
  }

  // Per-client switch click: REAL write, POST {id, enabled}. Same optimistic-flip/
  // revert-on-failure design and "no render-id guard needed" reasoning as
  // handleWireguardSwitchClick (the server-level toggle from Wave 5) — sw is captured by
  // reference before the await, render() always replaces appContent on navigation.
  async function handleWireguardClientToggle(sw, id){
    if(sw.dataset.pending === 'true') return;
    const wasOn = sw.classList.contains('on');
    const nextOn = !wasOn;
    sw.dataset.pending = 'true';
    sw.classList.add('pending');
    sw.classList.toggle('on', nextOn);
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/wireguard-clients', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({id, enabled: nextOn})
    }, 6000);
    sw.dataset.pending = 'false';
    sw.classList.remove('pending');
    if(result === null || !result.ok){
      sw.classList.toggle('on', wasOn);
    }
  }
```

- [ ] **Step 4: Wire the dispatch points**

`render()`: after the existing `advwireguard` dispatch line (Wave 5's `renderWireguardScreen`), add a second call on the same condition:
```js
      if(state.screen === 'advwireguard'){ state.wireguardClientsRenderId++; renderWireguardClientsScreen(); }
```

Global click handler — add near the existing `fwAddSubmit`/`fwAddCancel` branches (same "specific data-attribute checks, before the generic fallbacks" region):
```js
    const wgAddToggleBtn = e.target.closest('#wireguardAddToggleBtn');
    if(wgAddToggleBtn){
      const form = document.getElementById('wireguardAddForm');
      if(form) form.style.display = form.style.display === 'none' ? 'block' : 'none';
      return;
    }
    const wgAddCancel = e.target.closest('[data-wireguard-add-cancel]');
    if(wgAddCancel){
      const form = document.getElementById('wireguardAddForm');
      if(form) form.style.display = 'none';
      return;
    }
    const wgAddSubmit = e.target.closest('[data-wireguard-add-submit]');
    if(wgAddSubmit){
      if(!wgAddSubmit.disabled) submitWireguardAddClient();
      return;
    }
```

The per-client switch needs to be intercepted in the existing `.switch` branch, before the generic fallback — find the `if(sw.id === 'wireguardSwitch'){ ... }` line from Wave 5 and add immediately after it:
```js
      const wgClientId = sw.dataset.wireguardClientSwitch;
      if(wgClientId){ handleWireguardClientToggle(sw, wgClientId); return; }
```

- [ ] **Step 5: Verify against the live VM**

No browser available — verify via grep-confirms (new ids exist exactly once), `node --check` on the extracted `<script>`, a fresh valid JSON re-parse of `screens`, careful manual code tracing, and direct curl exercise of the real `/api/wireguard-clients` endpoint to confirm the response shapes match what the new JS reads. Clean up any test client created against the live VM afterward.

- [ ] **Step 6: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire VPN Server (WireGuard) Client devices list + Add client + toggle"
```

---

### Task 3: `/api/qos-priority` endpoint (GET list + POST create)

**Files:**
- Create: `docker/provision/www/api/qos-priority`
- Create: `docker/provision/14-provision-qos-priority-api.sh`
- Modify: `docker/README.md` (Provisioning section: add step 14)

No baseline VM state to provision (like `device-pause`, not like `wireguard`'s own server) — the provisioning script only deploys the endpoint file and verifies it responds.

- [ ] **Step 1: Write the endpoint**

Design (adapted directly from `device-pause`'s shape — same helpers, same stable-id-rename discipline, same `src=lan`/`dest=wan` rule shape, swapping `target=REJECT` for `target=MARK`/`set_mark`, and dropping the `paused_until`/expiry concept entirely since priority marking isn't time-limited):

- `GET /cgi-bin/api/qos-priority` → `[{"mac":"AA:BB:CC:DD:EE:FF"}, ...]` — real list of every `qospriority-*`-named `uci firewall` rule, parsed the same `list_rule_sections()` way as `device-pause`. Only `mac` is returned — no display name is stored server-side (the frontend cross-references the device's current name from a fresh `/api/devices` fetch at render time, falling back to showing the raw MAC if that device isn't currently DHCP-leased — an honest, realistic behavior, not a bug, since a prioritized device might not always be online).
- `POST /cgi-bin/api/qos-priority` body `{"mac": "<mac>"}` → creates a real `uci firewall` rule: `name='qospriority-<mac-no-colons-lowercased>'` (immediately renamed to this stable id after `uci add`, exactly like `device-pause`), `src='lan'`, `src_mac=<mac>`, `dest='wan'`, `target='MARK'`, `set_mark='0x2a'`, verified via readback, committed, `fw4 reload`. A second POST for the same MAC is idempotent (finds the existing rule by name, does nothing further, returns `{"ok":true,"mac":"..."}` — not an error, and not a duplicate). Strict MAC validation (same regex as `device-pause`), 400 on invalid/missing mac, no config touched. 405 for anything but GET/POST. No DELETE — matches the mockup, which has no remove affordance for these rows (same choice `/api/vlans` made for its own read-mostly list).

```lua
#!/usr/bin/lua
-- /api/qos-priority — GET (list) + POST (create, idempotent per MAC). Real
-- per-device traffic-marking for the Traffic & QoS screen's "Priority
-- devices" list. Confirmed live before writing this handler
-- (docker/facts.md Section 15): a uci firewall rule with target=MARK,
-- set_mark=0x2a, src=lan, dest=wan lands in the real mangle_forward nft
-- chain — marking the device's actual forwarded traffic, not just traffic
-- addressed to the router (the same src=lan/dest=wan distinction
-- device-pause's own investigation established for REJECT rules applies
-- identically here for MARK).
--
-- GET response shape: [{"mac":"AA:BB:CC:DD:EE:FF"}, ...] — no display name
-- stored here; the frontend cross-references a fresh /api/devices fetch by
-- MAC to show a name, falling back to the raw MAC for a device that isn't
-- currently DHCP-leased (honest, not a bug — a prioritized device isn't
-- guaranteed to always be online).
--
-- POST body: {"mac": "<mac>"} — creates the rule if it doesn't already
-- exist for this MAC; if it already does, this is a no-op success (POSTing
-- the same MAC twice is idempotent, not an error or a duplicate rule).
--
-- No DELETE — the mockup has no remove affordance for these rows (same
-- choice /api/vlans made for its own read-mostly list). Rules created here
-- can only be removed by hand over SSH in this wave; documented as a known
-- limitation, not silently glossed over.
--
-- 0x2a (decimal 42) is an arbitrary, fixed mark value — there's no second
-- priority tier or QoS queueing discipline (tc/SQM) consuming this mark in
-- this wave, so its exact numeric value has no behavioral meaning yet; it
-- exists so the real mechanism (a device's traffic being genuinely,
-- kernel-verifiably marked) can be demonstrated and later built upon.

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

local function mac_to_rule_name(mac) return "qospriority-" .. mac:lower():gsub(":", "") end
local function mac_to_section_id(mac) return "qospriority_" .. mac:lower():gsub(":", "") end -- underscore: uci section ids can't contain '-' (confirmed live, Wave 5 facts.md Section 14)

local function list_priority_sections()
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

local function find_priority_rule(rule_name)
  local order, fields = list_priority_sections()
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
  local order, fields = list_priority_sections()
  local rows = {}
  for _, id in ipairs(order) do
    local name = fields[id].name or ""
    local mac = fields[id].src_mac
    if name:match("^qospriority%-") and mac then
      rows[#rows + 1] = string.format('{"mac":"%s"}', json_escape(mac))
    end
  end
  send_headers(200)
  print("[" .. table.concat(rows, ",") .. "]")

elseif method == "POST" then
  local body = read_request_body()
  local req = json_parse_flat_object(body)
  local mac = req.mac

  if not is_valid_mac(mac) then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: mac (must be AA:BB:CC:DD:EE:FF form)"}')
  else
    local rule_name = mac_to_rule_name(mac)
    local existing_id = find_priority_rule(rule_name)

    if existing_id then
      -- Idempotent: already exists, nothing to do.
      send_headers(200)
      print(string.format('{"ok":true,"mac":"%s"}', json_escape(mac)))
    else
      local section_id = mac_to_section_id(mac)
      local anon = run("uci add firewall rule")
      local create_failed = anon == "" or anon:find("[^%w_]")
      if not create_failed then
        run("uci rename firewall." .. anon .. "=" .. section_id)
        create_failed = section_type(section_id) ~= "rule"
      end
      if not create_failed then
        run("uci set firewall." .. section_id .. ".name=" .. shell_quote(rule_name))
        run("uci set firewall." .. section_id .. ".src=" .. shell_quote("lan"))
        run("uci set firewall." .. section_id .. ".src_mac=" .. shell_quote(mac))
        run("uci set firewall." .. section_id .. ".dest=" .. shell_quote("wan"))
        run("uci set firewall." .. section_id .. ".target=" .. shell_quote("MARK"))
        run("uci set firewall." .. section_id .. ".set_mark=" .. shell_quote("0x2a"))
      end

      local readback_ok = false
      if not create_failed then
        local _, readback_fields = find_priority_rule(rule_name)
        readback_ok = readback_fields
          and readback_fields.src_mac == mac
          and readback_fields.dest == "wan"
          and readback_fields.target == "MARK"
      end

      if not readback_ok then
        run("uci revert firewall")
        send_headers(500)
        print('{"ok":false,"error":"failed to verify the priority rule write; reverted"}')
      else
        run("uci commit firewall")
        run("fw4 reload")
        send_headers(200)
        print(string.format('{"ok":true,"mac":"%s"}', json_escape(mac)))
      end
    end
  end

else
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', json_escape(tostring(method))))
end
```

- [ ] **Step 2: Write the provisioning script**

Base on `docker/provision/13-provision-devpause-api.sh`'s deploy-and-verify-only shape (read its CURRENT content first, post-code-review — it's the closest "no baseline, just deploy+verify a real endpoint" template): deploy `qos-priority` to `/www/cgi-bin/api/qos-priority`, `chmod +x` + `ls -la`, verify with a real `curl -sf` GET expecting a JSON array shape.

- [ ] **Step 3: Run and verify against the live VM**

```bash
chmod +x docker/provision/14-provision-qos-priority-api.sh
./docker/provision/14-provision-qos-priority-api.sh
curl -s http://localhost:8081/cgi-bin/api/qos-priority   # expect []
curl -s -X POST -H 'Content-Type: application/json' -d '{"mac":"11:22:33:44:55:66"}' http://localhost:8081/cgi-bin/api/qos-priority
curl -s http://localhost:8081/cgi-bin/api/qos-priority   # expect [{"mac":"11:22:33:44:55:66"}]
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "nft list ruleset | grep -B2 -A2 '11:22:33:44:55:66'"   # expect a real mangle_forward mark rule
```
Test idempotency (POST the same MAC twice, confirm `uci show firewall | grep -c qospriority_112233445566` stays 1). Test 400 (bad MAC, missing mac). Test 405. Clean up the test rule from the VM afterward.

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/qos-priority docker/provision/14-provision-qos-priority-api.sh docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/qos-priority endpoint (real per-device traffic marking)"
```

---

### Task 4: Frontend — wire Traffic & QoS Priority devices list + Add priority device

**Files:**
- Modify: `sadd-website.html` (the `advqos` entry in `screens`, new JS, `render()` dispatch, the global click handler, `state`)

- [ ] **Step 1: Add markup to `screens['advqos']`**

Via the Node.js JSON-parse-edit approach:

1. Wrap the two static `.adv-row` entries in a container and add an id to "+ Add priority device":
   `<div class="sec-label mt-24">Priority devices</div><div class="adv-row">...Leo's Xbox...</div><div class="adv-row">...Jenna's Laptop...</div><button class="btn btn-secondary mt-24" style="width:auto;padding:11px 22px;">+ Add priority device</button>`
   →
   `<div class="sec-label mt-24">Priority devices</div><div id="qosPriorityList"><div class="adv-row">...Leo's Xbox...</div><div class="adv-row">...Jenna's Laptop...</div></div><button class="btn btn-secondary mt-24" id="qosAddToggleBtn" style="width:auto;padding:11px 22px;">+ Add priority device</button>`

2. Immediately after the button:
```html
<div class="field mt-24" id="qosAddForm" style="display:none;max-width:340px;">
  <label>Device</label>
  <select class="input" id="qosDeviceSelect"><option value="">Loading devices…</option></select>
  <div style="display:flex;gap:10px;margin-top:10px;">
    <button class="btn btn-primary" style="width:auto;padding:9px 18px;" data-qos-add-submit>Add</button>
    <button class="btn btn-secondary" style="width:auto;padding:9px 18px;" data-qos-add-cancel>Cancel</button>
  </div>
  <div id="qosAddError" style="display:none;color:#dc2626;font-size:12px;margin-top:8px;"></div>
</div>
```

- [ ] **Step 2: Add `state.qosPriorityRenderId`**

Add `, qosPriorityRenderId: 0` to `state`.

- [ ] **Step 3: Add the render/handler JS**

Insert after Task 2's `handleWireguardClientToggle`'s closing `}`:

```js
  // ---- Traffic & QoS "Priority devices": real list + add, POST /cgi-bin/api/qos-priority.
  //      No display name is stored server-side — cross-referenced from a fresh
  //      /api/devices fetch by MAC each render, falling back to the raw MAC for a device
  //      that isn't currently leased. No delete affordance in the mockup, so none is
  //      built (mirrors Network & VLANs' precedent). ----
  function renderQosPriorityRow(entry, deviceNamesByMac){
    const name = deviceNamesByMac[entry.mac.toLowerCase()] || entry.mac;
    return '<div class="adv-row"><div class="ar-icon"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="8" cy="12" r="1.6"/><circle cx="16" cy="12" r="1.6"/></svg></div><div class="ar-main"><strong>'+escapeHtml(name)+'</strong><div class="ar-meta">High priority</div></div></div>';
  }

  async function renderQosPriorityScreen(){
    const myRenderId = state.qosPriorityRenderId;
    const [priorityData, devicesData] = await Promise.all([
      fetchRouterApi('/cgi-bin/api/qos-priority'),
      fetchRouterApi('/cgi-bin/api/devices')
    ]);
    if(state.screen !== 'advqos' || state.qosPriorityRenderId !== myRenderId) return;
    const listEl = document.getElementById('qosPriorityList');
    const addToggleBtn = document.getElementById('qosAddToggleBtn');
    if(!listEl) return;
    const deviceNamesByMac = {};
    if(Array.isArray(devicesData)){
      devicesData.forEach(d => { if(d.mac) deviceNamesByMac[d.mac.toLowerCase()] = d.hostname || d.ip || d.mac; });
    }
    if(Array.isArray(priorityData)){
      listEl.innerHTML = priorityData.map(e => renderQosPriorityRow(e, deviceNamesByMac)).join('');
      if(addToggleBtn) addToggleBtn.disabled = false;
    } else if(addToggleBtn){
      addToggleBtn.disabled = true;
    }
  }

  async function openQosAddForm(){
    const form = document.getElementById('qosAddForm');
    const select = document.getElementById('qosDeviceSelect');
    if(!form) return;
    form.style.display = form.style.display === 'none' ? 'block' : 'none';
    if(form.style.display === 'block' && select){
      setEscapedText(select, ''); // clear via textContent-safe path before rebuilding options
      select.innerHTML = '<option value="">Loading devices…</option>';
      const devices = await fetchRouterApi('/cgi-bin/api/devices');
      if(Array.isArray(devices) && devices.length){
        select.innerHTML = devices.map(d => '<option value="'+escapeHtml(d.mac||'')+'">'+escapeHtml(d.hostname || d.ip || d.mac || 'Unknown device')+'</option>').join('');
      } else {
        select.innerHTML = '<option value="">No devices available</option>';
      }
    }
  }

  async function submitQosAddPriority(){
    const form = document.getElementById('qosAddForm');
    if(!form) return;
    const select = document.getElementById('qosDeviceSelect');
    const errEl = document.getElementById('qosAddError');
    const submitBtn = form.querySelector('[data-qos-add-submit]');
    const mac = select ? select.value : '';
    if(errEl){ errEl.style.display = 'none'; errEl.textContent = ''; }
    if(!mac){
      if(errEl){ errEl.style.display = 'block'; setEscapedText(errEl, 'Choose a device.'); }
      return;
    }
    if(submitBtn) submitBtn.disabled = true;
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/qos-priority', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({mac})
    }, 3000);
    if(submitBtn) submitBtn.disabled = false;
    if(result && result.ok){
      form.style.display = 'none';
      state.qosPriorityRenderId++;
      renderQosPriorityScreen();
    } else if(errEl){
      const msg = (result && result.data && result.data.error) ? result.data.error
        : (result === null ? "Can't reach router — device not added." : ('Request failed (status '+result.status+') — device not added.'));
      errEl.style.display = 'block';
      setEscapedText(errEl, msg);
    }
  }
```

- [ ] **Step 4: Wire the dispatch points**

`render()`: add alongside the other Task/Wave dispatch lines:
```js
      if(state.screen === 'advqos'){ state.qosPriorityRenderId++; renderQosPriorityScreen(); }
```

Global click handler — add near the WireGuard add-form branches from Task 2:
```js
    const qosAddToggleBtn = e.target.closest('#qosAddToggleBtn');
    if(qosAddToggleBtn){ openQosAddForm(); return; }
    const qosAddCancel = e.target.closest('[data-qos-add-cancel]');
    if(qosAddCancel){
      const form = document.getElementById('qosAddForm');
      if(form) form.style.display = 'none';
      return;
    }
    const qosAddSubmit = e.target.closest('[data-qos-add-submit]');
    if(qosAddSubmit){
      if(!qosAddSubmit.disabled) submitQosAddPriority();
      return;
    }
```

- [ ] **Step 5: Verify against the live VM**

Same static-verification approach as every prior frontend task this wave (grep-confirms, `node --check`, JSON re-parse, manual trace, direct curl exercise of the real endpoints). Clean up any test priority rule created on the VM afterward.

- [ ] **Step 6: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Traffic & QoS Priority devices list + Add priority device"
```

---

### Task 5: Documentation closeout

**Files:**
- Modify: `docker/README.md` (Provisioning section, Known Limitations)
- Modify: `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` (Architecture diagram, Components, Frontend changes, Testing, Security posture, Full roadmap sections)

- [ ] **Step 1: `docker/README.md`**

Confirm steps 14 (qos-priority) and the wireguard-clients deploy addition to step 11 are already correctly documented (added incrementally by Tasks 1/3) — fix any numbering gap. Add Known Limitations bullets: (a) WireGuard clients' private keys are shown exactly once at creation and never persisted server-side — if the config display is dismissed without saving it, there is no way to recover it short of removing and re-adding the client (a real, standard WireGuard operational fact, not a bug); (b) Priority devices and WireGuard clients both have no remove/delete affordance in the UI — real state can only be removed by hand over SSH in this wave, matching the same choice already made for VLANs; (c) the QoS mark value (`0x2a`) has no consuming queueing discipline yet — the marking itself is real and kernel-verifiable, but nothing currently prioritizes marked traffic's actual latency/bandwidth; that would be its own future wave (a real `tc`/SQM setup keyed on this mark). Update the write-endpoint count (six → eight: `+wireguard-clients`, `+qos-priority`).

- [ ] **Step 2: Design spec**

Mirror Wave 5's closeout pattern exactly: a dated Wave 6 paragraph in Testing; `### WireGuard Clients API` / `### QoS Priority API` subsections in Components; extend the Frontend-changes running screen-count sentence; update the Architecture diagram comment; update the Security-posture write-endpoint count; flip Wave 6 from "(in progress)" to "(done)" in the Goal section and the Full roadmap section.

- [ ] **Step 3: Commit**

```bash
git add docker/README.md docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: Wave 6 closeout — README limitations, design spec updates"
```

---

## After all tasks

Dispatch one final whole-wave integration-level code-quality review (a fresh `superpowers:code-reviewer` subagent, given the full diff across all 5 tasks — pay particular attention to whether the two new endpoints (`wireguard-clients`, `qos-priority`) and `device-pause` genuinely agree with each other on every shared convention, not just each independently matching an older sibling), fix anything it raises, commit, then report Wave 6 complete using the same format every prior wave's completion summary used.
