# OpenWrt Integration — Wave 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire three more screens in `sadd-website.html` to genuinely real OpenWrt/VM state: **Developer & API Access**' "Rotate SSH key" button, **VPN Server (WireGuard)**'s hero toggle + connection details, and **Per-Device Controls**' "Pause internet" action — the last one reached for the first time via real navigation from the (already-real) Devices list, not as a standalone unreachable demo screen.

**Architecture:** Same shape as Waves 1-4: a small Lua CGI endpoint per feature under `docker/provision/www/api/`, deployed and (where the feature needs baseline VM state) provisioned by a new numbered `docker/provision/NN-*.sh` script, consumed by `sadd-website.html`'s existing `fetchRouterApi`/`fetchRouterApiWithStatus` + render-id-guarded render functions + (for the two write paths) the established optimistic-update switch/button pattern. Every exact command below was proven live against the running VM before this plan was written — see `docker/facts.md` Sections 13-14.

**Tech Stack:** OpenWrt 23.05.5 (Lua CGI under `uhttpd`, `uci`/`fw4`/`nft`/`ubus`/`dropbear`/`wg`/netifd), Docker/QEMU (unchanged), vanilla JS/HTML/CSS in `sadd-website.html` (no build step, no frameworks).

---

## Before you start (context every task shares)

