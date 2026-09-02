# Real "Bandwidth Used Today" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real, live-verified "Bandwidth used today" feature on the Traffic & QoS screen (`advqos` in `sadd-website.html`), replacing the mockup's fabricated 3-device percentage split + 7-bar sparkline with a real absolute per-device byte count for devices already marked "priority."

**Architecture:** A new cron sweep (`qos-bandwidth-sweep.sh`, every 5 minutes) reads each QoS-priority-marked device's live nft traffic counter and accumulates it into a persisted per-device-per-UTC-day file, then calls `fw4 reload` — the only mechanism on this VM that actually zeroes nft counters (confirmed live, `docker/facts.md` §19; `nft reset` itself is a confirmed no-op here). A new read-only endpoint (`/api/qos-bandwidth`) reads those persisted files with no shell-out at all. The frontend replaces the fabricated chart with a real total + per-device list.

**Tech Stack:** Lua CGI (matching every existing endpoint under `docker/provision/www/api/`), POSIX `/bin/sh` (matching `docker/provision/lib/bedtime-sweep.sh`/`devpause-sweep.sh`), `uci`/`nft`/`fw4` against the running OpenWrt VM, vanilla JS in `sadd-website.html`.

**Full design context:** `docs/superpowers/specs/2026-09-02-qos-bandwidth-today-design.md` and `docker/facts.md` §19 — read both before starting; this plan assumes their contents as background.

---

### Task 1: `qos-bandwidth-sweep.sh` — the accumulation sweep

**Files:**
- Create: `docker/provision/lib/qos-bandwidth-sweep.sh`

This project has no unit-test framework anywhere (every Lua/shell file in this codebase is verified live against the running VM, not with a local test runner) — follow that established convention here, not a generic pytest-style TDD template. "Testing" in this task means deploying the script to the VM by hand and exercising it with real and controlled inputs, the same way `docker/provision/lib/bedtime-sweep.sh` and `docker/provision/lib/devpause-sweep.sh` were built and verified.

**Context you need:**
- Every `qospriority-<mac with colons stripped>` uci firewall rule (created by `docker/provision/www/api/qos-priority`, already built in Wave 6) has NO explicit `proto` set, which means `fw4` expands it into TWO separate nft rules in the `mangle_forward` chain — one for `tcp`, one for `udp` — both sharing the same `!fw4: qospriority-<mac>` comment. A real example, confirmed live:
  ```
  meta l4proto tcp iifname "br-lan" ether saddr aa:bb:cc:dd:ee:ff counter packets 0 bytes 0 meta mark set 0x0000002a comment "!fw4: qospriority-aabbccddeeff"
  meta l4proto udp iifname "br-lan" ether saddr aa:bb:cc:dd:ee:ff counter packets 0 bytes 0 meta mark set 0x0000002a comment "!fw4: qospriority-aabbccddeeff"
  ```
  This sweep must sum BOTH lines' `bytes` value for a given device, not just one.
- `nft reset` (every documented form: by rule, by handle, by named counter object) does NOT work on this VM — confirmed live, `docker/facts.md` §19. Do not use it.
- `fw4 reload` DOES reliably zero every counter in the `inet fw4` table, because it fully regenerates the table from `uci` config from scratch on every call (confirmed live, `docker/facts.md` §19) — this is the reset mechanism this script relies on, called once at the end of each sweep pass.
- Busybox ash gotcha this project already hit once (`docker/facts.md` §16, `bedtime-sweep.sh`'s own header comment): a digit string with a leading zero (e.g. `"08"`) inside `$(( ))` risks octal misinterpretation / a syntax error. This script does arithmetic on byte counts (`$((PREV_TOTAL + BYTES_NOW))`), so both operands must be stripped of any leading zeros first, defensively — shell arithmetic itself never produces a leading-zero result, but a corrupted or manually-edited state file could contain one, and this project has already been bitten by this exact bug class once.

- [ ] **Step 1: Write the script**

Create `docker/provision/lib/qos-bandwidth-sweep.sh`:

```sh
#!/bin/sh
# /usr/bin/qos-bandwidth-sweep.sh — run every 5 minutes by cron (see
# 18-provision-qos-bandwidth-api.sh). For every uci firewall rule this
# project created for QoS Priority marking (named `qospriority-<mac with
# colons stripped>`, see docker/provision/www/api/qos-priority), reads that
# device's real nft mangle_forward counter (tcp+udp summed — a single
# qos-priority uci rule with no explicit `proto` expands into TWO separate
# nft rules, one per protocol, confirmed live docker/facts.md Section
# 15/19) and accumulates it onto a persisted per-device-per-UTC-day
# running total.
#
# Why accumulate instead of trusting the raw nft counter to hold a full
# day's traffic: `nft reset` does not work on this VM (confirmed live,
# docker/facts.md Section 19 — every documented reset form left a known
# non-zero counter completely unchanged). `fw4 reload` DOES reliably zero
# every counter in the table, but only as a side effect of fully
# regenerating the whole ruleset from uci config from scratch — and fw4
# reload is called by EVERY existing write endpoint in this project
# (device-pause, qos-priority itself, device-bedtime, firewall-rules,
# etc.), not just a purpose-built reset. So the raw counter can be zeroed
# by something totally unrelated at any moment, not just at a controlled
# daily boundary. Polling every 5 minutes and adding whatever's
# accumulated since the last tick onto a persisted total survives that —
# at the cost of a real, disclosed limitation: if an unrelated fw4 reload
# happens BETWEEN two sweep ticks, whatever traffic accumulated in that
# gap is lost (the counter is already back to zero by the time this sweep
# next reads it) — an undercount, never an overcount, for that one device
# that day. Rare in practice (write actions aren't constant), and
# documented plainly rather than glossed over — see docker/README.md's
# Known Limitations and
# docs/superpowers/specs/2026-09-02-qos-bandwidth-today-design.md.
#
# Storage: /etc/qos-bandwidth/<mac-no-colons>-<YYYYMMDD>.txt, one plain
# integer (accumulated bytes) per device per UTC calendar day. A new day is
# simply a filename that doesn't exist yet (read as 0) — no hour-comparison
# arithmetic anywhere in this script, deliberately avoiding the busybox-ash
# `$(( ))` zero-padded-hour gotcha bedtime-sweep.sh had to route around
# (docker/facts.md Section 16) by not needing hour arithmetic at all. Byte
# totals ARE run through `$(( ))` below, so both operands are defensively
# stripped of any leading zeros first — this project's own arithmetic
# values should never naturally have one (shell arithmetic never prints a
# zero-padded result), but a corrupted/manually-edited state file could,
# and a leading-zero digit sequence in $(( )) risks the exact same
# octal-misinterpretation bug class bedtime-sweep.sh found, so this is
# defensive, not decorative.
#
# No top-level `set -e`, deliberately, same reasoning as devpause-sweep.sh
# and bedtime-sweep.sh: one device's read/write failing shouldn't cancel
# the sweep for every other device this tick.

STATE_DIR="/etc/qos-bandwidth"
mkdir -p "$STATE_DIR"

TODAY="$(date -u +%Y%m%d)"

strip_leading_zeros() {
  # "007" -> "7", "0" -> "0", "" -> "0". Avoids $(( )) octal
  # misinterpretation on a leading-zero digit string.
  local v
  v="$(echo "$1" | sed 's/^0*//')"
  if [ -z "$v" ]; then echo 0; else echo "$v"; fi
}

for id in $(uci show firewall | grep "\.name='qospriority-" | sed -n "s/^firewall\.\([^.]*\)\.name=.*/\1/p"); do
  MAC="$(uci -q get "firewall.${id}.src_mac")"
  if [ -z "$MAC" ]; then
    logger -t qos-bandwidth-sweep "ERROR: firewall.${id} has no src_mac; skipping"
    continue
  fi
  MAC_NOCOLON="$(echo "$MAC" | tr -d ':' | tr 'A-F' 'a-f')"
  RULE_NAME="qospriority-${MAC_NOCOLON}"

  NFT_OUTPUT="$(nft list chain inet fw4 mangle_forward 2>/dev/null)"
  NFT_STATUS=$?
  if [ "$NFT_STATUS" != "0" ]; then
    logger -t qos-bandwidth-sweep "ERROR: nft list chain inet fw4 mangle_forward failed (exit ${NFT_STATUS}); skipping ${RULE_NAME} this tick"
    continue
  fi

  # Sum both nft rule lines' bytes for this device's mark rule (tcp + udp —
  # a single uci rule with no explicit proto expands into both, confirmed
  # live docker/facts.md Section 15/19). Each matching line looks like:
  #   ... counter packets N bytes M ... comment "!fw4: qospriority-aabbccddeeff"
  BYTES_NOW="$(echo "$NFT_OUTPUT" \
    | grep "\"!fw4: ${RULE_NAME}\"" \
    | sed -n 's/.*counter packets [0-9]* bytes \([0-9]*\).*/\1/p' \
    | awk '{sum+=$1} END {print sum+0}')"
  BYTES_NOW="$(strip_leading_zeros "$BYTES_NOW")"

  STATE_FILE="${STATE_DIR}/${MAC_NOCOLON}-${TODAY}.txt"
  PREV_TOTAL="$(cat "$STATE_FILE" 2>/dev/null)"
  case "$PREV_TOTAL" in
    ''|*[!0-9]*) PREV_TOTAL=0 ;;
  esac
  PREV_TOTAL="$(strip_leading_zeros "$PREV_TOTAL")"

  NEW_TOTAL=$((PREV_TOTAL + BYTES_NOW))
  echo "$NEW_TOTAL" > "$STATE_FILE" \
    || logger -t qos-bandwidth-sweep "ERROR: failed to write ${STATE_FILE}"
