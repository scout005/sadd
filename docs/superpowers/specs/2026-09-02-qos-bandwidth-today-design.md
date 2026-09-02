# Real "Bandwidth Used Today" — Design

## Goal

Make Traffic & QoS's "Bandwidth used today" card real, against the running OpenWrt VM — but as a genuine **redesign**, not a "wire the existing mockup to real data" task like every prior wave in `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` (the main roadmap doc, Waves 1-8). This feature was re-examined at every wave boundary since Wave 5 (`docker/facts.md` §13, §16, §18) and consistently found blocked for the same reason: the mockup's own display is a *comparative* one (a 3-device percentage split summing to 100%, plus a 7-bar sparkline implying an hourly history) with no honest way to populate it — this VM only ever carries whatever trivial manual-test traffic a task happens to generate, so a real comparative breakdown would show one device near 100% and the rest near 0%, not a plausible split, and there's no way to make it representative without generating synthetic traffic, which this project has consistently avoided doing.

This spec changes what the feature *shows* — an absolute per-device byte count instead of a comparative percentage split — so it can be built honestly against real traffic, however small, the same way Ad Blocking's single absolute "blocked this week" count already does. It's cross-referenced from the main roadmap doc's Wave 9 entry, not merged into it, since it's a scope change rather than a "make the existing mockup real" task.

## Why a redesign, not a wire-up

The mockup's own numbers (`Living Room TV 41%`, `Leo's Xbox 26%`, `Everything else 33%`) only mean something if there's enough real, varied traffic across enough real devices for the split to be plausible. This VM structurally can't produce that (confirmed live, `docker/facts.md` §18: zero DHCP leases and a zero-packet counter at the moment of the Wave 9 survey). An absolute count per device sidesteps this entirely — "142 KB today" is honest and real regardless of how much or little traffic exists, the same way Ad Blocking's blocked-count is honest whether it's 3 or 300.

## Scope: only QoS-priority-marked devices

Only two things in this codebase currently create a per-device firewall rule with a real traffic counter attached: Device Pause (Wave 5, REJECT, only while paused) and QoS Priority (Wave 6, MARK, only while marked "priority"). There is no rule, and therefore no counter, for an arbitrary device that isn't in one of those two states. This spec reuses QoS Priority's existing `mangle_forward` MARK rules — a device must already be marked "priority" (via the same "+ Add priority device" flow Wave 6 built) to show up here at all. This is a real, disclosed narrowing, not an oversight: building counter-only rules for *every* leased device was considered and rejected as a materially bigger new mechanism than this feature's actual purpose justifies (see Non-goals).

## Architecture

```
qos-bandwidth-sweep.sh (cron, every 5 minutes)
  │  for each qospriority-<mac> uci firewall section:
  │    reads live nft counter (mangle_forward, tcp+udp summed)
  │    adds it onto /etc/qos-bandwidth/<mac>-<YYYYMMDD>.txt
  │  then, once per pass:
  │    fw4 reload   (zeroes every counter in the table — the only
  │                   working reset mechanism on this VM, see below)
        │
        ▼
GET /cgi-bin/api/qos-bandwidth
  → reads today's file per currently-marked device, no shell-out
  → [{"mac": "...", "bytesToday": N}, ...]
        │
        ▼