- Bring the VM up: `bash docker/fetch-boot-image.sh` (no-op if already fetched) then `docker compose up -d --build` from `docker/`, wait for `docker inspect --format='{{.State.Health.Status}}' openwrt` to report `healthy`.
- SSH: `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost`. Copy files with `scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 2223 <local> root@localhost:<remote>` — **the `-O` flag is required** (legacy SCP protocol; this VM's dropbear has no `sftp-server`, confirmed in `docker/facts.md`).
- Git identity for every commit in this repo (no global git config is touched): `GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com"`.
- Every existing endpoint under `docker/provision/www/api/` (read `adblock`, `wifi`, or `firewall-rules` first) establishes the conventions every new endpoint below must follow: hand-built JSON (no `lua-cjson` — no outbound internet on the VM), a `run()`/`uci_get()` shell-out helper, `shell_quote()` for any interpolated value, the hand-rolled `json_parse_flat_object` body parser for POST bodies (JSON `true`/`false` parse as the Lua **strings** `"true"`/`"false"`, not real booleans), write-then-readback-verify-then-commit with `uci revert <config>` on mismatch, differentiated `Status:` headers (400/404/405/500), and a `send_headers(status)` helper. Copy these helpers verbatim into each new endpoint file rather than trying to share code between CGI scripts (established precedent: every endpoint file is self-contained for simple `scp` deployment — see `08-provision-wifi-api.sh`'s header comment on the accepted duplication).
- Frontend conventions (read `sadd-website.html` around `fetchRouterApi`/`fetchRouterApiWithStatus`, `state`, `syncFallbackNotice`, `handleAdblockSwitchClick`/`setAdblockSwitchVisual`, and `renderGuestScreen`/`handleGuestWifiSwitchClick` first — these are this wave's closest templates): `fetchRouterApi(path)` for read-only GETs (returns parsed JSON or `null`), `fetchRouterApiWithStatus(path, opts, timeoutMs)` for writes (returns `{ok,status,data}` or `null`; pass an explicit `timeoutMs` for any endpoint whose real handler is slow — see Task 1's finding on WireGuard's `ifup`/`network restart` timing), a `state.<screen>RenderId` counter bumped in `render()` and captured-before-await/compared-after-await inside each `render<Screen>Screen()`, `setEscapedText(el, text)` for any text assignment, `syncFallbackNotice(anchorEl, hasData, message)` for hero/single-row screens' fallback notice.
- After all tasks, dispatch one final whole-wave integration-level code-quality review (as every prior wave did), fix anything it raises, then report Wave 5 complete.

---

### Task 1: Provision a real WireGuard server (packages + baseline UCI config)

**Files:**
- Create: `docker/provision/11-provision-wireguard-api.sh`
- Modify: `docker/README.md:Provisioning section` (add step 11 to the sequential command list)

This script installs WireGuard support and brings up a real, persisted `wg0` interface — mirroring `08-provision-wifi-api.sh`'s "create baseline config from nothing" shape (this VM has no WireGuard config of any kind on a fresh boot), including its idempotent verify/create/revert/retry-once discipline (see that script's own header comment, and the newly-added note in it about this being a now-3×-duplicated pattern — this makes it 4×, but per that note the extraction is still deliberately deferred).

- [ ] **Step 1: Write the package-install portion**

Nine `.ipk` files are required (the full transitive dependency chain — see `docker/facts.md` Section 14 for exactly which two of `opkg`'s own first-round error messages hide a second layer of missing deps). All nine come from `https://downloads.openwrt.org/releases/23.05.5/`, all `x86_64`, all kernel-version-pinned `5.15.167-1` except `wireguard-tools` itself:

```sh
#!/bin/sh
set -e

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

echo "=== 11-provision-wireguard-api.sh ==="

# --- Idempotency check: is a real, working wg0 already up? ---
if ssh_run "ip link show wg0 2>/dev/null | grep -q 'state UNKNOWN\|POINTOPOINT'" && \
   ssh_run "wg show wg0 >/dev/null 2>&1"; then
  echo "wg0 already up with a real WireGuard interface — skipping package install and baseline config."
else
  echo "Downloading WireGuard packages + full transitive kmod dependency chain on the host..."
  WORKDIR="$(mktemp -d)"
  BASE_TARGETS="https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/packages"
  BASE_PACKAGES_BASE="https://downloads.openwrt.org/releases/23.05.5/packages/x86_64/base"

  for pkg in kmod-crypto-kpp kmod-crypto-lib-chacha20 kmod-crypto-lib-chacha20poly1305 \
             kmod-crypto-lib-curve25519 kmod-crypto-lib-poly1305 kmod-udptunnel4 \
             kmod-udptunnel6 kmod-wireguard; do
    curl -sf -o "${WORKDIR}/${pkg}.ipk" "${BASE_TARGETS}/${pkg}_5.15.167-1_x86_64.ipk"
  done
  curl -sf -o "${WORKDIR}/wireguard-tools.ipk" "${BASE_PACKAGES_BASE}/wireguard-tools_1.0.20210914-2_x86_64.ipk"

  echo "Copying to the VM..."
  scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" "${WORKDIR}"/*.ipk "${SSH_TARGET}:/tmp/"

  echo "Installing (all 9 in one command — installing the crypto-lib kmods separately from"
  echo "kmod-wireguard silently leaves the module unprobeable; see docker/facts.md Section 14)..."
  ssh_run "opkg install /tmp/kmod-crypto-kpp.ipk /tmp/kmod-crypto-lib-chacha20.ipk /tmp/kmod-crypto-lib-chacha20poly1305.ipk /tmp/kmod-crypto-lib-curve25519.ipk /tmp/kmod-crypto-lib-poly1305.ipk /tmp/kmod-udptunnel4.ipk /tmp/kmod-udptunnel6.ipk /tmp/kmod-wireguard.ipk /tmp/wireguard-tools.ipk && rm -f /tmp/kmod-*.ipk /tmp/wireguard-tools.ipk"

  rm -rf "${WORKDIR}"

  echo "Verifying the kernel module actually probes (opkg exit 0 alone is not proof — see facts.md Section 14)..."
  ssh_run "modprobe wireguard && lsmod | grep -q '^wireguard '"

  echo "Restarting the network service so netifd picks up the newly-installed wireguard.sh"
  echo "proto handler (a reload/ifup alone silently leaves proto=wireguard unrecognized — see"
  echo "docker/facts.md Section 14)..."
  ssh_run "/etc/init.d/network restart"
  sleep 3
fi
```

- [ ] **Step 2: Write the baseline `wg0` config + verify-revert-retry portion**

Appended to the same file, after the package-install block above:

```sh
# --- Baseline network.wg0 config: create if missing, verify via readback, retry once ---
create_and_verify_wg0() {
  ssh_run "
    umask 077
    if [ ! -f /etc/wireguard-privkey ]; then
      wg genkey > /etc/wireguard-privkey
    fi
    PRIV=\$(cat /etc/wireguard-privkey)
    uci -q delete network.wg0 2>/dev/null
    uci set network.wg0=interface
    uci set network.wg0.proto=wireguard
    uci set network.wg0.private_key=\"\$PRIV\"
    uci set network.wg0.listen_port=51820
    uci set network.wg0.addresses='10.9.0.1/24'
    uci commit network
    ifup wg0
  "
  sleep 2
}

verify_wg0() {
  ssh_run "ubus call network.interface.wg0 status 2>/dev/null | grep -q '\"proto\": \"wireguard\"'" && \
  ssh_run "ip link show wg0 2>/dev/null | grep -q 'POINTOPOINT'" && \
  ssh_run "wg show wg0 2>/dev/null | grep -q 'listening port: 51820'"
}

if verify_wg0; then
  echo "network.wg0 already correctly configured and up."
else
  echo "Creating baseline network.wg0 config (attempt 1)..."
  create_and_verify_wg0
  if verify_wg0; then
    echo "network.wg0 verified up after attempt 1."
  else
    echo "Verification failed after attempt 1 — reverting and retrying once..."
    ssh_run "uci revert network; ip link del wg0 2>/dev/null || true"
    sleep 1
    create_and_verify_wg0
    if verify_wg0; then
      echo "network.wg0 verified up after retry."
    else
      echo "FATAL: network.wg0 still not verifiably up after a revert+retry. Investigate manually." >&2
      exit 1
    fi
  fi
fi

echo "Real public key: $(ssh_run "wg show wg0 public-key")"
echo "=== 11-provision-wireguard-api.sh done ==="
```

Notes for the implementer: `/etc/wireguard-privkey` is created once and reused across re-runs of this script (so the public key — and hence the value the frontend will display — stays stable across idempotent re-provisioning, rather than silently rotating every time this script happens to run). `wg0`'s `disabled` UCI option is deliberately left unset (enabled) here — Task 2's endpoint is what flips it.

- [ ] **Step 3: Run the script against the live VM and verify by hand**

```bash
chmod +x docker/provision/11-provision-wireguard-api.sh
./docker/provision/11-provision-wireguard-api.sh
```
Expected: ends with `=== 11-provision-wireguard-api.sh done ===` and a real `Real public key: <base64>=` line. Then independently confirm (not just trusting the script's own echoed output):
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "wg show wg0; ip link show wg0; uci show network.wg0"
```
Expected: a real interface, a real listening port 51820, a real public key. Then re-run the script a second time with no changes and confirm it prints `wg0 already up with a real WireGuard interface — skipping package install and baseline config.` and `network.wg0 already correctly configured and up.` (idempotency).

- [ ] **Step 4: Commit**

```bash
git add docker/provision/11-provision-wireguard-api.sh
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): provision a real WireGuard server (wg0)"
```

---

### Task 2: `/api/wireguard` endpoint (GET + POST)

**Files:**
- Create: `docker/provision/www/api/wireguard`
- Modify: `docker/provision/11-provision-wireguard-api.sh` (append a deploy-and-verify step, mirroring `08-provision-wifi-api.sh`'s own `scp` + verify block)

- [ ] **Step 1: Write the endpoint**

```lua
#!/usr/bin/lua
-- /api/wireguard — GET + POST. Real WireGuard-server-backed status/toggle for
-- the VPN Server (WireGuard) screen. Reads/writes the baseline config created
-- by docker/provision/11-provision-wireguard-api.sh (see that script and
-- docker/facts.md Sections 13-14 for the confirmed live investigation this
-- endpoint is built on).
--
-- GET response shape:
--   {"running": true|false, "port": 51820, "publicKey": "<base64>", "subnet": "10.9.0.0/24"}
--
-- === running ===
-- `ubus call network.interface.wg0 status` (same real-liveness-signal idea as
-- Network & VLANs' /api/vlans reading `ip link show` — not a cached/assumed
-- value) reporting `"up": true` -> true. Anything else (down, no such
-- interface, ubus failure) -> false.
--
-- === port / publicKey ===
-- Always read live from `wg show wg0` (not from uci, which stores the
-- *private* key, never printed by this endpoint) — `listening port: N` and
-- `public key: <b64>` lines. If wg0 doesn't exist (e.g. mid-toggle-off),
-- these fall back to the port/subnet this VM was provisioned with (51820,
-- 10.9.0.0/24) and an empty publicKey string, rather than crashing.
--
-- === subnet ===
-- Hardcoded '10.9.0.0/24' — this is the one baseline value
-- 11-provision-wireguard-api.sh always provisions network.wg0.addresses as
-- (10.9.0.1/24), never user-editable through this screen in this wave (no
-- "add a peer"/"change subnet" UI exists yet) — same "narrow read-only
-- constant, not because it's technically unreadable but because there's
-- nothing else to disagree with it" reasoning as VLANs' hardcoded subnet
-- display would use if it needed one.
--
-- === POST (real on/off toggle) ===
--
-- POST body: {"enabled": true|false} — writes network.wg0.disabled
-- accordingly and reports the new running state.
--
-- Both directions confirmed live against this running VM before writing this
-- handler (docker/facts.md Section 14):
--   enabled:true  -> uci set network.wg0.disabled=0 ; commit ; ifup wg0
--   enabled:false -> uci set network.wg0.disabled=1 ; commit ; ifdown wg0
-- Confirmed both ways that the real kernel interface actually appears/
-- disappears (`ip link show wg0`), not just that the uci option flips.
--
-- Body parsing / write discipline: same hand-rolled json_parse_flat_object +
-- literal "true"/"false" string validation, and the same
-- write-then-readback-verify-then-commit-or-revert discipline, as
-- `wifi`/`adblock`'s POST handlers — adapted verbatim, see those files'
-- header comments for the full rationale.
--
-- Invalid/missing input is rejected with 400 and touches no config at all.
-- Unsupported methods (anything but GET/POST) get 405.

local EXPECTED_PORT = 51820
local EXPECTED_SUBNET = "10.9.0.0/24"

local function run(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return "" end
  local out = p:read("*a") or ""
  p:close()
  return (out:gsub("%s+$", ""))
end

local function uci_get(path)
  local out = run("uci get " .. path)
  if out == "" or out:match("^uci:") then return nil end
  return out
end

local function is_running()
  local out = run("ubus call network.interface.wg0 status")
  return out:find('"up": true', 1, true) ~= nil
end

local function wg_port_and_pubkey()
  local out = run("wg show wg0")
  if out == "" then return EXPECTED_PORT, "" end
  local port = out:match("listening port: (%d+)") or tostring(EXPECTED_PORT)
  local pubkey = out:match("public key: (%S+)") or ""
  return tonumber(port) or EXPECTED_PORT, pubkey
end

local function json_escape(s)
  s = tostring(s or "")
  return s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', c:byte())
  end)
end

local function shell_quote(s)
  s = tostring(s or "")
  s = s:gsub('[\1-\9\11-\31]', '')
  s = s:gsub('[\n\r]', ' ')
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function read_request_body()
  local len = tonumber(os.getenv("CONTENT_LENGTH") or "")
  if len and len > 0 then return io.read(len) or "" end
  return io.read("*a") or ""
end

-- === Narrow, defensive flat-JSON-object parser === (adapted verbatim from
-- wifi/adblock's json_parse_flat_object — see those files for the full
-- rationale on the deliberate true/"true" ambiguity this accepts.)
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

local function parse_enabled(body)
  local req = json_parse_flat_object(body)
  local v = req.enabled
  if v == "true" then return true end
  if v == "false" then return false end
  return nil
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
  local port, pubkey = wg_port_and_pubkey()
  print(string.format(
    '{"running":%s,"port":%d,"publicKey":"%s","subnet":"%s"}',
    is_running() and "true" or "false", port, json_escape(pubkey), EXPECTED_SUBNET
  ))

elseif method == "POST" then
  local body = read_request_body()
  local enabled_req = parse_enabled(body)

  if enabled_req == nil then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: enabled (must be a JSON boolean true or false)"}')
  else
    run("uci set network.wg0.disabled=" .. shell_quote(enabled_req and "0" or "1"))

    local readback = uci_get("network.wg0.disabled")
    local expected = enabled_req and "0" or nil -- disabled=0 reads back as "0"; disabled=1 reads back as "1"
    local readback_ok
    if enabled_req then
      readback_ok = (readback == "0")
    else
      readback_ok = (readback == "1")
    end

    if not readback_ok then
      run("uci revert network")
      send_headers(500)
      print('{"ok":false,"error":"failed to verify network.wg0.disabled write; reverted"}')
    else
      run("uci commit network")
      if enabled_req then run("ifup wg0") else run("ifdown wg0") end
      send_headers(200)
      print(string.format('{"ok":true,"running":%s}', enabled_req and "true" or "false"))
    end
  end

else
  local safe_method = tostring(method):gsub('[\\"%c]', '')
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', safe_method))
end
```

- [ ] **Step 2: Append the deploy-and-verify block to `11-provision-wireguard-api.sh`**

```sh

# --- Deploy the /api/wireguard endpoint ---
echo "Deploying /api/wireguard..."
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "$(dirname "$0")/www/api/wireguard" \
  "${SSH_TARGET}:/www/cgi-bin/api/wireguard"
ssh_run "chmod +x /www/cgi-bin/api/wireguard"

echo "Verifying it responds with real JSON..."
ssh_run "curl -s http://localhost/cgi-bin/api/wireguard" | grep -q '"running"'
echo "=== 11-provision-wireguard-api.sh done ==="
```
(This replaces the previous final `echo "=== ... done ==="` line from Step 2 of Task 1 — there should be exactly one such line, at the true end of the file.)

- [ ] **Step 3: Run and verify against the live VM**

```bash
./docker/provision/11-provision-wireguard-api.sh
curl -s http://localhost:8081/cgi-bin/api/wireguard
```
Expected: `{"running":true,"port":51820,"publicKey":"<real base64>","subnet":"10.9.0.0/24"}`. Then test the POST toggle both directions:
```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{"enabled":false}' http://localhost:8081/cgi-bin/api/wireguard
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "ip link show wg0"   # expect: can't find device
curl -s -X POST -H 'Content-Type: application/json' -d '{"enabled":true}' http://localhost:8081/cgi-bin/api/wireguard
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "ip link show wg0"   # expect: real interface back, same public key as before
```
Also test the 400 path: `curl -s -X POST -d '{"enabled":"nope"}' http://localhost:8081/cgi-bin/api/wireguard` → expect HTTP 400 and an `{"ok":false,...}` body.

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/wireguard docker/provision/11-provision-wireguard-api.sh
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/wireguard endpoint (GET status + POST toggle)"
```

---

### Task 3: Frontend — wire VPN Server (WireGuard) screen to real data

**Files:**
- Modify: `sadd-website.html` (the `advwireguard` entry inside the `screens` JSON blob, plus new JS near `renderGuestScreen`/`handleGuestWifiSwitchClick`, plus the `render()` dispatch block, plus the `state` object)

This is the third real hero-toggle screen (after Guest Wi-Fi and Ad Blocking) — follow `renderGuestScreen`/`handleGuestWifiSwitchClick` as the template almost exactly, extended with three additional read-only `.tech-row` values (Port, Public key, VPN subnet) the way About's version row and Settings' rows already establish the "read-only field swap by id" pattern.

- [ ] **Step 1: Add ids to the static markup**

In the `screens` object's `advwireguard` value (edit via a small Node.js script reading/parsing/re-serializing the JSON blob, the same way every prior wave's frontend task has — do NOT hand-edit the single-line JSON string with a text editor), make these targeted string replacements:

1. `<div class="th-main"><strong>WireGuard Server</strong><span>Running &middot; UDP port 51820</span></div><div class="switch on"></div>`
   → `<div class="th-main"><strong>WireGuard Server</strong><span id="wireguardStatusText">Running &middot; UDP port 51820</span></div><div class="switch on" id="wireguardSwitch"></div>`
   and wrap the whole hero in an id: the existing `<div class="toggle-hero" style="max-width:100%;margin-top:14px;">` → `<div class="toggle-hero" id="wireguardToggleHero" style="max-width:100%;margin-top:14px;">`

2. `<div class="tech-row"><div class="tr-label">Port</div><div class="tr-val">51820</div></div>`
   → `<div class="tech-row"><div class="tr-label">Port</div><div class="tr-val" id="wireguardPortVal">51820</div></div>`

3. `<div class="tech-row"><div class="tr-label">Public key</div><div class="tr-val">a8Kx&hellip;Qw2=</div></div>`
   → `<div class="tech-row"><div class="tr-label">Public key</div><div class="tr-val" id="wireguardPubkeyVal">a8Kx&hellip;Qw2=</div></div>`

4. `<div class="tech-row"><div class="tr-label">VPN <a href="#" data-goto="glossary" style="text-decoration:underline;color:inherit;">subnet</a></div><div class="tr-val">10.9.0.0/24</div></div>`
   → same but `<div class="tr-val" id="wireguardSubnetVal">10.9.0.0/24</div>`

Protocol and Hostname `.tech-row`s are NOT touched — Protocol is a fixed label ("WireGuard (UDP)", never varies), Hostname (`smith-family.saddvpn.com`) is a fictional DNS name this VM has no analog for, both stay static.

- [ ] **Step 2: Add `wireguardRenderId` to `state`**

In `sadd-website.html`, find the `const state = { ... }` line (search for `vlansRenderId: 0`) and add `, wireguardRenderId: 0` before the closing `}`.

- [ ] **Step 3: Add the render/click-handler JS**

Insert immediately after `handleGuestWifiSwitchClick`'s closing `}` (before the Diagnostics & Logs section comment):

```js
  // ---- VPN Server (WireGuard) screen: the .toggle-hero's .switch (id="wireguardSwitch")
  //      becomes a REAL write control backed by GET/POST /cgi-bin/api/wireguard's `running`
  //      field, plus three read-only .tech-row values (Port/Public key/VPN subnet) swapped
  //      by id — same "real read-only field" pattern as About's version row. Everything
  //      else on this screen (Advanced toggles, Full-LAN-access warning, Client devices
  //      list, Performance stat, third-party-VPN routing, Site-to-site, AmneziaWG) stays
  //      static per this wave's scope — see the design spec's Wave 5 note. ----
  function setWireguardSwitchVisual(sw, statusTextEl, portEl, pubkeyEl, running, port, publicKey){
    sw.classList.toggle('on', running);
    sw.setAttribute('aria-checked', running ? 'true' : 'false');
    if(statusTextEl) setEscapedText(statusTextEl, (running ? 'Running' : 'Stopped') + ' · UDP port ' + port);
    if(portEl) setEscapedText(portEl, String(port));
    if(pubkeyEl && publicKey) setEscapedText(pubkeyEl, publicKey);
  }

  async function renderWireguardScreen(){
    // same stale-fetch-race guard as renderGuestScreen/renderAdblockScreen/etc.
    const myRenderId = state.wireguardRenderId;
    const data = await fetchRouterApi('/cgi-bin/api/wireguard');
    if(state.screen !== 'advwireguard' || state.wireguardRenderId !== myRenderId) return;
    const heroEl = document.getElementById('wireguardToggleHero');
    const sw = document.getElementById('wireguardSwitch');
    const statusTextEl = document.getElementById('wireguardStatusText');
    const portEl = document.getElementById('wireguardPortVal');
    const pubkeyEl = document.getElementById('wireguardPubkeyVal');
    const subnetEl = document.getElementById('wireguardSubnetVal');
    if(!heroEl || !sw) return;
    const hasData = data && typeof data === 'object';
    if(hasData){
      setWireguardSwitchVisual(sw, statusTextEl, portEl, pubkeyEl, !!data.running, data.port, data.publicKey);
      if(subnetEl && data.subnet) setEscapedText(subnetEl, data.subnet);
    }
    // Switch left enabled even on failure — a click still safely round-trips through
    // fetchRouterApiWithStatus and reverts cleanly (see handleWireguardSwitchClick), same
    // reasoning as Guest Wi-Fi/Ad Blocking's switches.
    syncFallbackNotice(heroEl, hasData, "Can't reach router — showing default VPN server state");
  }

  // ---- WireGuard switch click: REAL write, POST /cgi-bin/api/wireguard {enabled}. Same
  //      optimistic-update design as handleGuestWifiSwitchClick/handleAdblockSwitchClick:
  //      flips immediately, disabled (`.pending`) only for the request's duration, reverts
  //      to exactly its prior state (switch + status text) on a confirmed failure with a
  //      4s auto-dismissing notice. Uses a longer explicit timeout (6000ms, not the shared
  //      1500ms default) — this endpoint's real handler runs `ifup`/`ifdown wg0` through
  //      netifd, and Task 1's own provisioning script waits 2s after `ifup wg0` before its
  //      own verification even considers checking, so the same conservative budget Ad
  //      Blocking's dnsmasq-restart path uses is applied here too rather than assuming
  //      network interface bring-up is as fast as the wireless.guest.disabled toggle was.
  //      Same "no state.wireguardRenderId guard needed" reasoning as
  //      handleGuestWifiSwitchClick/handleAdblockSwitchClick — sw/heroEl/etc. are captured
  //      by reference before the await, and render() always fully replaces appContent on
  //      navigation. ----
  async function handleWireguardSwitchClick(sw){
    if(sw.dataset.pending === 'true') return;
    const heroEl = sw.closest('.toggle-hero');
    const statusTextEl = document.getElementById('wireguardStatusText');
    const portEl = document.getElementById('wireguardPortVal');
    const pubkeyEl = document.getElementById('wireguardPubkeyVal');
    const wasOn = sw.classList.contains('on');
    const nextOn = !wasOn;
    const currentPort = portEl ? portEl.textContent : '51820';
    const currentPubkey = pubkeyEl ? pubkeyEl.textContent : '';
    sw.dataset.pending = 'true';
    sw.classList.add('pending');
    setWireguardSwitchVisual(sw, statusTextEl, portEl, pubkeyEl, nextOn, currentPort, currentPubkey);
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/wireguard', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({enabled: nextOn})
    }, 6000);
    sw.dataset.pending = 'false';
    sw.classList.remove('pending');
    if(result === null || !result.ok){
      setWireguardSwitchVisual(sw, statusTextEl, portEl, pubkeyEl, wasOn, currentPort, currentPubkey);
      const msg = (result && result.data && result.data.error) ? result.data.error
        : (result === null ? "Can't reach router — VPN server not changed." : ('Request failed (status '+result.status+') — VPN server not changed.'));
      if(heroEl){
        const notice = syncFallbackNotice(heroEl, false, msg);
        setTimeout(()=>notice.remove(), 4000);
      }
    }
  }