done

# Zero every counter in the table for the next window — the only working
# reset mechanism on this VM (docker/facts.md Section 19). Safe to call
# even when the for-loop above ran zero times (no qos-priority devices
# marked yet) — fw4 reload is idempotent and every other sweep/endpoint in
# this project already calls it routinely.
if ! fw4 reload >/dev/null 2>&1; then
  logger -t qos-bandwidth-sweep "ERROR: fw4 reload failed after accumulating this tick's counters"
fi
```

- [ ] **Step 2: Deploy it to the VM by hand for testing**

The Docker/QEMU OpenWrt VM must already be running (`docker ps` should show an `openwrt` container, healthy — if not, `cd docker && docker compose up -d` and wait for it to report healthy before continuing). Deploy manually (the real provisioning script comes in Task 3):

```bash
scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 2223 \
  docker/provision/lib/qos-bandwidth-sweep.sh \
  root@localhost:/usr/bin/qos-bandwidth-sweep.sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "chmod +x /usr/bin/qos-bandwidth-sweep.sh"
```

- [ ] **Step 3: Verify the script is safe to run with zero marked devices**

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "curl -s http://localhost:8081/cgi-bin/api/qos-priority"
```
Expected: `[]` (no devices currently marked priority — if this returns something else, note what's marked and account for it in later steps, don't assume a clean slate). Then:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "/usr/bin/qos-bandwidth-sweep.sh; echo EXIT=\$?; ls /etc/qos-bandwidth/ 2>&1"
```
Expected: `EXIT=0`, and `/etc/qos-bandwidth/` exists (created by `mkdir -p`) but is empty (the for-loop had nothing to iterate).

- [ ] **Step 4: Verify the accumulation arithmetic with a deterministic, controlled counter value (no real traffic needed)**

Mark a throwaway test device priority so a `qospriority-*` rule exists to sweep:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "curl -s -X POST -d '{\"mac\":\"aa:bb:cc:dd:ee:88\"}' http://localhost:8081/cgi-bin/api/qos-priority"
```
Expected: `{"ok":true,"mac":"aa:bb:cc:dd:ee:88"}`.