Browser (advqos screen, "Bandwidth used today" card)
```

## A real, confirmed-live finding this design depends on

`nft reset` — the standard, documented way to zero an nftables counter — **does not work on this VM**. Confirmed by direct testing (nftables v1.0.8, kernel 5.15.167): creating a rule with a known non-zero counter (`nft add rule ... counter packets 42 bytes 9999`), then running `nft reset rule ... handle N`, left the counter completely unchanged. Tried against both an inline rule counter and a named counter object; neither reset.

What *does* reliably zero counters: `fw4 reload`, because it fully tears down and regenerates the entire `inet fw4` table from `uci` config on every call — confirmed by injecting a throwaway rule directly into the live table with `nft` (bypassing `uci` entirely) and watching it disappear completely after `fw4 reload`, proving the whole table is rebuilt from scratch, not patched. This is the same command every existing write endpoint in this project already calls, so it's a proven, already-relied-on primitive — but it means **any** `fw4 reload`, anywhere in the app, zeroes **every** counter in the table, not just the ones this feature cares about. This is why the sweep has to poll and accumulate every 5 minutes rather than trusting the raw counter to hold a full day's traffic, and it's the source of the one disclosed limitation below.

## Components

### `qos-bandwidth-sweep.sh` (new, `docker/provision/lib/`)

Every 5 minutes (registered into `/etc/crontabs/root` by `docker/provision/18-provision-qos-bandwidth-api.sh`, the same seed-the-crontab-first requirement `docker/facts.md` §13 already established for `devpause-sweep.sh`):

1. List every `qospriority-*` uci firewall rule section (same enumeration `/api/qos-priority`'s own GET already does).
2. For each one's `src_mac`, sum the `mangle_forward` tcp+udp rule pair's `bytes` counter (both rules share the same MAC and mark value, confirmed in `docker/facts.md` §15).
3. Read `/etc/qos-bandwidth/<mac>-<YYYYMMDD>.txt` (UTC date; missing file = `0`), add the just-read counter's bytes, write the new total back.
4. After the full pass (all devices processed), run `fw4 reload` once — zeroing every counter in the table for the next 5-minute window.

No hour-comparison, no midnight special-case: a new UTC calendar date is simply a filename that doesn't exist yet, read as `0`. This sidesteps Wave 7's whole busybox-ash `$(( ))` arithmetic gotcha class entirely, since nothing here does arithmetic on an hour value.

**The disclosed limitation, stated plainly**: if some other write endpoint's own `fw4 reload` fires between two sweep ticks, it zeroes the raw counter before this sweep gets to read and accumulate it that window — silently undercounting (never overcounting) that device's total for the rest of the day by whatever traffic happened in that gap. Real, not theoretical — proven live in testing (see Testing below), not just asserted. Rare in practice since write actions aren't constant, and it degrades gracefully (a lower number, never a wrong-direction one).

### `docker/provision/www/api/qos-bandwidth` (new)

- `GET /cgi-bin/api/qos-bandwidth` → `[{"mac": "<mac>", "bytesToday": <int>}, ...]`, one entry per device that currently has a `qospriority-*` uci section (regardless of whether its file exists yet — a device marked seconds ago, before the first sweep tick, correctly reports `0`, not an error or omission).
- No `POST` — this is a derived, computed-only resource; there's nothing to write via this endpoint (marking a device priority still goes through `/api/qos-priority`, unchanged).
- Unlike every other endpoint in this directory, this one never shells out to `uci`, `io.popen`, or `nft` at all — it only enumerates `qospriority-*` uci sections (to know which MACs to report) and reads small flat files the sweep already wrote. The simplest GET this project has built.

### `docker/provision/18-provision-qos-bandwidth-api.sh` (new)

Same deploy-and-verify-only shape as every prior provisioning script (`16`/`17` as the immediate template): deploys `qos-bandwidth-sweep.sh` to the VM, seeds/confirms the crontab entry (mirroring `13-provision-devpause-api.sh`'s crontab-seeding precedent), deploys the endpoint to `/www/cgi-bin/api/qos-bandwidth`, `chmod +x`, verifies with a real `curl -sf` GET expecting a JSON array shape, and creates `/etc/qos-bandwidth/` if it doesn't already exist.

## Frontend changes (`sadd-website.html`, `advqos` screen)

The existing 7-bar sparkline (`.bar-chart` height-percentage spans) and 3-device percentage `.mini-log` rows are removed from this screen's markup — neither has any real data source under this design, and this project has consistently avoided shipping a visual element that implies data it doesn't have (the same reasoning that gave Network & VLANs a static "—" placeholder instead of a fabricated device-count, Wave 4).

Replaced with, per the approved visual option:
- A big total: the sum of every marked device's `bytesToday`, human-formatted (B/KB/MB), with a subtitle "across N priority devices today" (N = the array length).
- A per-device list below it: display name (cross-referenced against a fresh `/api/devices` fetch by MAC, same pattern `/api/qos-priority`'s own frontend already uses, falling back to the raw MAC for a device that isn't currently DHCP-leased) + that device's own formatted byte count.
- Empty state (zero marked devices): total shows `0 B`, list shows "No priority devices marked yet" — consistent tone with this file's other empty-list states.
- A short disclosure line under the card: updates every 5 minutes; a firewall change elsewhere in the app can occasionally cause an early, partial reset for that window — plain language, not the internal `fw4 reload` mechanism detail.
- New `state.qosBandwidthRenderId`, independent fetch-on-render (`renderQosBandwidthScreen`), fired alongside `renderQosPriorityScreen` in the same `if(state.screen === 'advqos')` structure Wave 6 already established — two independent real sections on one screen, matching `advwireguard`'s own precedent (Wave 6) of one `if` per render call.
- Standard fallback on fetch failure: static demo data (the original mockup's sparkline/percentages) plus the usual non-blocking "Can't reach router — showing demo data" notice — so an unreachable router doesn't regress the screen's existing appearance.

## Testing plan

Live against the VM, not simulated:
1. Mark a device priority (existing `/api/qos-priority` flow). The rule this matches (`iifname "br-lan" ether saddr <mac>`, in `mangle_forward`) only counts traffic genuinely forwarded from a LAN-side device, not router-originated traffic — the output-hook `ping` trick used during design investigation (`docker/facts.md` §19) proved `fw4 reload`'s reset behavior on the router's own `output`-chain traffic, which is a different, easier-to-generate chain; it does not by itself prove the `mangle_forward` MAC-matched path. Generating genuine matching traffic means marking **tap0's own real hardware MAC** as the priority device — every throwaway test container in this topology (`docker run --network container:openwrt ...`) shares that exact same MAC, not a distinct one per container (confirmed in `docker/provision/www/api/devices`' own header comment and `docker/facts.md` §1a/§10) — then generating an outbound packet from a `--network container:openwrt` container (the same technique `docker/facts.md` §10 already used to prove a real TCP SYN increments a real counter) and confirming the sweep's counter-read reflects it. Separately (and more simply, for testing the accumulation arithmetic itself in isolation from topology quirks), a counter can be given a known preset value directly via `nft add rule ... counter packets N bytes M` on a throwaway rule, the same technique used during design investigation to prove `fw4 reload`'s reset behavior — useful for deterministically testing the sweep's read-and-accumulate math without needing real traffic at all.
2. Run the sweep manually across multiple ticks with traffic generated between each; confirm the persisted total accumulates correctly (monotonically increasing, matching the sum of what was actually sent).
3. Day-rollover: pre-seed a "yesterday" file with a nonzero value, confirm "today" starts at `0` with no special-case code needed — proving the date-keyed-filename approach genuinely avoids any midnight logic.
4. **Reproduce the disclosed limitation, not just assert it**: trigger another endpoint's `fw4 reload` (e.g. a `POST` to `/api/device-pause`) between two sweep ticks with real traffic in between, and confirm the expected undercount actually happens — proof the documented limitation is real behavior, not a hedge.
5. Confirm `GET /cgi-bin/api/qos-bandwidth` for a freshly-marked device (before any sweep tick has run) correctly returns `bytesToday: 0`, not an error.
6. Confirm removing a device's priority marking (no `DELETE` exists on `/api/qos-priority`, so this is via manual SSH removal, matching that endpoint's own established limitation) correctly drops it from this endpoint's list on the next call, without deleting its historical `/etc/qos-bandwidth/*.txt` files (no cleanup mechanism for those is in scope — see Non-goals).

## Known limitations (to be added to `docker/README.md`)

- **Read-only, no auth** — same posture as every other endpoint in this project; this one discloses which devices are marked priority and their real byte counts, a new (small) disclosure surface added to the existing read-only-endpoint list.
- **Undercounts, never overcounts, when another endpoint reloads fw4 mid-window** — disclosed above and proven live in testing, not just asserted.
- **No per-device history beyond "today"** — `/etc/qos-bandwidth/*.txt` files accumulate indefinitely (one per device per day, forever) with no cleanup/rotation mechanism in this wave; a long-running real deployment would need one eventually, out of scope here (this VM's own state doesn't persist across `docker compose down` anyway, per the project's existing Known Limitations).
- **Only QoS-priority-marked devices are covered**, not every device on the network — the same "narrow, not exhaustive" shape as Ad Blocking's fixed domain list, disclosed directly in the empty-state/subtitle copy ("across N priority devices").

## Non-goals for this feature

- Counter-only rules for every leased device (not just priority-marked ones) — considered and rejected as a materially bigger new mechanism (a device-count's worth of new firewall rules, managed and cleaned up as devices join/leave) than this feature's real purpose justifies. Priority-marked devices are exactly the ones a user would already care about tracking.
- A cleanup/rotation mechanism for old per-day files — real infrastructure concern, not a UI-wiring one.
- Fixing the underlying `nft reset` no-op — out of scope; this is VM/nftables-version behavior, not something this project's code can change, and the `fw4 reload` workaround is sufficient for this feature's needs.
- Any change to `/api/qos-priority` itself — this spec only adds a new, independent, read-only endpoint alongside it.