```

- [ ] **Step 4: Wire the dispatch points**

In `render()`, immediately after the existing `if(state.screen === 'advnetwork'){ ... }` line, add:
```js
      // VPN Server (WireGuard) screen: same pattern — static hero-toggle ("switch on") and
      // Port/Public key values already showing (no blank flash), bump the render token,
      // kick off the real-data fetch/overlay async on top.
      if(state.screen === 'advwireguard'){ state.wireguardRenderId++; renderWireguardScreen(); }
```

In the global click handler, immediately after the existing `if(sw.id === 'adblockSwitch'){ handleAdblockSwitchClick(sw); return; }` line, add:
```js
      // VPN Server (WireGuard)'s switch is likewise a REAL write control (POST
      // /cgi-bin/api/wireguard), intercepted the same way, before the generic branch below.
      if(sw.id === 'wireguardSwitch'){ handleWireguardSwitchClick(sw); return; }
```

- [ ] **Step 5: Verify in a real browser against the live VM**

Serve the file (`python3 -m http.server` is unavailable per this session's established Node-only tooling — use any static file server, e.g. `npx serve` from the repo root, or open the file directly and confirm the `file://` guard behavior separately), navigate to VPN Server (WireGuard), and confirm: real "Running · UDP port 51820" (or "Stopped" if toggled off first), real public key matching `wg show wg0` output on the VM, the switch click flips the real interface (`ip link show wg0` on the VM reflects it within a few seconds), and a Docker `stop` mid-request correctly shows the revert + notice.