Give its counter a known, non-zero value directly via `nft` (the same technique used during design investigation to prove `fw4 reload`'s reset behavior, `docker/facts.md` §19 — bypasses the need for genuine traffic to test the sweep's read-and-accumulate math in isolation):
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
nft list chain inet fw4 mangle_forward
"
```
Find the two rule handles for the `qospriority-aabbccddeeff` comment (one tcp, one udp) via `nft -a list chain inet fw4 mangle_forward`, then delete and re-add each with a known counter value (deleting+re-adding is necessary since there's no working way to SET an existing rule's counter in place — only at creation, confirmed `docker/facts.md` §19):
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
nft -a list chain inet fw4 mangle_forward | grep qospriority-aabbccddeeff
"
```
Note the two `handle N` values shown (one per proto line), then, for EACH handle:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
nft delete rule inet fw4 mangle_forward handle <HANDLE>
nft add rule inet fw4 mangle_forward meta l4proto tcp iifname \"br-lan\" ether saddr aa:bb:cc:dd:ee:88 counter packets 5 bytes 1000 meta mark set 0x2a comment \"!fw4: qospriority-aabbccddeeff\"
"
```
(repeat for the udp line with a different byte value, e.g. `bytes 500`, so the sum is verifiable as 1500). Then run the sweep and check the result:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
/usr/bin/qos-bandwidth-sweep.sh
cat /etc/qos-bandwidth/aabbccddeeff-\$(date -u +%Y%m%d).txt
"
```
Expected: `1500` (1000 + 500). **Important**: since the sweep's own `fw4 reload` at the end regenerates the whole table from `uci` config, your manually-injected counter values (which only existed in the live `nft` ruleset, not in `uci`) will be gone after this — that's expected and correct, it proves the reload happened. Run the sweep a SECOND time immediately after:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
/usr/bin/qos-bandwidth-sweep.sh
cat /etc/qos-bandwidth/aabbccddeeff-\$(date -u +%Y%m%d).txt
"
```
Expected: still `1500` (the real counter is back to 0 after the reload from the first pass, so this second pass adds 0 — the total should NOT double).

- [ ] **Step 5: Verify with genuinely real traffic, not just a preset value**

Every throwaway test container in this project's topology (`docker run --network container:openwrt ...`) shares tap0's single real hardware MAC — not a distinct MAC per container (confirmed `docker/provision/www/api/devices`' own header comment, `docker/facts.md` §1a/§10). Look it up live:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "ip link show tap0"
```
Note the `link/ether` MAC address shown. Mark THAT MAC priority (remove the throwaway `aa:bb:cc:dd:ee:88` marking first if you want a clean single-device test — there's no `DELETE` on `/api/qos-priority`, so do this over SSH: `uci -q delete firewall.qospriority_aabbccddeeff; uci commit firewall; fw4 reload`):
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "curl -s -X POST -d '{\"mac\":\"<TAP0_MAC_FROM_ABOVE>\"}' http://localhost:8081/cgi-bin/api/qos-priority"
```
Generate a real outbound packet from a throwaway container sharing the same network namespace (the same technique `docker/facts.md` §10 used to prove a real TCP SYN increments a real counter):
```bash
docker run --rm --network container:openwrt busybox \
  sh -c "ping -c 3 -W 1 8.8.8.8"
```
(the target's unreachability doesn't matter — the packet still gets forwarded through `mangle_forward` before failing further out). Then run the sweep and confirm the persisted total picked up real, non-fabricated bytes:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
/usr/bin/qos-bandwidth-sweep.sh
cat /etc/qos-bandwidth/<TAP0_MAC_NO_COLONS_LOWERCASE>-\$(date -u +%Y%m%d).txt
"
```
Expected: a nonzero number reflecting real ICMP packet bytes.

- [ ] **Step 6: Reproduce the disclosed "undercount" limitation live — don't just assert it**

The design spec (`docs/superpowers/specs/2026-09-02-qos-bandwidth-today-design.md`, Testing plan item 4) requires this be proven, not just claimed in a comment. Using the same tap0-MAC device still marked from Step 5: generate some real traffic, then — BEFORE running the sweep — trigger a DIFFERENT endpoint's own `fw4 reload` (this is what an unrelated user action elsewhere in the app would do), then run the sweep and confirm the traffic generated before that reload was lost (undercounted), not double-counted or crashed on:

```bash
docker run --rm --network container:openwrt busybox \
  sh -c "ping -c 3 -W 1 8.8.8.8"
```
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
nft list chain inet fw4 mangle_forward | grep qospriority
"
```
Confirm a nonzero counter exists for the tap0 MAC's rule right now (proving there IS real traffic waiting to be swept). Now simulate an unrelated endpoint's reload BEFORE the sweep gets a chance to read it — e.g. by hitting `/api/device-pause` for a throwaway MAC (any real write endpoint that calls `fw4 reload` works; this one is convenient and harmless to use for the test):
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
curl -s -X POST -d '{\"mac\":\"11:22:33:44:55:77\",\"minutes\":1}' http://localhost:8081/cgi-bin/api/device-pause
nft list chain inet fw4 mangle_forward | grep qospriority
"
```
Expected: the qos-priority rule's counter is now back to `packets 0 bytes 0` — the unrelated `/api/device-pause` call's own `fw4 reload` already zeroed it, BEFORE the sweep ever got a chance to read the traffic generated above. Now run the sweep:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
/usr/bin/qos-bandwidth-sweep.sh
cat /etc/qos-bandwidth/<TAP0_MAC_NO_COLONS_LOWERCASE>-\$(date -u +%Y%m%d).txt
"
```
Expected: the persisted total did NOT increase from the traffic generated in this step (it only reflects whatever was captured by the Step 5 sweep, before this step's reload wiped the counter) — confirming the disclosed limitation is real, reproducible behavior, and confirming the failure mode is a silent undercount (a plausible-looking but low number), not a crash, an error, or a negative/nonsensical value. Clean up the throwaway pause: `uci -q delete firewall.$(uci show firewall | grep "src_mac='11:22:33:44:55:77'" | head -1 | cut -d. -f2); uci commit firewall; fw4 reload` (or simply wait the 1 minute for it to expire via the existing devpause-sweep).

- [ ] **Step 7: Verify day-rollover needs no special-case handling**

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
echo 99999 > /etc/qos-bandwidth/aabbccddeeff-20990101.txt
/usr/bin/qos-bandwidth-sweep.sh
cat /etc/qos-bandwidth/aabbccddeeff-\$(date -u +%Y%m%d).txt
"
```
Expected: today's file is completely unaffected by the fabricated far-future-dated file — confirms the date-keyed-filename approach genuinely needs no day-boundary logic. Clean up the fabricated file afterward: `rm /etc/qos-bandwidth/aabbccddeeff-20990101.txt`.

- [ ] **Step 8: Clean up all test state from the VM**

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
uci -q delete firewall.qospriority_aabbccddeeff 2>/dev/null
uci -q delete firewall.qospriority_\$(echo '<TAP0_MAC_FROM_STEP_5>' | tr -d ':' | tr 'A-F' 'a-f') 2>/dev/null
uci commit firewall
fw4 reload
rm -f /etc/qos-bandwidth/*.txt
curl -s http://localhost:8081/cgi-bin/api/qos-priority
"
```
Expected final check: `[]` (no devices left marked priority), `/etc/qos-bandwidth/` empty.

- [ ] **Step 9: Commit**

```bash
git add docker/provision/lib/qos-bandwidth-sweep.sh
```
Use git identity: `GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com"`. Write the commit message to a heredoc file and use `git commit -F <file>` (embedded quotes in `-m` have broken this shell before in this project). Message: "feat(docker): add qos-bandwidth-sweep.sh (real per-device traffic accumulation)" plus a body summarizing the nft-reset-is-a-no-op / fw4-reload-resets-everything finding this script's design depends on (reference `docker/facts.md` §19), and the live verification performed (deterministic counter test, real-traffic test, disclosed-undercount-limitation reproduction, day-rollover test).

---

### Task 2: `/api/qos-bandwidth` endpoint

**Files:**
- Create: `docker/provision/www/api/qos-bandwidth`

**Context you need:** This is a read-only, GET-only endpoint. Unlike every other endpoint in this directory, it never shells out to `uci`, `io.popen`, or `nft` at all for its response — it only needs to know which MACs currently have a `qospriority-*` uci section (to know which devices to report) and read small flat files Task 1's sweep already writes. It reuses `docker/provision/www/api/qos-priority`'s own `list_priority_sections()`/enumeration approach for the first part (read `docker/provision/www/api/qos-priority` in full first — Task 1 already required reading it, but re-read it now for this task's own context, since it's this endpoint's direct template for the uci-enumeration half).

- [ ] **Step 1: Write the endpoint**

```lua
#!/usr/bin/lua
-- /api/qos-bandwidth — GET only. Real per-device traffic totals for the
-- Traffic & QoS screen's "Bandwidth used today" card, for devices already
-- marked "priority" via /api/qos-priority (Wave 6). Reuses that endpoint's
-- own qospriority-* uci enumeration to know which MACs to report, then
-- reads each one's persisted daily total — a plain integer written by
-- qos-bandwidth-sweep.sh (docker/provision/lib/), which runs every 5
-- minutes and does all the real work (reading live nft counters,
-- accumulating them, and reloading fw4 — the only mechanism confirmed to
-- actually reset a counter on this VM, docker/facts.md Section 19). This
-- endpoint itself never shells out to uci, io.popen, or nft at all — it
-- is a pure read of small flat files the sweep already wrote, the
-- simplest GET in this whole directory.
--
-- GET response shape: [{"mac":"AA:BB:CC:DD:EE:FF","bytesToday":<int>}, ...]
-- One entry per device currently marked priority, REGARDLESS of whether
-- its state file exists yet — a device marked seconds ago, before the
-- first sweep tick has run, correctly reports bytesToday:0, not an error
-- or a silent omission (the "no entry means not tracked" pitfall a naive
-- file-glob-only implementation could fall into).
--
-- No POST — this is a derived, computed-only resource. There is nothing
-- to write via this endpoint; marking a device priority in the first
-- place still goes entirely through /api/qos-priority, unchanged by this
-- endpoint's existence.
--
-- Storage read: /etc/qos-bandwidth/<mac-no-colons-lowercase>-<YYYYMMDD>.txt
-- (UTC calendar date), matching exactly what qos-bandwidth-sweep.sh
-- writes — see that script's own header comment for the full rationale
-- (nft reset is a no-op here; fw4 reload IS the reset mechanism, but it's
-- shared by every write endpoint in this project, hence the accumulate-
-- every-5-minutes design instead of trusting the raw counter for a full
-- day).
--
-- Honest, disclosed limitation (see docker/README.md Known Limitations
-- and docs/superpowers/specs/2026-09-02-qos-bandwidth-today-design.md):
-- an unrelated write endpoint's own fw4 reload between two sweep ticks
-- zeroes the raw nft counter before the sweep can read and accumulate
-- it, silently undercounting (never overcounting) that window's traffic.
-- Real, proven live during Task 1's own testing, not just asserted.

local STATE_DIR = "/etc/qos-bandwidth"

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

local function send_headers(status)
  local reasons = { [400]="Bad Request", [405]="Method Not Allowed", [500]="Internal Server Error" }
  if status and status ~= 200 then
    print("Status: " .. status .. " " .. (reasons[status] or "Error"))
  end
  print("Content-Type: application/json\n")
end

-- Same uci-firewall-enumeration approach as /api/qos-priority's own
-- list_priority_sections() — copied here (not required elsewhere, but
-- this endpoint needs its own list of qospriority-* MACs, and this
-- project's established convention is each endpoint carries its own
-- copy of shared logic rather than a cross-file import mechanism that
-- doesn't exist in this plain-CGI setup).
local function list_priority_macs()
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
  local macs = {}
  for _, id in ipairs(order) do
    local name = fields[id].name or ""
    local mac = fields[id].src_mac
    -- Load-bearing prefix check, same reasoning as qos-priority's own GET
    -- handler: device-pause's rules are ALSO rule-type sections with
    -- src_mac set, and would incorrectly show up here without this check.
    if name:match("^qospriority%-") and mac then
      macs[#macs + 1] = mac
    end
  end
  return macs
end

local function read_bytes_today(mac)
  local mac_nocolon = mac:lower():gsub(":", "")
  local today = run("date -u +%Y%m%d")
  local path = STATE_DIR .. "/" .. mac_nocolon .. "-" .. today .. ".txt"
  local f = io.open(path, "r")
  if not f then return 0 end
  local content = f:read("*a") or ""
  f:close()
  local n = tonumber((content:gsub("%s+$", "")))
  if not n then return 0 end
  return math.floor(n)
end

local method = os.getenv("REQUEST_METHOD") or "GET"

if method == "GET" then
  local macs = list_priority_macs()
  local rows = {}
  for _, mac in ipairs(macs) do
    rows[#rows + 1] = string.format('{"mac":"%s","bytesToday":%d}', json_escape(mac), read_bytes_today(mac))
  end
  send_headers(200)
  print("[" .. table.concat(rows, ",") .. "]")
else
  send_headers(405)
  print(string.format('{"ok":false,"error":"unsupported method: %s"}', json_escape(tostring(method))))
end
```

- [ ] **Step 2: Deploy it to the VM by hand for testing**

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "mkdir -p /www/cgi-bin/api"
scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 2223 \
  docker/provision/www/api/qos-bandwidth \
  root@localhost:/www/cgi-bin/api/qos-bandwidth
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "chmod +x /www/cgi-bin/api/qos-bandwidth"
```

- [ ] **Step 3: Verify GET with zero marked devices**

```bash
curl -s http://localhost:8081/cgi-bin/api/qos-bandwidth
```
Expected: `[]` (assuming Task 1's Step 7 cleanup left no devices marked — if something is still marked from earlier testing, expect an entry for it instead and account for that).

- [ ] **Step 4: Verify GET reports `bytesToday:0` for a freshly-marked device with no state file yet**

```bash
curl -s -X POST -d '{"mac":"aa:bb:cc:dd:ee:99"}' http://localhost:8081/cgi-bin/api/qos-priority
curl -s http://localhost:8081/cgi-bin/api/qos-bandwidth
```
Expected: `[{"mac":"aa:bb:cc:dd:ee:99","bytesToday":0}]` — no `/etc/qos-bandwidth/aabbccddee99-*.txt` file exists yet (no sweep tick has run for this device), and the endpoint correctly reports `0`, not an error or an empty array.

- [ ] **Step 5: Verify GET reflects a real persisted total after a sweep tick**

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "echo 12345 > /etc/qos-bandwidth/aabbccddee99-\$(date -u +%Y%m%d).txt"
curl -s http://localhost:8081/cgi-bin/api/qos-bandwidth
```
Expected: `[{"mac":"aa:bb:cc:dd:ee:99","bytesToday":12345}]`.

- [ ] **Step 6: Verify 405 on unsupported methods**

```bash
curl -s -X POST -d '{}' http://localhost:8081/cgi-bin/api/qos-bandwidth
curl -s -X DELETE http://localhost:8081/cgi-bin/api/qos-bandwidth
```
Expected: both return `Status: 405` with `{"ok":false,"error":"unsupported method: POST"}` / `"...DELETE"`.

- [ ] **Step 7: Clean up test state**

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost "
uci -q delete firewall.qospriority_aabbccddee99
uci commit firewall
fw4 reload
rm -f /etc/qos-bandwidth/*.txt
curl -s http://localhost:8081/cgi-bin/api/qos-bandwidth
"
```
Expected: `[]`.

- [ ] **Step 8: Commit**

```bash
git add docker/provision/www/api/qos-bandwidth
```
Same git identity as Task 1. Heredoc + `git commit -F`. Message: "feat(docker): add /api/qos-bandwidth endpoint (real per-device daily traffic totals)" plus a body noting this is the first pure-file-read GET endpoint in this directory (no uci/nft/shell-out for the response itself) and the live verification performed.

---

### Task 3: `docker/provision/18-provision-qos-bandwidth-api.sh`

**Files:**
- Create: `docker/provision/18-provision-qos-bandwidth-api.sh`
- Modify: `docker/README.md` (Provisioning section: add step 18)

**Context you need:** Read `docker/provision/15-provision-bedtime-api.sh` in full first — it is the closest template, since it deploys BOTH a sweep script (into `/usr/bin/`, seeding a crontab entry, verifying `crond` is genuinely running — not just trusting the init script's own exit code, `docker/facts.md` §13's crontab-must-be-seeded-before-cron-starts gotcha) AND an endpoint (into `/www/cgi-bin/api/`) in one script, exactly the shape this task needs.

- [ ] **Step 1: Write the provisioning script**

```sh
#!/bin/sh
# Deploys docker/provision/lib/qos-bandwidth-sweep.sh (the tracked source
# of truth for the per-device bandwidth accumulation sweep) onto a running
# OpenWrt VM as /usr/bin/qos-bandwidth-sweep.sh, seeds a cron entry that
# runs it every 5 minutes, verifies crond is genuinely running, then
# deploys and verifies docker/provision/www/api/qos-bandwidth.
#
# Deliberately NOT under docker/provision/www/ for the sweep script (same
# reasoning as 13-provision-devpause-api.sh's devpause-sweep.sh and
# 15-provision-bedtime-api.sh's bedtime-sweep.sh): that whole subtree gets
# generically copied onto the VM's web-servable /www/cgi-bin/ by
# 02-copy-www.sh, and this script is a plain cron job, not an
# HTTP-servable CGI endpoint. docker/provision/lib/ has no such exposure.
#
# Critical gotcha this script works around (confirmed live in
# docker/facts.md Section 13, by reading /etc/init.d/cron directly):
# `/etc/init.d/cron start`'s own start_service() does
# `[ -z "$(ls /etc/crontabs/)" ] && return 1` — if /etc/crontabs/ is empty,
# it silently no-ops (returns exit 0 from the init script anyway; procd
# reports success regardless), and crond never actually starts. So this
# script always seeds /etc/crontabs/root with a real line BEFORE calling
# `/etc/init.d/cron start`, then independently verifies with `pgrep crond`
# rather than trusting the init script's own exit code.
#
# Usage (run from the repo root, or anywhere — paths are self-contained):
#   bash docker/provision/18-provision-qos-bandwidth-api.sh
#
# Optional overrides (defaults match docker/docker-compose.yml's port map):
#   OPENWRT_HOST=localhost OPENWRT_PORT=2223 bash docker/provision/18-provision-qos-bandwidth-api.sh
set -e

OPENWRT_HOST="${OPENWRT_HOST:-localhost}"
OPENWRT_PORT="${OPENWRT_PORT:-2223}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_TARGET="root@${OPENWRT_HOST}"

ssh_run() { ssh ${SSH_OPTS} -p "${OPENWRT_PORT}" "${SSH_TARGET}" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_FILE="${SCRIPT_DIR}/lib/qos-bandwidth-sweep.sh"

echo "=== 18-provision-qos-bandwidth-api.sh ==="

if [ ! -f "${SRC_FILE}" ]; then
  echo "ERROR: ${SRC_FILE} not found." >&2
  exit 1
fi

echo "Copying ${SRC_FILE} -> root@${OPENWRT_HOST}:/usr/bin/qos-bandwidth-sweep.sh ..."
# -O forces the legacy SCP protocol — this VM has no /usr/libexec/sftp-server,
# confirmed live in 01/02/03; required, not optional, against this VM.
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${SRC_FILE}" \
  "${SSH_TARGET}:/usr/bin/qos-bandwidth-sweep.sh"

echo "Making it executable (core.filemode=false means git doesn't track +x — see 02's comment)..."
ssh_run "chmod +x /usr/bin/qos-bandwidth-sweep.sh && ls -la /usr/bin/qos-bandwidth-sweep.sh"

echo "Ensuring /etc/qos-bandwidth/ exists on the VM..."
ssh_run "mkdir -p /etc/qos-bandwidth"

echo "Seeding /etc/crontabs/root with a every-5-minutes entry (idempotent — grep -qF guards against a duplicate line on re-run)..."
ssh_run "mkdir -p /etc/crontabs && (grep -qF '/usr/bin/qos-bandwidth-sweep.sh' /etc/crontabs/root 2>/dev/null || echo '*/5 * * * * /usr/bin/qos-bandwidth-sweep.sh' >> /etc/crontabs/root) && cat /etc/crontabs/root"

echo "Enabling and starting cron..."
ssh_run "/etc/init.d/cron enable && /etc/init.d/cron start"

echo "Verifying crond is actually running (the init script's own exit code is NOT proof — it silently no-ops if /etc/crontabs/ was empty when it ran; docker/facts.md Section 13). Since the crontab was seeded above before start, this ordering should avoid that trap, but verify anyway rather than trust it..."
if ssh_run "pgrep crond >/dev/null 2>&1"; then
  echo "OK: crond is running."
else
  echo "crond not running after start — retrying once with /etc/init.d/cron restart..." >&2
  ssh_run "/etc/init.d/cron restart"
  sleep 2
  if ssh_run "pgrep crond >/dev/null 2>&1"; then
    echo "OK: crond is running after restart."
  else
    echo "ERROR: crond still not running after restart. Investigate manually (check /etc/crontabs/root contents and /etc/init.d/cron)." >&2
    exit 1
  fi
fi

echo "=== 18-provision-qos-bandwidth-api.sh: sweep half done. Now deploying the /api/qos-bandwidth endpoint itself. ==="

OPENWRT_HTTP_PORT="${OPENWRT_HTTP_PORT:-8081}"
API_SRC_FILE="${SCRIPT_DIR}/www/api/qos-bandwidth"

if [ ! -f "${API_SRC_FILE}" ]; then
  echo "ERROR: ${API_SRC_FILE} not found." >&2
  exit 1
fi

echo "Ensuring /www/cgi-bin/api exists on the VM (root@${OPENWRT_HOST}:${OPENWRT_PORT})..."
ssh_run "mkdir -p /www/cgi-bin/api"

echo "Copying ${API_SRC_FILE} -> root@${OPENWRT_HOST}:/www/cgi-bin/api/qos-bandwidth ..."
# shellcheck disable=SC2086
scp -O ${SSH_OPTS} -P "${OPENWRT_PORT}" \
  "${API_SRC_FILE}" \
  "${SSH_TARGET}:/www/cgi-bin/api/qos-bandwidth"

echo "Making it executable..."
ssh_run "chmod +x /www/cgi-bin/api/qos-bandwidth && ls -la /www/cgi-bin/api/qos-bandwidth"

echo "Verifying: GET http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/qos-bandwidth returns a JSON array..."
BODY="$(curl -s "http://${OPENWRT_HOST}:${OPENWRT_HTTP_PORT}/cgi-bin/api/qos-bandwidth")"
echo "Response: ${BODY}"

case "${BODY}" in
  \[*\])
    echo "OK: /api/qos-bandwidth returns a JSON array shape."
    ;;
  *)
    echo "ERROR: expected a JSON array (e.g. [] or [{...}]), got: ${BODY}" >&2
    exit 1
    ;;
esac

echo "=== 18-provision-qos-bandwidth-api.sh done: qos-bandwidth-sweep.sh deployed, cron seeded (*/5 * * * *), crond confirmed running, /api/qos-bandwidth deployed and verified. ==="
```

- [ ] **Step 2: Run it and verify against the live VM**

```bash
chmod +x docker/provision/18-provision-qos-bandwidth-api.sh
./docker/provision/18-provision-qos-bandwidth-api.sh
```
Expected: script completes with the final `=== ... done ===` line, no `ERROR:` lines.

- [ ] **Step 3: Verify the crontab entry survives and the sweep genuinely runs on its own**

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "cat /etc/crontabs/root | grep qos-bandwidth"
```
Expected: exactly one line, `*/5 * * * * /usr/bin/qos-bandwidth-sweep.sh`. Re-run the provisioning script a second time and confirm the crontab still has exactly one such line (not duplicated):
```bash
./docker/provision/18-provision-qos-bandwidth-api.sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2223 root@localhost \
  "grep -c qos-bandwidth-sweep.sh /etc/crontabs/root"
```
Expected: `1`.

- [ ] **Step 4: Add step 18 to `docker/README.md`'s Provisioning section**

Read the existing steps 16/17 entries first (search for `# 16. Deploy` and `# 17. Deploy` in `docker/README.md`) and match their exact format precisely — script name, what it does, curl examples, file notes for both `qos-bandwidth-sweep.sh` and `docker/provision/www/api/qos-bandwidth`. Include: what the sweep does and why (accumulate-every-5-minutes because `nft reset` doesn't work here), the endpoint's response shape, and a worked curl example mirroring step 16/17's own style (mark a device priority, wait or manually seed a state file, GET `/api/qos-bandwidth`, show the real response, clean up test state afterward).

- [ ] **Step 5: Commit**

```bash
git add docker/provision/18-provision-qos-bandwidth-api.sh docker/README.md
```
Same git identity. Heredoc + `git commit -F`. Message: "feat(docker): add provisioning script for qos-bandwidth-sweep.sh and /api/qos-bandwidth"

---

### Task 4: Frontend — real "Bandwidth used today" on the Traffic & QoS screen

**Files:**
- Modify: `sadd-website.html` (the `advqos` entry in `screens`, new JS, `render()` dispatch, `state`)

This is the SECOND real section on the `advqos` screen (the first, "Priority devices," was built in Wave 6 — read `renderQosPriorityScreen`/`renderQosPriorityRow` at `sadd-website.html` around line 1560-1603 first, as the direct template for this task's own render function). `screens` is a large single-line JSON-like blob (each screen's HTML is a JSON string value with embedded `\n` literal newlines) — edit it via a small Node.js script doing `JSON.parse`/edit/`JSON.stringify`, never by hand-editing the raw file as text.

- [ ] **Step 1: Replace the fabricated sparkline + percentage markup in `screens['advqos']`**

The exact current markup (verified via extraction, byte-for-byte):
```
<div class="sec-label mt-24">Bandwidth used today</div>
        <div class="dcard" style="padding:18px;">
          <div class="bar-chart" style="height:64px;"><span style="height:35%;"></span><span style="height:55%;"></span><span style="height:40%;"></span><span style="height:75%;" class="hi"></span><span style="height:50%;"></span><span style="height:85%;" class="hi"></span><span style="height:60%;"></span></div>
          <div class="mini-log"><div class="mini-log-row"><strong>Living Room TV</strong><span>41%</span></div><div class="mini-log-row"><strong>Leo's Xbox</strong><span>26%</span></div><div class="mini-log-row"><strong>Everything else</strong><span>33%</span></div></div>
        </div>
```
Replace it (same `sec-label` heading text, same outer `.dcard`) with:
```
<div class="sec-label mt-24">Bandwidth used today</div>
        <div class="dcard" style="padding:18px;">
          <div id="qosBandwidthTotal" style="text-align:center;padding:12px 0;border-bottom:1px solid rgba(255,255,255,0.08);margin-bottom:8px;"><div style="font-size:28px;font-weight:700;">0 B</div><div style="font-size:12px;opacity:.7;">across 0 priority devices today</div></div>
          <div id="qosBandwidthList" class="mini-log"><div class="mini-log-row"><span>No priority devices marked yet</span></div></div>
          <div style="font-size:11px;opacity:.55;margin-top:10px;">Updated every 5 minutes · a firewall change elsewhere in the app can occasionally cause an early, partial reset for that window</div>
        </div>
```
This is static fallback/demo markup — `renderQosBandwidthScreen` (Step 3) overwrites `#qosBandwidthTotal` and `#qosBandwidthList`'s contents on a successful fetch, and leaves this exact static state in place on a failed fetch (matching every other real section's fallback-to-demo-data behavior in this file). The `.bar-chart` sparkline is dropped entirely (no real data source backs it — same reasoning Network & VLANs' device-count uses a static "—" instead of a fabricated number, Wave 4).

Do this via a Node script — `screens` genuinely is strict, valid JSON as a value (double-quoted keys and strings throughout), confirmed by direct test (`JSON.parse` on the extracted literal succeeds and round-trips cleanly through `JSON.stringify` with all 48 keys intact) — use `JSON.parse`/`JSON.stringify` directly, no `eval` needed:
```js
const fs = require('fs');
const path = 'sadd-website.html';
let html = fs.readFileSync(path, 'utf8');
const match = html.match(/const screens = (\{.*?\});/s);
if (!match) throw new Error('screens object not found');
const screens = JSON.parse(match[1]);
const oldBlock = '<div class="sec-label mt-24">Bandwidth used today</div>\n        <div class="dcard" style="padding:18px;">\n          <div class="bar-chart" style="height:64px;"><span style="height:35%;"></span><span style="height:55%;"></span><span style="height:40%;"></span><span style="height:75%;" class="hi"></span><span style="height:50%;"></span><span style="height:85%;" class="hi"></span><span style="height:60%;"></span></div>\n          <div class="mini-log"><div class="mini-log-row"><strong>Living Room TV</strong><span>41%</span></div><div class="mini-log-row"><strong>Leo\'s Xbox</strong><span>26%</span></div><div class="mini-log-row"><strong>Everything else</strong><span>33%</span></div></div>\n        </div>';
const newBlock = '<div class="sec-label mt-24">Bandwidth used today</div>\n        <div class="dcard" style="padding:18px;">\n          <div id="qosBandwidthTotal" style="text-align:center;padding:12px 0;border-bottom:1px solid rgba(255,255,255,0.08);margin-bottom:8px;"><div style="font-size:28px;font-weight:700;">0 B</div><div style="font-size:12px;opacity:.7;">across 0 priority devices today</div></div>\n          <div id="qosBandwidthList" class="mini-log"><div class="mini-log-row"><span>No priority devices marked yet</span></div></div>\n          <div style="font-size:11px;opacity:.55;margin-top:10px;">Updated every 5 minutes · a firewall change elsewhere in the app can occasionally cause an early, partial reset for that window</div>\n        </div>';
if (!screens['advqos'].includes(oldBlock)) {
  throw new Error("old block not found verbatim in screens['advqos'] — re-extract and check for drift before proceeding");
}
screens['advqos'] = screens['advqos'].split(oldBlock).join(newBlock);
html = html.replace(match[0], 'const screens = ' + JSON.stringify(screens) + ';');
fs.writeFileSync(path, html);
console.log('OK');
```
After running it, re-parse the file the same way (fresh `require('fs').readFileSync` + the same regex + `JSON.parse`) and confirm exactly 48 keys with only `advqos`'s value differing from before — the same verification approach used by every prior wave's frontend task.

- [ ] **Step 2: Add `state.qosBandwidthRenderId`**

Add `, qosBandwidthRenderId: 0` to `state` (find the `const state = { ... }` line and add it alongside the other `*RenderId` fields, e.g. next to `qosPriorityRenderId: 0`).

- [ ] **Step 3: Add the render function**

Insert after `renderQosPriorityScreen`'s closing `}` (found in Step 1's read of `sadd-website.html` around line 1603):