- [ ] **Step 6: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire VPN Server (WireGuard) hero toggle + connection details to real data"
```

---

### Task 4: `/api/ssh-key` endpoint (POST-only rotate)

**Files:**
- Create: `docker/provision/www/api/ssh-key`
- Create: `docker/provision/12-provision-ssh-key-api.sh`
- Modify: `docker/README.md:Provisioning section` (add step 12)

Unlike Task 1/2, this endpoint needs no baseline VM state to provision (dropbear is already running on every fresh boot) — the provisioning script only deploys the endpoint file and verifies it responds, mirroring `06-provision-system-info-api.sh`/`07-provision-logs-api.sh`'s shape (stateless endpoint, nothing to create first) rather than `08`'s.

- [ ] **Step 1: Write the endpoint**

```lua
#!/usr/bin/lua
-- /api/ssh-key — POST only. Real dropbear host-key rotation for the
-- Developer & API Access screen's "Rotate SSH key" button. Confirmed live
-- against this running VM before writing this handler (docker/facts.md
-- Section 14): deleting both host key files and restarting dropbear makes
-- dropbear auto-regenerate fresh ones (standard OpenWrt behavior, no
-- `dropbearkey` invocation needed here), with a genuinely different
-- fingerprint every time.
--
-- POST response shape (no request body needed/read):
--   {"ok": true, "fingerprint": "SHA256:<...>"}
-- or on failure:
--   {"ok": false, "error": "..."}
--
-- Safety note (see docker/facts.md Section 14 for the full reasoning): this
-- is safe for THIS project's own verification workflow specifically because
-- every SSH connection this project makes always passes
-- `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` — there is no
-- persisted known_hosts entry anywhere for a rotated key to conflict with. A
-- real deployment using normal host-key pinning would need to separately warn
-- the operator their client will show a "host key changed" prompt after
-- calling this — out of scope to simulate here (the screen's own copy
-- already says "invalidates the old one immediately", which is accurate).
--
-- Only the RSA host key's fingerprint is returned (matching the single
-- fingerprint a real SSH client shows on first connect) — the ed25519 key is
-- rotated identically but its own fingerprint isn't surfaced in this JSON,
-- since the mockup's "Rotate now" button has no per-key-type UI to populate.

local function run(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return "" end
  local out = p:read("*a") or ""
  p:close()
  return (out:gsub("%s+$", ""))
end

local function json_escape(s)
  s = tostring(s or "")
  return s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', c:byte())
  end)
end

local function send_headers(status)
  local reasons = { [405]="Method Not Allowed", [500]="Internal Server Error" }
  if status and status ~= 200 then
    print("Status: " .. status .. " " .. (reasons[status] or "Error"))
  end
  print("Content-Type: application/json\n")
end

local method = os.getenv("REQUEST_METHOD") or "GET"

if method == "POST" then
  run("rm -f /etc/dropbear/dropbear_rsa_host_key /etc/dropbear/dropbear_ed25519_host_key")
  run("/etc/init.d/dropbear restart")
  -- dropbear needs a brief moment after restart before the new key file is
  -- fully written and dropbearkey can read it back — confirmed live this is
  -- not needed in interactive testing (restart is synchronous enough there),
  -- but a short defensive sleep here costs nothing and removes any race for
  -- a CGI-triggered restart under uhttpd's own process model.
  os.execute("sleep 1")
  local fp = run("dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null | grep -i Fingerprint")
  local fingerprint = fp:match("Fingerprint:%s*(%S+)")

  if fingerprint then
    send_headers(200)
    print(string.format('{"ok":true,"fingerprint":"%s"}', json_escape(fingerprint)))
  else
    send_headers(500)
    print('{"ok":false,"error":"key rotation ran but the new fingerprint could not be read back"}')
  end

else
  local safe_method = tostring(method):gsub('[\\"%c]', '')
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', safe_method))
end
```

- [ ] **Step 2: Write the provisioning script**

```sh
#!/bin/sh
set -e

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_TARGET="root@${OPENWRT_HOST}"

echo "=== 12-provision-ssh-key-api.sh ==="
echo "Deploying /api/ssh-key (stateless — dropbear is already running on every fresh boot,"
echo "nothing to provision beyond the endpoint file itself)..."

scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "$(dirname "$0")/www/api/ssh-key" \
  "${SSH_TARGET}:/www/cgi-bin/api/ssh-key"
ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "chmod +x /www/cgi-bin/api/ssh-key"

echo "Verifying GET is correctly rejected (405, this endpoint is POST-only)..."
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://${OPENWRT_HOST}:8081/cgi-bin/api/ssh-key")
if [ "$STATUS" != "405" ]; then
  echo "FATAL: expected 405 for GET /api/ssh-key, got ${STATUS}" >&2
  exit 1
fi