```js
  // ---- Traffic & QoS "Bandwidth used today" card: a REAL, read-only display,
  //      GET /cgi-bin/api/qos-bandwidth. Second independent real section on this
  //      screen (Priority devices, above, is the first — Wave 6) — own render-id,
  //      own fetch, fired alongside renderQosPriorityScreen from the same
  //      if(state.screen === 'advqos') dispatch block, matching advwireguard's own
  //      one-independent-section-per-render-call precedent (Wave 6). No click
  //      handlers — this card has no interactive elements at all. ----
  function formatBytesToday(n){
    if(typeof n !== 'number' || !isFinite(n) || n < 0) n = 0;
    if(n < 1024) return n + ' B';
    if(n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
    return (n / (1024 * 1024)).toFixed(2) + ' MB';
  }

  function renderQosBandwidthRow(entry, deviceNamesByMac){
    // Guard against a missing mac/bytesToday (same defense-in-depth pattern
    // renderQosPriorityRow/renderWireguardClientRow already establish in this
    // file): one malformed entry degrades to nothing, not a thrown error that
    // blanks the whole list.
    if(!entry || !entry.mac || typeof entry.bytesToday !== 'number') return '';
    const name = deviceNamesByMac[entry.mac.toLowerCase()] || entry.mac;
    return '<div class="mini-log-row"><strong>'+escapeHtml(name)+'</strong><span>'+escapeHtml(formatBytesToday(entry.bytesToday))+'</span></div>';
  }

  async function renderQosBandwidthScreen(){
    const myRenderId = state.qosBandwidthRenderId;
    const [bandwidthData, devicesData] = await Promise.all([
      fetchRouterApi('/cgi-bin/api/qos-bandwidth'),
      fetchRouterApi('/cgi-bin/api/devices')
    ]);
    if(state.screen !== 'advqos' || state.qosBandwidthRenderId !== myRenderId) return;
    const totalEl = document.getElementById('qosBandwidthTotal');
    const listEl = document.getElementById('qosBandwidthList');
    if(!totalEl || !listEl) return;
    const deviceNamesByMac = {};
    if(Array.isArray(devicesData)){
      devicesData.forEach(d => { if(d.mac) deviceNamesByMac[d.mac.toLowerCase()] = d.hostname || d.ip || d.mac; });
    }
    if(Array.isArray(bandwidthData)){
      const validEntries = bandwidthData.filter(e => e && e.mac && typeof e.bytesToday === 'number');
      const totalBytes = validEntries.reduce((sum, e) => sum + e.bytesToday, 0);
      const count = validEntries.length;
      totalEl.innerHTML = '<div style="font-size:28px;font-weight:700;">'+escapeHtml(formatBytesToday(totalBytes))+'</div><div style="font-size:12px;opacity:.7;">across '+count+' priority device'+(count === 1 ? '' : 's')+' today</div>';
      if(count === 0){
        listEl.innerHTML = '<div class="mini-log-row"><span>No priority devices marked yet</span></div>';
      } else {
        listEl.innerHTML = validEntries.map(e => renderQosBandwidthRow(e, deviceNamesByMac)).join('');
      }
    } else {
      if(!listEl.querySelector('.api-fallback-notice')){
        const notice = document.createElement('div');
        notice.className = 'api-fallback-notice';
        notice.textContent = "Can't reach router — showing demo data";
        listEl.insertAdjacentElement('afterbegin', notice);
      }
    }
  }
```

- [ ] **Step 4: Wire the dispatch point**

`render()`: find Wave 6's existing `if(state.screen === 'advqos'){ state.qosPriorityRenderId++; renderQosPriorityScreen(); }` line and add a SECOND, separate `if` block immediately after it (matching this file's established one-`if`-per-render-call convention, e.g. `advwireguard`'s two independent sections just above it):
```js
      if(state.screen === 'advqos'){ state.qosBandwidthRenderId++; renderQosBandwidthScreen(); }
```

No click handler wiring needed — this card has no buttons, toggles, or inputs, purely a display.

- [ ] **Step 5: Verify against the live VM**

No browser available in this environment — verify via grep-confirms, `node --check` on the extracted `<script>` block, a fresh valid JSON/object re-parse of `screens` (48 keys, unchanged key set except `advqos`'s value), careful manual code tracing, and direct curl exercise of `/api/qos-bandwidth` and `/api/qos-priority` together (mark a device priority, seed a state file over SSH, confirm the values `renderQosBandwidthScreen` would compute — total, count, per-row formatted bytes — match what a manual trace of the function against that same JSON response produces). Confirm the diff to `screens['advqos']` is minimal — only the Bandwidth used today block changed, the Priority devices section and everything else on that screen untouched. Clean up any test state left on the VM afterward (`uci -q delete firewall.qospriority_<test mac>; uci commit firewall; fw4 reload; rm -f /etc/qos-bandwidth/*.txt`).

- [ ] **Step 6: Commit**

```bash
git add sadd-website.html
```
Same git identity. Heredoc + `git commit -F`. Message: "feat(website): wire Traffic & QoS's Bandwidth used today card to real per-device totals"

---

### Task 5: Documentation closeout

**Files:**
- Modify: `docker/README.md` (Known Limitations)
- Modify: `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` (Full roadmap's Wave 9 entry — cross-reference, don't merge the new spec's content in)
- Modify: `docs/superpowers/specs/2026-09-02-qos-bandwidth-today-design.md` (mark it done, if it has a status marker — check; if not, this step is just the other two files)

- [ ] **Step 1: `docker/README.md` Known Limitations**

Add bullets covering, honestly: (a) this feature only covers QoS-priority-marked devices, not every device on the network — disclosed directly in the UI's own "across N priority devices" subtitle, same "narrow, not exhaustive" shape as Ad Blocking's fixed domain list; (b) the counter can undercount (never overcount) if an unrelated write endpoint's own `fw4 reload` fires between two 5-minute sweep ticks — real and proven live during Task 1's testing, not hypothetical; (c) no cleanup/rotation mechanism exists for `/etc/qos-bandwidth/*.txt` files — they accumulate one file per device per day indefinitely in this wave (this VM's own state doesn't persist across `docker compose down` anyway, per this file's own existing Known Limitations, so this is a soft concern in practice, not a hard one). Update the write-endpoint count if this changes it — VERIFY by listing `docker/provision/www/api/` and checking each file's `REQUEST_METHOD` dispatch yourself; `/api/qos-bandwidth` is GET-only, so it does NOT belong in the write-endpoint count, but it DOES belong in the read-only-endpoint disclosure list (it discloses which devices are marked priority and their real byte counts — extend that list the same way Wave 8's own closeout extended it for `/api/safe-search`/`/api/blocked-sites`).

- [ ] **Step 2: Main roadmap doc's Wave 9 entry**

Read the current Wave 9 entry in `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` (search for `**Wave 9`) and update its "Bandwidth used today" bullet to note it was pulled out and built as a scope-changed redesign, cross-referencing `docs/superpowers/specs/2026-09-02-qos-bandwidth-today-design.md` by path — do NOT merge that spec's content into this doc; a one-or-two-sentence pointer is correct, matching how this task's own spec was written to be cross-referenced rather than folded in.

- [ ] **Step 3: Commit**

```bash
git add docker/README.md docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md
```
Same git identity. Heredoc + `git commit -F`. Message: "docs: Bandwidth Used Today closeout — README limitations, roadmap cross-reference"

---

## After all tasks

Dispatch one final whole-feature integration-level code-quality review (a fresh `superpowers:code-reviewer` subagent, given the full diff across all 5 tasks) — pay particular attention to: whether the sweep's `fw4 reload` call could ever race with or disrupt another concurrently-running write endpoint's own uci changes (this project's established `uci commit`/`fw4 reload` sequencing precedent should already cover this, but confirm rather than assume for a NEW script calling it on a timer, not in response to a user action); whether the frontend's total/count computation genuinely matches what the backend's response shape guarantees; and whether the whole feature's own disclosed "undercounts, never overcounts" limitation is actually true given the exact arithmetic used (trace it, don't just trust the comment). Fix anything it raises, commit, then report this feature complete using the same format every prior Wave 1-8 completion summary in this project used.