echo "=== 12-provision-ssh-key-api.sh done ==="
```

- [ ] **Step 3: Run and verify against the live VM**

```bash
chmod +x docker/provision/12-provision-ssh-key-api.sh
./docker/provision/12-provision-ssh-key-api.sh
```
Then confirm the real rotation, independently of the endpoint's own claim:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key | grep Fingerprint"
curl -s -X POST http://localhost:8081/cgi-bin/api/ssh-key
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key | grep Fingerprint"
```
Expected: the two `dropbearkey` fingerprints differ, and the curl response's `fingerprint` field matches the second one exactly.

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/ssh-key docker/provision/12-provision-ssh-key-api.sh
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/ssh-key endpoint (real dropbear host-key rotation)"
```

---

### Task 5: Frontend — wire "Rotate SSH key" button on Developer & API Access

**Files:**
- Modify: `sadd-website.html` (the `advapi` entry in `screens`, plus new JS, plus the global click handler)

- [ ] **Step 1: Add ids to the static markup**

In `screens['advapi']`, via the same Node.js JSON-parse-edit-reserialize approach as every prior frontend task:

`<button class="btn btn-secondary" style="width:auto;padding:7px 14px;font-size:12px;">Rotate now</button>`
(the one immediately following "Rotate SSH key" / "Generates a new key...") →
`<button class="btn btn-secondary" id="sshRotateBtn" style="width:auto;padding:7px 14px;font-size:12px;">Rotate now</button><span class="mono-badge" id="sshRotateStatus" style="margin-left:8px;display:none;"></span>`

(There is exactly one `<button class="btn btn-secondary" style="width:auto;padding:7px 14px;font-size:12px;">Rotate now</button>` string in the whole `screens` blob — confirm this with a grep count of 1 before editing, since the edit script matches on that literal substring.)

- [ ] **Step 2: Add the click-handler JS**

Insert immediately after `handleWireguardSwitchClick`'s closing `}` from Task 3:

```js
  // ---- Developer & API Access: "Rotate now" button (id="sshRotateBtn") is a REAL write
  //      action, POST /cgi-bin/api/ssh-key — genuinely regenerates dropbear's host key on
  //      the VM. Unlike every other write control in this file, this isn't a toggle with
  //      two stable states to optimistically flip between — it's a one-shot action with a
  //      transient result (a new fingerprint), so the pattern here is simpler: disable the
  //      button + show "Rotating..." for the request's duration, then show either the new
  //      fingerprint or an error, auto-dismissing after 6s either way. No revert is needed
  //      on failure (there's no prior visual state to revert to — the button was never
  //      showing a fingerprint before the click). ----
  async function handleSshRotateClick(btn){
    if(btn.dataset.pending === 'true') return;
    const statusEl = document.getElementById('sshRotateStatus');
    btn.dataset.pending = 'true';
    btn.disabled = true;
    if(statusEl){ statusEl.style.display = 'inline'; setEscapedText(statusEl, 'Rotating…'); }
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/ssh-key', { method: 'POST' }, 3000);
    btn.dataset.pending = 'false';
    btn.disabled = false;
    if(statusEl){
      if(result && result.ok && result.data && result.data.fingerprint){
        setEscapedText(statusEl, 'New key: ' + result.data.fingerprint);
      } else {
        const msg = (result && result.data && result.data.error) ? result.data.error
          : (result === null ? "Can't reach router — key not rotated." : ('Request failed (status '+result.status+') — key not rotated.'));
        setEscapedText(statusEl, msg);
      }
      setTimeout(()=>{ statusEl.style.display = 'none'; }, 6000);
    }
  }
```

- [ ] **Step 3: Wire the dispatch point**

In the global click handler, the "Rotate now" button has no existing generic hook (it's a plain `<button class="btn btn-secondary">` with no `data-action`/`data-firewall-*` attribute today) — add a new branch. Place it right before the existing `const fwAddCancel = ...` block (i.e., among the other specific-id/data-attribute checks, before the generic `[data-goto]`/`[data-action]`/`.switch` fallbacks further down):

```js
    const sshRotateBtn = e.target.closest('#sshRotateBtn');
    if(sshRotateBtn){
      if(!sshRotateBtn.disabled) handleSshRotateClick(sshRotateBtn);
      return;
    }
```

- [ ] **Step 4: Verify in a real browser against the live VM**

Navigate to Developer & API Access, click "Rotate now", confirm the button disables + shows "Rotating…" then a real `New key: SHA256:...` fingerprint, confirm via SSH that `dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key` matches it, click again to confirm it rotates to a **different** fingerprint the second time, and confirm the failure path (stop the container mid-click) shows the error text and doesn't leave the button permanently disabled.

- [ ] **Step 5: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Developer & API Access' Rotate SSH key button to a real action"
```

---

### Task 6: Provision the per-device pause mechanism (cron sweep + seeded crontab)

**Files:**
- Create: `docker/provision/www/lib/devpause-sweep.sh` (deployed onto the VM as `/usr/bin/devpause-sweep.sh`)
- Create: `docker/provision/13-provision-devpause-api.sh`
- Modify: `docker/README.md:Provisioning section` (add step 13)

This is the baseline-state half of the Per-Device Controls feature: a script that runs every minute on the VM, finds any `devpause-*` firewall rule whose stored expiry has passed, and removes it — real auto-expiry, not a client-side timer that only pretends the block ends.

- [ ] **Step 1: Write the sweep script**

```sh
#!/bin/sh
# /usr/bin/devpause-sweep.sh — run every minute by cron (see
# 13-provision-devpause-api.sh). Finds any uci firewall rule this project
# created for a per-device "pause internet" action (named `devpause-<mac
# with colons stripped>`, carrying a custom `paused_until` uci option — an
# epoch-seconds timestamp; uci tolerates arbitrary option names on a rule
# section, and fw4 silently ignores ones it doesn't recognize, confirmed live)
# whose paused_until has passed, and removes it — real auto-expiry.
#
# Real device-pause creation is /cgi-bin/api/device-pause's job (Task 7); this
# script only ever DELETES expired ones, never creates them.

NOW=$(date +%s)
CHANGED=0

# Find every uci firewall rule section this project created for a per-device
# pause (name starts with "devpause-"), extract just its section id, using
# only POSIX sed/grep (busybox ash, not bash/gawk — matches every other
# script in this directory's tooling assumptions).
for id in $(uci show firewall | grep "\.name='devpause-" | sed -n "s/^firewall\.\([^.]*\)\.name=.*/\1/p"); do
  paused_until=$(uci -q get "firewall.${id}.paused_until")
  if [ -n "$paused_until" ] && [ "$paused_until" -le "$NOW" ] 2>/dev/null; then
    logger -t devpause-sweep "removing expired pause: firewall.${id} (paused_until=${paused_until}, now=${NOW})"
    uci -q delete "firewall.${id}"
    CHANGED=1
  fi
done

if [ "$CHANGED" = "1" ]; then
  uci commit firewall
  fw4 reload >/dev/null 2>&1
fi
```

- [ ] **Step 2: Write the provisioning script**

```sh
#!/bin/sh
set -e

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

echo "=== 13-provision-devpause-api.sh ==="

echo "Deploying the sweep script..."
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "$(dirname "$0")/www/lib/devpause-sweep.sh" \
  "${SSH_TARGET}:/usr/bin/devpause-sweep.sh"
ssh_run "chmod +x /usr/bin/devpause-sweep.sh"

echo "Seeding /etc/crontabs/root and starting cron if not already running..."
echo "(cron's own init script silently no-ops unless /etc/crontabs/ already has a file —"
echo "see docker/facts.md Section 13 — so this must run before /etc/init.d/cron start.)"

CRON_LINE='* * * * * /usr/bin/devpause-sweep.sh'
ssh_run "
  touch /etc/crontabs/root
  grep -qF \"${CRON_LINE}\" /etc/crontabs/root || echo \"${CRON_LINE}\" >> /etc/crontabs/root
  /etc/init.d/cron enable
  /etc/init.d/cron start
"

echo "Verifying crond is actually running (not just trusting the init script's exit code —"
echo "see docker/facts.md Section 13 on why that alone is not proof)..."
sleep 1
if ! ssh_run "pgrep crond >/dev/null"; then
  echo "crond not running after start — restarting once..."
  ssh_run "/etc/init.d/cron restart"
  sleep 1
  ssh_run "pgrep crond >/dev/null"
fi

echo "=== 13-provision-devpause-api.sh done ==="
```

- [ ] **Step 3: Run and verify against the live VM**

```bash
mkdir -p docker/provision/www/lib
chmod +x docker/provision/13-provision-devpause-api.sh
./docker/provision/13-provision-devpause-api.sh
```
Then fault-inject to prove the sweep genuinely works (don't just trust that cron is running — prove it removes something):
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
  uci add firewall rule
  uci set firewall.@rule[-1].name='devpause-aabbccddeeff'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].src_mac='aa:bb:cc:dd:ee:ff'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].target='REJECT'
  uci set firewall.@rule[-1].proto='all'
  uci set firewall.@rule[-1].paused_until=\$(( \$(date +%s) - 5 ))
  uci commit firewall
  fw4 reload
  uci show firewall | grep devpause-aabbccddeeff
"
```
Expected: the rule exists. Then wait up to 60s (cron runs on the minute) and re-check:
```bash
sleep 65
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "uci show firewall | grep devpause-aabbccddeeff; echo exit=\$?"
```
Expected: no match, `exit=1` — the sweep genuinely removed the expired rule.

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/lib/devpause-sweep.sh docker/provision/13-provision-devpause-api.sh
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): provision a real cron sweep for expired per-device pauses"
```

---

### Task 7: `/api/device-pause` endpoint (GET status + POST create)

**Files:**
- Create: `docker/provision/www/api/device-pause`
- Modify: `docker/provision/13-provision-devpause-api.sh` (append deploy-and-verify)

- [ ] **Step 1: Write the endpoint**

```lua
#!/usr/bin/lua
-- /api/device-pause — GET (status) + POST (create/replace a pause). Real
-- per-MAC firewall block for the Per-Device Controls screen's "Pause
-- internet" chips. Auto-expiry is handled by a separate cron-driven sweep
-- (docker/provision/www/lib/devpause-sweep.sh, see
-- docker/provision/13-provision-devpause-api.sh) — this endpoint only ever
-- creates/replaces/reads the rule, never deletes an expired one itself (no
-- request happens to trigger that at exactly the right moment).
--
-- GET /cgi-bin/api/device-pause?mac=<mac>
--   -> {"paused": true|false, "remainingSeconds": <int, 0 if not paused>}
--
-- POST /cgi-bin/api/device-pause  body: {"mac": "<mac>", "minutes": <int>}
--   -> {"ok": true, "paused": true, "remainingSeconds": <int>}
--
-- === Rule shape — confirmed live (docker/facts.md Section 14) ===
-- A rule with src='lan' + src_mac set but no `dest` only lands in the
-- input_lan nft chain (traffic addressed to the router itself) — NOT what a
-- "pause internet" feature needs. dest='wan' is required to land the rule in
-- forward_lan as a real REJECT of the device's outbound-bound traffic. This
-- VM's wan zone is topologically unreachable (no real WAN interface — see
-- docker/facts.md Section 1/Task 7), so end-to-end "device actually loses
-- internet" isn't testable here, but the rule itself is real, uci/fw4-backed
-- config, the same "prove the mechanism" bar Wave 1's port-forwarding work
-- already established for this project.
--
-- Rule naming: `devpause-<mac with colons stripped, lowercased>` — a stable,
-- deterministic name per device, so a second POST for the same MAC finds and
-- REPLACES its own prior rule (extending/shortening a pause) rather than
-- accumulating duplicate rules for the same device.
--
-- MAC validation: a strict 6-octet colon-hex pattern — anything else is
-- rejected 400 before any uci command runs (this value is interpolated into
-- both a uci option value, via shell_quote, and a uci section NAME derived
-- from it, so it's validated as a whole shape up front rather than only
-- escaped at use).
--
-- minutes validation: an integer, 1-1440 inclusive (1 minute to 24 hours —
-- generous enough to cover the mockup's three chips: 15 min, 1 hr, and
-- "Until tomorrow", which the frontend computes client-side as "minutes
-- until next local midnight" and sends as a plain minutes value like any
-- other duration — see sadd-website.html's handleDevicePauseChipClick).
--
-- Write discipline: same write-then-readback-verify-then-commit-or-revert as
-- every other write endpoint in this directory — adapted for a rule ADD
-- rather than a single-option SET, using list_redirect_sections()'s
-- id/field-parsing approach (adapted from firewall-rules) generalized to
-- `rule` sections.

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

local function is_valid_mac(v)
  if type(v) ~= "string" then return false end
  return v:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

local function mac_to_rule_name(mac)
  return "devpause-" .. mac:lower():gsub(":", "")
end

-- Parses `uci show firewall` into id -> {name=..., paused_until=...} for
-- every `rule`-type section — adapted from firewall-rules'
-- list_redirect_sections(), generalized from "redirect" to "rule".
local function list_rule_sections()
  local output = run("uci show firewall")
  local order = {}
  local is_rule = {}
  local fields = {}
  for line in output:gmatch("[^\n]+") do
    local lhs, rhs = line:match("^(.-)=(.*)$")
    if lhs and rhs then
      local rest = lhs:match("^firewall%.(.+)$")
      if rest then
        local dot = rest:find("%.")
        if dot then
          local id = rest:sub(1, dot - 1)
          local field = rest:sub(dot + 1)
          if is_rule[id] then
            local val = rhs:match("^'(.-)'$")
            if not val then val = rhs end
            fields[id][field] = val
          end
        else
          local id = rest
          local typ = rhs:match("^'?(.-)'?$")
          if typ == "rule" and not is_rule[id] then
            is_rule[id] = true
            order[#order + 1] = id
            fields[id] = {}
          end
        end
      end
    end
  end
  return order, fields
end

local function find_pause_rule(rule_name)
  local order, fields = list_rule_sections()
  for _, id in ipairs(order) do
    if fields[id].name == rule_name then return id, fields[id] end
  end
  return nil, nil
end

local function json_escape(s)
  s = tostring(s or "")
  return s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', c:byte())
  end)
end

local function read_request_body()
  local len = tonumber(os.getenv("CONTENT_LENGTH") or "")
  if len and len > 0 then return io.read(len) or "" end
  return io.read("*a") or ""
end

-- Same hand-rolled flat-JSON-object parser as every other write endpoint —
-- adapted verbatim (see wifi/adblock's header comments for the full
-- rationale).
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

local function parse_query_mac()
  local qs = os.getenv("QUERY_STRING") or ""
  for pair in qs:gmatch("[^&]+") do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k == "mac" then
      -- minimal percent-decode for the colon-heavy MAC values this endpoint expects
      v = v:gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
      return v
    end
  end
  return nil
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
  local mac = parse_query_mac()
  if not is_valid_mac(mac) then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required query param: mac (must be AA:BB:CC:DD:EE:FF form)"}')
  else
    local _, fields = find_pause_rule(mac_to_rule_name(mac))
    send_headers(200)
    if fields and fields.paused_until then
      local remaining = tonumber(fields.paused_until) - os.time()
      if remaining and remaining > 0 then
        print(string.format('{"paused":true,"remainingSeconds":%d}', remaining))
      else
        print('{"paused":false,"remainingSeconds":0}')
      end
    else
      print('{"paused":false,"remainingSeconds":0}')
    end
  end

elseif method == "POST" then
  local body = read_request_body()
  local req = json_parse_flat_object(body)
  local mac = req.mac
  local minutes = tonumber(req.minutes)

  if not is_valid_mac(mac) then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: mac (must be AA:BB:CC:DD:EE:FF form)"}')
  elseif not minutes or minutes ~= math.floor(minutes) or minutes < 1 or minutes > 1440 then
    send_headers(400)
    print('{"ok":false,"error":"missing or invalid required field: minutes (integer, 1-1440)"}')
  else
    local rule_name = mac_to_rule_name(mac)
    local expires_at = os.time() + (minutes * 60)

    -- Replace any existing pause rule for this MAC (extend/shorten), rather
    -- than accumulating duplicates.
    local existing_id = find_pause_rule(rule_name)
    if existing_id then run("uci -q delete firewall." .. existing_id) end

    run("uci add firewall rule")
    run("uci set firewall.@rule[-1].name=" .. shell_quote(rule_name))
    run("uci set firewall.@rule[-1].src=" .. shell_quote("lan"))
    run("uci set firewall.@rule[-1].src_mac=" .. shell_quote(mac))
    run("uci set firewall.@rule[-1].dest=" .. shell_quote("wan"))
    run("uci set firewall.@rule[-1].target=" .. shell_quote("REJECT"))
    run("uci set firewall.@rule[-1].proto=" .. shell_quote("all"))
    run("uci set firewall.@rule[-1].paused_until=" .. shell_quote(tostring(expires_at)))

    local _, readback_fields = find_pause_rule(rule_name)
    local readback_ok = readback_fields
      and readback_fields.src_mac == mac
      and readback_fields.dest == "wan"
      and readback_fields.target == "REJECT"
      and readback_fields.paused_until == tostring(expires_at)

    if not readback_ok then
      run("uci revert firewall")
      send_headers(500)
      print('{"ok":false,"error":"failed to verify the pause rule write; reverted"}')
    else
      run("uci commit firewall")
      run("fw4 reload")
      send_headers(200)
      print(string.format('{"ok":true,"paused":true,"remainingSeconds":%d}', minutes * 60))
    end
  end

else
  local safe_method = tostring(method):gsub('[\\"%c]', '')
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', safe_method))
end
```

- [ ] **Step 2: Append the deploy-and-verify block to `13-provision-devpause-api.sh`**

```sh

# --- Deploy the /api/device-pause endpoint ---
echo "Deploying /api/device-pause..."
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "$(dirname "$0")/www/api/device-pause" \
  "${SSH_TARGET}:/www/cgi-bin/api/device-pause"
ssh_run "chmod +x /www/cgi-bin/api/device-pause"

echo "Verifying it responds correctly..."
curl -s "http://${OPENWRT_HOST}:8081/cgi-bin/api/device-pause?mac=aa:bb:cc:dd:ee:ff" | grep -q '"paused":false'
echo "=== 13-provision-devpause-api.sh done ==="
```
(Replaces the previous final `echo "=== ... done ==="` line — exactly one such line at the true end of the file.)

- [ ] **Step 3: Run and verify against the live VM**

```bash
./docker/provision/13-provision-devpause-api.sh
curl -s "http://localhost:8081/cgi-bin/api/device-pause?mac=11:22:33:44:55:66"
```
Expected: `{"paused":false,"remainingSeconds":0}`. Then create a real pause and confirm both the API's own report and the real uci/nft state independently:
```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{"mac":"11:22:33:44:55:66","minutes":2}' http://localhost:8081/cgi-bin/api/device-pause
curl -s "http://localhost:8081/cgi-bin/api/device-pause?mac=11:22:33:44:55:66"   # expect paused:true, remainingSeconds near 120
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "nft list ruleset | grep -A1 '11:22:33:44:55:66'"   # expect a real forward_lan reject rule
```
Then confirm Task 6's cron sweep genuinely removes it once expired (wait past the 2 minutes + up to 60s for the next cron tick), and confirm a second POST for the same MAC replaces rather than duplicates (`uci show firewall | grep -c "devpause-112233445566"` stays 1 after two POSTs). Also test the 400 paths (bad MAC, missing minutes, minutes=0, minutes=99999).

- [ ] **Step 4: Commit**

```bash
git add docker/provision/www/api/device-pause docker/provision/13-provision-devpause-api.sh
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(docker): add /api/device-pause endpoint (real per-MAC auto-expiring block)"
```

---

### Task 8: Frontend — real device navigation + real "Pause internet" chips

**Files:**
- Modify: `sadd-website.html` (`renderDeviceRow`, the `devcontrols` entry in `screens`, new JS, `render()` dispatch, the global click handler, `state`)

This is the task that links the two already-real screens (Devices, Per-Device Controls) together for the first time. Read `renderDeviceRow`/`renderDevicesScreen` (Devices) and the full `devcontrols` raw markup before starting.

- [ ] **Step 1: Add real device identity to `renderDeviceRow`**

In `sadd-website.html`, modify `renderDeviceRow(d)` (search for `function renderDeviceRow(d){`) to stamp `data-*` attributes onto the `.list-item` div, so the click handler can read the clicked device's identity directly off the DOM (matching this file's existing `data-firewall-delete-id`-style idiom) — change:

```js
    return '<div class="list-item"><div class="li-icon">'+genericDeviceIconSvg+'</div><div class="li-main"><strong>'+name+'</strong>'+ipLine+'</div><span class="status-pill '+(online?'online':'offline')+'">'+(online?'Online':'Offline')+'</span></div>';
```
to:
```js
    const mac = d.mac ? escapeHtml(d.mac) : '';
    return '<div class="list-item" data-device-mac="'+mac+'" data-device-name="'+name+'" data-device-ip="'+(d.ip?escapeHtml(d.ip):'')+'" data-device-online="'+(online?'1':'0')+'"><div class="li-icon">'+genericDeviceIconSvg+'</div><div class="li-main"><strong>'+name+'</strong>'+ipLine+'</div><span class="status-pill '+(online?'online':'offline')+'">'+(online?'Online':'Offline')+'</span></div>';
```
(Confirm the real `/api/devices` GET response includes a `mac` field before this step — read `docker/provision/www/api/devices` to confirm the exact field name; adjust `d.mac` to match if it's spelled differently.)

- [ ] **Step 2: Add `state.selectedDevice` and a `devcontrolsRenderId` counter**

In `state`, add `, selectedDevice: null, devcontrolsRenderId: 0` (a real device's `{mac, name, ip, online}`, or `null` when devcontrols is reached via its original static path from Parental Controls — in which case the screen renders exactly as it always has, no real-data overlay at all, same "no real device context, stay static" rule every other screen's fallback follows).

- [ ] **Step 3: Add ids to the `devcontrols` static markup**

Via the Node.js JSON-parse-edit approach, in `screens['devcontrols']`:

1. `<div class="detail-header"><div class="dh-icon">...</div><div><strong style="display:block;font-size:17px;">Emma's iPhone</strong><span style="font-size:13px;color:var(--muted);">Phone · Part of Emma's profile</span></div></div>`
   → add ids: `<strong id="devcontrolsDeviceName" style="display:block;font-size:17px;">Emma's iPhone</strong><span id="devcontrolsDeviceSub" style="font-size:13px;color:var(--muted);">Phone · Part of Emma's profile</span>`

2. `<div class="sec-label mt-24">Pause internet</div>\n              <div class="timer-row">` → add an id to the timer-row: `<div class="timer-row" id="devicePauseTimerRow">`

- [ ] **Step 4: Add the render/click-handler JS**

Insert after `handleSshRotateClick`'s closing `}` from Task 5:

```js
  // ---- Per-Device Controls: reached with real device context (state.selectedDevice) for
  //      the first time via a click on a real Devices-list row (see the .list-item click
  //      handler below). When reached that way, the detail header becomes the real
  //      device's name/MAC and the "Pause internet" chips (id="devicePauseTimerRow")
  //      become a REAL write control, GET/POST /cgi-bin/api/device-pause. When reached via
  //      its original static path (the "Emma's devices" sidebar from Parental Controls,
  //      state.selectedDevice is null), the screen renders exactly as it always has —
  //      fully static, chips revert to their original cosmetic-only click behavior (see
  //      the generic .timer-chip branch in the click handler below, which this real path
  //      intercepts BEFORE, the same "specific id/state check before the generic branch"
  //      idiom as guestWifiSwitch/adblockSwitch). Bedtime, the content-filter radio group,
  //      and the blocked-apps list are explicitly out of scope for this wave (see the
  //      design spec's Wave 5 note) and are never touched here. ----
  function formatRemaining(seconds){
    if(seconds >= 3600) return Math.round(seconds/3600) + ' hr';
    return Math.round(seconds/60) + ' min';
  }

  async function renderDevcontrolsScreen(){
    const dev = state.selectedDevice;
    if(!dev || !dev.mac) return; // reached via the original static path — nothing to overlay
    const myRenderId = state.devcontrolsRenderId;
    const nameEl = document.getElementById('devcontrolsDeviceName');
    const subEl = document.getElementById('devcontrolsDeviceSub');
    const timerRow = document.getElementById('devicePauseTimerRow');
    if(nameEl) setEscapedText(nameEl, dev.name || dev.mac);
    if(subEl) setEscapedText(subEl, (dev.online ? 'Online' : 'Offline') + (dev.ip ? ' · ' + dev.ip : ''));
    if(timerRow) timerRow.dataset.mac = dev.mac; // marks this timer-row as a REAL pause control for the click handler below

    const data = await fetchRouterApi('/cgi-bin/api/device-pause?mac=' + encodeURIComponent(dev.mac));
    if(state.screen !== 'devcontrols' || state.devcontrolsRenderId !== myRenderId) return;
    if(timerRow && data && typeof data === 'object'){
      timerRow.querySelectorAll('.timer-chip').forEach(c=>c.classList.remove('active'));
      if(data.paused && data.remainingSeconds > 0){
        // no static chip maps exactly onto an arbitrary remaining duration — show it as a
        // small appended label on the row instead of forcing one chip to claim "active"
        // for a duration it doesn't actually represent.
        let label = timerRow.nextElementSibling;
        if(!label || !label.classList || !label.classList.contains('api-fallback-notice')){
          label = document.createElement('div');
          label.className = 'api-fallback-notice';
          timerRow.insertAdjacentElement('afterend', label);
        }
        setEscapedText(label, 'Paused — ' + formatRemaining(data.remainingSeconds) + ' remaining');
      } else {
        const existing = timerRow.nextElementSibling;
        if(existing && existing.classList && existing.classList.contains('api-fallback-notice')) existing.remove();
      }
    }
  }

  // ---- Real "Pause internet" chip click: POST /cgi-bin/api/device-pause {mac, minutes}.
  //      Not optimistic (unlike the toggle switches) — a pause chip has no single obvious
  //      "immediately correct" visual state to jump to before the real remainingSeconds is
  //      known, so this shows a brief pending state on the row, waits for the real
  //      response, then displays the real remaining time. Chip-to-minutes mapping: "15
  //      min" -> 15, "1 hr" -> 60, "Until tomorrow" -> minutes remaining until the next
  //      local midnight (computed client-side, a clear and honest reading of "tomorrow"
  //      with no per-family schedule concept to draw on instead). ----
  function minutesUntilNextMidnight(){
    const now = new Date();
    const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0, 0);
    return Math.max(1, Math.round((next - now) / 60000));
  }

  async function handleDevicePauseChipClick(chip, timerRow){
    const mac = timerRow.dataset.mac;
    if(!mac || timerRow.dataset.pending === 'true') return;
    const label = (chip.textContent || '').trim();
    const minutes = label === '15 min' ? 15 : label === '1 hr' ? 60 : minutesUntilNextMidnight();
    timerRow.dataset.pending = 'true';
    timerRow.querySelectorAll('.timer-chip').forEach(c=>c.classList.remove('active'));
    chip.classList.add('active');
    const result = await fetchRouterApiWithStatus('/cgi-bin/api/device-pause', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({mac, minutes})
    }, 3000);
    timerRow.dataset.pending = 'false';
    let label2 = timerRow.nextElementSibling;
    if(!label2 || !label2.classList || !label2.classList.contains('api-fallback-notice')){
      label2 = document.createElement('div');
      label2.className = 'api-fallback-notice';
      timerRow.insertAdjacentElement('afterend', label2);
    }
    if(result && result.ok && result.data){
      setEscapedText(label2, 'Paused — ' + formatRemaining(result.data.remainingSeconds) + ' remaining');
    } else {
      chip.classList.remove('active');
      const msg = (result && result.data && result.data.error) ? result.data.error
        : (result === null ? "Can't reach router — device not paused." : ('Request failed (status '+result.status+') — device not paused.'));
      setEscapedText(label2, msg);
      setTimeout(()=>{ if(label2.parentElement) label2.remove(); }, 4000);
    }
  }
```

- [ ] **Step 5: Wire the dispatch points**

In `render()`, immediately after the `advwireguard` line added in Task 3, add:
```js
      // Per-Device Controls: only overlays real data when reached with a real selected
      // device (see renderDevcontrolsScreen's own comment) — a no-op otherwise.
      if(state.screen === 'devcontrols'){ state.devcontrolsRenderId++; renderDevcontrolsScreen(); }
```

In the global click handler, the real device-row navigation must be added to the EXISTING `.list-item` branch (not a new one) — find:
```js
    // devices list-item (mobile-style list state, reused here for the split-desk list)
    const listItem = e.target.closest('.list-item');
    if(listItem && listItem.closest('.split-desk-list, [data-panel="list"]')){
      const scope = listItem.closest('.split-desk-list, [data-panel="list"]');
      scope.querySelectorAll('.list-item').forEach(i=>i.classList.remove('active'));
      listItem.classList.add('active');
      return;
    }
```
and change it to:
```js
    // devices list-item (mobile-style list state, reused here for the split-desk list)
    const listItem = e.target.closest('.list-item');
    if(listItem && listItem.closest('.split-desk-list, [data-panel="list"]')){
      const scope = listItem.closest('.split-desk-list, [data-panel="list"]');
      scope.querySelectorAll('.list-item').forEach(i=>i.classList.remove('active'));
      listItem.classList.add('active');
      // Real Devices screen row, with a real MAC: navigate to Per-Device Controls for
      // THAT device (see renderDevcontrolsScreen's own comment on how the target screen
      // uses this). Demo rows on any other screen (e.g. devcontrols' own static "Emma's
      // devices" sidebar) have no data-device-mac attribute and fall through unaffected.
      if(state.screen === 'devices' && listItem.dataset.deviceMac){
        state.selectedDevice = {
          mac: listItem.dataset.deviceMac,
          name: listItem.dataset.deviceName || listItem.dataset.deviceMac,
          ip: listItem.dataset.deviceIp || '',
          online: listItem.dataset.deviceOnline === '1'
        };
        goTo('devcontrols');
      }
      return;
    }
```

The `.timer-chip` branch needs the real interception added BEFORE its existing generic behavior — find:
```js
    // timer chip
    const timer = e.target.closest('.timer-chip');
    if(timer){
      const row = timer.closest('.timer-row');
      row.querySelectorAll('.timer-chip').forEach(c=>c.classList.remove('active'));
      timer.classList.add('active');
      return;
    }
```
and change it to:
```js
    // timer chip
    const timer = e.target.closest('.timer-chip');
    if(timer){
      const row = timer.closest('.timer-row');
      // Per-Device Controls' "Pause internet" chips are a REAL write control when this
      // timer-row was stamped with a real device's MAC (see renderDevcontrolsScreen) —
      // intercepted here, before the generic click-to-select-a-chip behavior below, the
      // same "specific check before the generic branch" idiom as guestWifiSwitch/
      // adblockSwitch/wireguardSwitch above. Any other .timer-row in the app (there are
      // none today besides this one — devcontrols is the only screen using .timer-row)
      // would fall through to the generic behavior unaffected, since it would have no
      // dataset.mac set.
      if(row && row.dataset.mac){ handleDevicePauseChipClick(timer, row); return; }
      row.querySelectorAll('.timer-chip').forEach(c=>c.classList.remove('active'));
      timer.classList.add('active');
      return;
    }
```

- [ ] **Step 6: Verify in a real browser against the live VM**

Navigate to Devices, click a real device row, confirm navigation lands on Per-Device Controls showing that device's real name/MAC/online-status (not "Emma's iPhone"), click "15 min", confirm a real "Paused — 15 min remaining" label appears, confirm via SSH (`nft list ruleset | grep <mac>`) that a real forward_lan reject rule now exists for that MAC, reload the page and re-navigate the same way, confirm the pause status is still correctly reported (real GET on load). Then separately confirm the ORIGINAL static path (Parental Controls → "Emma's controls" → devcontrols, or however the existing static navigation reaches this screen) still shows the untouched "Emma's iPhone" demo content with fully cosmetic chip-clicking, unaffected by this task.

- [ ] **Step 7: Commit**

```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): real device navigation + real per-MAC Pause internet action"
```

---

### Task 9: Documentation closeout

**Files:**
- Modify: `docker/README.md` (Provisioning section: add steps 11-13 to the sequential command list and verify block; Known Limitations: add Wave 5's honesty notes)
- Modify: `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` (Architecture diagram comment, Components section per-endpoint subsections, Frontend changes subsection, Testing section — mirror exactly how Waves 2-4 each added their own dated update paragraph to these same sections rather than rewriting them)

- [ ] **Step 1: Update `docker/README.md`'s Provisioning section**

Add to the sequential command list:
```bash
./docker/provision/11-provision-wireguard-api.sh
./docker/provision/12-provision-ssh-key-api.sh
./docker/provision/13-provision-devpause-api.sh
```
and to its verify block:
```bash
curl -s http://localhost:8081/cgi-bin/api/wireguard  # -> {"running":true,"port":51820,"publicKey":"<real>","subnet":"10.9.0.0/24"}
curl -s -X POST http://localhost:8081/cgi-bin/api/ssh-key  # -> {"ok":true,"fingerprint":"SHA256:<real>"}
curl -s "http://localhost:8081/cgi-bin/api/device-pause?mac=aa:bb:cc:dd:ee:ff"  # -> {"paused":false,"remainingSeconds":0}
```

- [ ] **Step 2: Add Wave 5 notes to Known Limitations**

Append bullets covering: (a) the four write-capable endpoints as of Wave 5 (`firewall-rules`, `wifi`, `adblock`, `wireguard`, `device-pause` — five, update the Security posture cross-reference count too, in both this file and the design spec); (b) per-device pause blocks the device's outbound-to-WAN traffic in real, correct `uci`/`fw4` config, but (like every other WAN-dependent feature in this project) isn't end-to-end testable since this VM has no real WAN interface; (c) "Until tomorrow" is computed as minutes-until-next-local-midnight, an approximation with no per-family schedule concept behind it; (d) SSH key rotation is safe for this project's own verification workflow specifically because of its `-o StrictHostKeyChecking=no` convention, not something to assume safe in a normal deployment without a client-side warning.

- [ ] **Step 3: Update the design spec**

Mirror Wave 4's own update pattern exactly (find the `**Wave 4 update (...)**` paragraph in the Testing section, and the Wave 4 bullets in the Components/Frontend-changes sections, as the template): add a `**Wave 5 update (...)**` paragraph to the Testing section summarizing what was proven real and how; add `### Wireguard API`, `### SSH Key API`, `### Device Pause API` subsections to Components (mirroring the existing per-endpoint subsections); extend the Frontend changes subsection's running screen-count sentence (eight screens/sections → eleven: Developer & API Access' rotate button, VPN Server (WireGuard)'s hero+details, Per-Device Controls' pause action); update the Architecture diagram comment's screen list; update the Security posture section's write-endpoint count (three → five) and read-only-endpoint list if `device-pause`'s GET should be mentioned there too (it discloses whether a specific MAC is currently paused — a narrow disclosure, but real, worth a one-clause mention for consistency with how `/api/vlans` was handled in Wave 4's closeout).

- [ ] **Step 4: Commit**

```bash
git add docker/README.md docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: Wave 5 closeout — README provisioning/limitations, design spec updates"
```

---

## After all tasks

Dispatch one final whole-wave integration-level code-quality review (a fresh `superpowers:code-reviewer` subagent, given the full diff across all 9 tasks), fix anything it raises with a fix subagent + re-review, apply any doc-only fixes directly, commit, then report Wave 5 complete to the user using the same format every prior wave's completion summary used: what's real now, process highlights, real bugs caught, what's next per the roadmap (Wave 6, the renamed remaining-harder-simulation bucket).
