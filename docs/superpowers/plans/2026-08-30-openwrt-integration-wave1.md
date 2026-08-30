# Real OpenWrt Integration — Wave 1 (Devices + Firewall) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `devices` and `advfirewall` screens in `sadd-website.html` driven by a real, running OpenWrt instance (Docker + KVM) instead of hardcoded demo data, with a small in-image Lua API daemon as the only thing that talks to `uci`/`ubus`/`nft`.

**Architecture:** See `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` for the full design and roadmap. Summary: a real OpenWrt x86-64 VM boots under QEMU/KVM inside Docker; `uhttpd` inside that VM serves both the static frontend file and a `/api/*` Lua backend (same-origin, no CORS); the frontend's `devices`/`advfirewall` screens fetch from `/api/*` with a fallback to today's static demo data if unreachable. Every other screen is untouched.

**Tech Stack:** Docker, QEMU/KVM, real OpenWrt 23.05.5 (or newer if Task 1 finds a better fit), Lua (OpenWrt's native `uhttpd` scripting layer) or CGI-style Lua scripts, `uci`/`ubus`/`nft`/`dnsmasq`. Frontend: vanilla JS `fetch`, same single-file pattern as the rest of `sadd-website.html`.

**Before Task 1, read this — real investigation already done:** `docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md`'s "Environment bring-up: findings from a live investigation" section documents hands-on findings from a real session: KVM is confirmed available, the official OpenWrt combined image is confirmed bootable (a known benign gzip quirk was found and worked around), a proven-working direct-QEMU boot path exists at `docker/Dockerfile.qemu-direct`, and the current `docker/docker-compose.yml` (based on `albrechtloh/openwrt-docker`) is confirmed to detect KVM correctly but fails at a documented, specific step. Task 1 continues from these findings — it does not start from zero.

---

### Task 1: Finish environment bring-up — a host-reachable, real OpenWrt VM in Docker

**Files:**
- Modify: `docker/docker-compose.yml`
- Create: `docker/README.md` (document the final working setup — exact commands, exact ports, how to reach LuCI/SSH/the API)
- Possibly modify/replace: `docker/Dockerfile.qemu-direct` (already proven to boot the kernel; may need networking added if this becomes the final path)

**Context:** `docker-compose.yml` currently runs `albrechtloh/openwrt-docker:latest`, which detects KVM correctly but fails during its own self-discovery step with:
```
nsenter: failed to execute docker: No such file or directory
ERROR: Status 127 while: nsenter --target 1 --uts --net --ipc --mount docker inspect -f '{{.State.Pid}}' $(cat /etc/hostname) (line 93/179)
```
This happens because the image runs with `pid: "host"` and tries to `nsenter --target 1 --mount` (the true host's root mount namespace) to exec a `docker` CLI binary there. On a bare-metal Linux Docker host this works because `docker` is installed on the host. On Docker Desktop (this environment), the actual host namespace is a minimal LinuxKit VM with no `docker` binary — so this specific self-discovery mechanism can't succeed here.

- [ ] **Step 1: Try mounting the Docker socket.** Add to `docker/docker-compose.yml` under the `openwrt` service:
```yaml
    volumes:
      - data:/storage/
      - /var/run/docker.sock:/var/run/docker.sock
```
Run `docker compose up -d` from `docker/`, then watch logs: `docker compose logs -f`. If the same `nsenter: failed to execute docker` error still appears, this didn't help — move to Step 2. If a *different* error appears (e.g. it gets further and fails elsewhere), that's progress — keep iterating on this path for up to ~30 more minutes of focused effort before falling back to Step 2's approach.

- [ ] **Step 2: Check upstream for a known fix.** Before hand-rolling anything, check https://github.com/AlbrechtL/openwrt-docker/issues (search terms: "docker desktop", "nsenter", "windows", "wsl") for an existing report/workaround. If one exists and looks safe to apply, apply it and retest.

- [ ] **Step 3 (fallback if Steps 1-2 don't resolve it within reasonable effort): hand-roll veth networking around the already-proven direct-QEMU path.** `docker/Dockerfile.qemu-direct` already successfully boots the real OpenWrt kernel (confirmed: full boot log reaching a console prompt, `br-lan` coming up) — the only missing piece is host-reachable networking, since the investigation used QEMU's simplistic usermode NAT (`-netdev user`) which doesn't suit a router guest that wants to be its own DHCP server/gateway on its LAN bridge.

  Replace the `-netdev user,...` line in `docker/Dockerfile.qemu-direct`'s QEMU invocation with a TAP-based setup: create a tap device in the container's network namespace (requires the container to run with `--cap-add=NET_ADMIN`, already present), attach it to QEMU via `-netdev tap,id=net0,ifname=tap0,script=no,downscript=no -device virtio-net-pci,netdev=net0`, then bridge/route the container's own network to that tap device so the guest's `br-lan` IP (default `192.168.1.1`) becomes reachable from outside the container (e.g. via `iptables`/`socat` port-forwarding from the container's exposed ports to `192.168.1.1:80`/`:22`, since Docker's own `-p` port mapping only forwards to the container's own IP, not into the QEMU guest — you likely need a small forwarding step, such as `socat TCP-LISTEN:80,fork TCP:192.168.1.1:80 &` started in the container's entrypoint after the guest is up, or an `iptables` DNAT rule on the container's own network namespace).

  This is real, fiddly networking work with no single guaranteed-correct recipe — budget real iteration time, verify each piece (tap device created? guest sees it as eth0? guest's br-lan comes up with an IP? is that IP reachable via ping from inside the container? does a forwarding rule/process actually relay host-container traffic to it?) rather than assuming success.

- [ ] **Step 4: Verify host reachability**, however Step 1-3 resolved it. From outside the container (i.e. from this repo's normal shell, not `docker exec`):
```bash
curl -sI http://localhost:<mapped-port>/
```
must return *some* HTTP response (even a bare default `uhttpd` page, not a 404/refused/timeout) proving the request reached the real OpenWrt VM's web server. Also verify SSH reachability: `nc -zv localhost <mapped-ssh-port>` (or equivalent) succeeds.

- [ ] **Step 5:** Write `docker/README.md` documenting: the exact final `docker-compose.yml` approach that worked, exact commands to bring it up (`docker compose up -d` from `docker/`), exact ports/URLs to reach LuCI and SSH and (later) the `/api/*` backend, how to tear it down (`docker compose down -v`), and a troubleshooting note about the two bugs found in this investigation (gzip trailing-garbage on the official image, and the wrapper's disk-boot/nsenter issues) so nobody re-discovers them from scratch.

- [ ] **Step 6: Commit**
```bash
git add docker/
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "infra: finish OpenWrt-in-Docker environment bring-up, host-reachable"
```

---

### Task 2: Verify `uci`/`ubus`/`nft` tooling and find the real DHCP lease data source

**Files:**
- Create: `docker/facts.md` (short, concrete findings doc — exact commands, exact paths — that Tasks 3, 5, and 7 will read before writing their Lua code)

**Context:** This task is pure investigation, done by SSHing (or console-attaching) into the now-running real OpenWrt VM from Task 1. Do not guess at command syntax or file paths in later tasks — confirm them here first.

- [ ] **Step 1:** SSH into the VM (`ssh root@localhost -p <mapped-ssh-port>`, or via whatever console access Task 1's approach provides). Confirm these all work and capture their actual output shape:
  - `uci show network`
  - `uci show firewall`
  - `nft list ruleset` (confirms `firewall4`/nftables is active and not erroring)
  - `ubus list` (see what's available — specifically look for anything under `dhcp`, `network.device`, `system`)
  - `cat /tmp/dhcp.leases` (the traditional dnsmasq lease file location — confirm it exists and inspect its line format; if empty, that's fine for now, just confirm the path)

- [ ] **Step 2:** Write `docker/facts.md` with: the exact confirmed lease file path and its line format (dnsmasq's format is typically `<expiry-epoch> <mac> <ip> <hostname> <client-id>` — confirm this is actually what's in the file, don't assume), a copy of `uci show firewall`'s actual output (to inform the exact section-naming Task 7 will manipulate — real OpenWrt firewall configs use a mix of named and anonymous `config redirect` sections, confirm which this VM has), and a note on whether `ubus call dhcp ...` (if the `dhcp` ubus object exists) is a viable alternative to the lease file.

- [ ] **Step 3: Commit**
```bash
git add docker/facts.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: capture confirmed uci/ubus/nft facts from the running OpenWrt VM"
```

---

### Task 3: Install uhttpd Lua/CGI support, serve a minimal `/api/ping` endpoint

**Files:**
- Create (inside the VM, then captured as a repo-tracked provisioning script): `docker/provision/01-install-api-packages.sh`, `docker/provision/www/api/ping` (or `.lua`, depending on what Step 1 finds works)

**Context:** Whatever gets installed/configured by hand over SSH during this task must also be captured as a repeatable script in the repo (`docker/provision/`), since the VM's own disk state shouldn't be the only copy of this — Task 1's `docker/README.md` should be updated (in this task) to say how/when these provisioning scripts get run against a fresh VM.

- [ ] **Step 1:** Over SSH, try `opkg update && opkg install uhttpd-mod-lua`. If that package doesn't exist or fails, fall back to CGI: `opkg install lua lua-cjson` (these should exist) and use `uhttpd`'s built-in CGI support (already present — no extra package) by placing an executable Lua script with a `#!/usr/bin/lua` shebang under `uhttpd`'s configured CGI directory (check `uci show uhttpd` for the current `cgi_prefix`/docroot; typically `/www/cgi-bin`).

- [ ] **Step 2:** Write a minimal endpoint (path depends on Step 1's outcome — e.g. `/www/cgi-bin/api/ping`) that outputs a valid HTTP response with a JSON body `{"ok":true}`. For a CGI script this means printing the `Content-Type` header, a blank line, then the body — e.g.:
```lua
#!/usr/bin/lua
print("Content-Type: application/json\n")
print('{"ok":true}')
```

- [ ] **Step 3: Verify.** `curl -s http://localhost:<mapped-port>/api/ping` (technical exact path depends on `cgi_prefix`) must return `{"ok":true}`.

- [ ] **Step 4:** Copy whatever files/config changes were made inside the VM into `docker/provision/` in this repo (so they're reviewable/repeatable, not only living inside the VM's disk state), and add a short section to `docker/README.md` on how to apply them to a freshly-booted VM (e.g. `scp` the `www/` tree over, run the install script over SSH).

- [ ] **Step 5: Commit**
```bash
git add docker/provision/ docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): install Lua/CGI API support, add /api/ping"
```

---

### Task 4: Serve `sadd-website.html` from the VM's `uhttpd`

**Files:**
- Modify: `docker/provision/` (add the frontend file / a step that copies it in)
- Modify: `docker/README.md`

- [ ] **Step 1:** Copy `sadd-website.html` into the VM's web docroot (check `uci show uhttpd` for the configured docroot, typically `/www`) as `index.html` (or alongside the existing default page — decide based on whether overwriting the default OpenWrt landing page is acceptable; it is, for this dev/test VM).
- [ ] **Step 2:** Add this copy step to the provisioning scripts/instructions from Task 3, so it's repeatable.
- [ ] **Step 3: Verify.** Open `http://localhost:<mapped-port>/` in a real browser. Confirm the app loads and is fully functional exactly as it is when opened via `file://` today — click through a few screens, confirm the search feature (built earlier this session) still works, confirm no console errors. This confirms same-origin hosting doesn't break anything already built.
- [ ] **Step 4: Commit**
```bash
git add docker/provision/ docker/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): serve sadd-website.html from the VM's uhttpd"
```

---

### Task 5: Devices API — real DHCP lease data

**Files:**
- Create: `docker/provision/www/api/devices` (Lua CGI script, or equivalent per Task 3's chosen mechanism)

**Context:** Use the exact lease file path/format confirmed in `docker/facts.md` (Task 2) — do not assume the traditional `/tmp/dhcp.leases` format without checking that file against what Task 2 actually found.

- [ ] **Step 1:** Write the endpoint to read the real lease file, parse each line into `{hostname, ip, mac, leaseExpires}`, and add a basic liveness signal — the simplest reliable option inside the VM is checking the kernel's ARP/neighbor table (`cat /proc/net/arp` — a MAC present there with a non-`00:00:00:00:00:00` entry and `REACHABLE`/valid flag is a reasonable "online" signal; document whatever heuristic is actually used, since perfect liveness detection isn't the point here — a plausible, real signal is). Output as a JSON array via `lua-cjson`.
- [ ] **Step 2: Verify — real device, not just plausible JSON.** Attach a second, throwaway container to the same Docker network the OpenWrt VM's LAN side is reachable on (exact mechanism depends on Task 1's final networking approach — a plain `docker run --rm -it --network <the-relevant-network> alpine sh` and running a DHCP client, or if that's not straightforward given Task 1's approach, at minimum confirm a *real* lease already present in the lease file from something that legitimately joined shows up correctly). `curl http://localhost:<mapped-port>/api/devices` must include that real entry.
- [ ] **Step 3: Commit**
```bash
git add docker/provision/
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): add /api/devices backed by real DHCP leases"
```

---

### Task 6: Frontend — wire the `devices` screen to `/api/devices`, with fallback

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the current `screens['devices']` HTML string and the `render()`/`goTo()` mechanism (established earlier this session, search feature work) before changing anything. The static device rows use `.list-item`/`.li-main`/`.status-pill` markup (confirm exact current classes by reading the file — do not assume from memory, this file has been edited many times this session).

- [ ] **Step 1:** Add a small fetch-with-timeout-and-fallback helper near the top of the `<script>` block:
```js
async function fetchRouterApi(path, opts){
  try{
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 1500);
    const res = await fetch(path, {...opts, signal: ctrl.signal});
    clearTimeout(t);
    if(!res.ok) throw new Error('bad status '+res.status);
    return await res.json();
  }catch(e){
    return null; // caller falls back to static demo data
  }
}
```
- [ ] **Step 2:** Change how the `devices` screen renders: instead of `screens['devices']` being used as-is by the existing `render()` function, add a check — if `state.screen === 'devices'`, call an async `renderDevicesScreen()` function that: renders the *existing static* `screens['devices']` HTML first (so there's no blank flash), then calls `fetchRouterApi('/api/devices')`; if it returns real data, replace the device-list portion of the DOM with real rows (same `.list-item` markup, built from the fetched data) and show nothing extra; if it returns `null` (unreachable), leave the static demo rows as-is and insert a small non-blocking notice element (e.g. `<div class="api-fallback-notice">Can't reach router — showing demo data</div>`) above the list — add minimal CSS for `.api-fallback-notice` matching the file's existing muted/notice styling conventions (check for an existing similar pattern, e.g. how `.search-empty` or offline-mode messaging is styled, and match it).
- [ ] **Step 3: Verify with the real VM running (from Task 1-5):** open the file via the VM's `uhttpd` (not `file://`), navigate to Devices, confirm real device rows render with no fallback notice. Then verify the fallback path: open the file via plain `file://` (no VM reachable from that origin) or temporarily point `fetchRouterApi` at a bad path, confirm the static demo rows + notice render instead, with no console error and no broken layout.
- [ ] **Step 4: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Devices screen to real /api/devices with fallback"
```

---

### Task 7: Firewall API — real port-forwarding rules (read + add + delete)

**Files:**
- Create: `docker/provision/www/api/firewall-rules` (or `.lua`)

**Context:** Use the exact `uci show firewall` shape confirmed in `docker/facts.md` (Task 2) for how `redirect` sections are actually named/structured on this VM.

- [ ] **Step 1: `GET`** — list current `config redirect` sections via `uci show firewall`, parse into `[{id, name, proto, src_dport, dest_ip, dest_port}, ...]`, output as JSON.
- [ ] **Step 2: `POST`** — read a JSON body `{name, proto, src_dport, dest_ip, dest_port}`, run `uci add firewall redirect`, set each field via `uci set firewall.@redirect[-1].<field>=<value>` (or the equivalent addressing scheme confirmed in Task 2's facts), `uci commit firewall`, then reload with `/etc/init.d/firewall reload` (fall back to `fw4 reload` if that init script doesn't exist/doesn't apply changes live — verify which actually works on this VM, don't assume). Respond with the newly created rule's id.
- [ ] **Step 3: `DELETE /api/firewall-rules/<id>`** — `uci delete firewall.<id>`, commit, reload. Respond with success/failure.
- [ ] **Step 4: Verify it's real, not just displayed.** Add a rule via `curl -X POST` with a test port (e.g. forward external `9999` to some internal test target's port), confirm it shows up in `nft list ruleset` inside the VM. Then do an actual connectivity proof: run a tiny listener on the internal target (e.g. `nc -l -p <port>` on a throwaway test container on the LAN side), and from outside the OpenWrt VM (from this repo's normal shell) attempt to reach the forwarded external port — confirm it connects. Delete the rule via `curl -X DELETE`, confirm the same connection attempt now fails.
- [ ] **Step 5: Commit**
```bash
git add docker/provision/
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(openwrt): add real GET/POST/DELETE /api/firewall-rules"
```

---

### Task 8: Frontend — wire the `advfirewall` port-forwarding section to the real API, with fallback

**Files:**
- Modify: `sadd-website.html`

**Context:** Read the current `screens['advfirewall']` HTML — it has a port-forwarding rules section (the Xbox/NVR rules referenced by the search feature's `searchIndex`) using `.rule-row`/`.rr-main`/`.rr-path` markup (confirmed class names from earlier this session's CSS-bug-fixing work — re-confirm they're still current by reading the file, don't assume unchanged). This screen needs both read (list rules) and write (add/delete a rule) wiring, unlike Task 6's read-only Devices screen.

- [ ] **Step 1:** Mirror Task 6's pattern: on navigating to `advfirewall`, render the static rules first, then `fetchRouterApi('/api/firewall-rules')`; on success, replace the rule-row list with real data (reusing `.rule-row` markup); on failure, leave static demo rules + the same `.api-fallback-notice` pattern from Task 6.
- [ ] **Step 2:** Wire whatever "add a rule" UI element already exists on this screen (read the file to find it — if there's no existing add-rule form/button, add a minimal one consistent with the screen's existing style) to `POST /api/firewall-rules` via `fetchRouterApi`, then re-render the list on success. If the API is unreachable (fallback mode), disable the add-rule control and show a small explanatory note rather than pretending to add a rule that won't really exist.
- [ ] **Step 3:** Wire each real rule's existing delete/remove control (or add one, matching the screen's style, if none exists) to `DELETE /api/firewall-rules/<id>`, re-rendering on success.
- [ ] **Step 4: Verify end-to-end via the UI itself** (not just curl, now that Task 7 already proved the API works via curl): with the real VM running, open the app through `uhttpd`, navigate to Firewall & Ports, add a rule through the UI, confirm it appears in the list; reload the page, confirm it's still there (proving it's real config, not just client-side state); delete it through the UI, confirm it's gone and reload again to confirm persistence of the deletion too.
- [ ] **Step 5: Commit**
```bash
git add sadd-website.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "feat(website): wire Firewall & Ports rules to real API with fallback"
```

---

### Task 9: Full Wave 1 verification pass

**Files:** none (verification only)

- [ ] **Step 1:** Fresh start: `docker compose down -v` then `docker compose up -d` from `docker/`, run through `docker/README.md`'s documented provisioning steps on the freshly-booted VM, confirm everything in Tasks 3-8 still works from a completely clean state (this is the real test of whether `docker/README.md` and `docker/provision/` actually capture everything needed, rather than relying on manual SSH state that only exists in one developer's already-configured VM).
- [ ] **Step 2:** Regression check on the rest of the app: with the VM up and the frontend served from it, click through a representative sample of the other 46 static desktop screens (they should render exactly as before — nothing about this wave should have touched them), and re-run the global search feature's existing test queries (from the earlier search feature work this session) to confirm nothing broke.
- [ ] **Step 3:** Regression check with the VM *down*: open `sadd-website.html` via plain `file://` (no VM reachable), confirm the whole app — including Devices and Firewall & Ports — still works exactly as it did before this wave, using static demo data with the fallback notices, no console errors, no broken layout.
- [ ] **Step 4:** If any of the above surfaces a bug, fix it (root-cause it properly, don't guess-and-check) and commit the fix. If everything passes cleanly, no commit is needed for this task.

---

## Self-review notes

- **Spec coverage:** every component in the design doc's Architecture/Components/Testing sections has a corresponding task (environment: Task 1-2; API daemon: Task 3, 5, 7; frontend: Task 4, 6, 8; end-to-end verification incl. the design's "real connectivity test" requirement: Task 7 Step 4, Task 9).
- **Placeholder scan:** Task 1 intentionally contains real, upfront-acknowledged uncertainty (which of Steps 1-3 will actually resolve the networking blocker) rather than a placeholder — this is a genuine open technical question already narrowed down by hands-on investigation to three concrete, ordered candidates, not an unspecified "figure it out." Every other task has concrete steps, commands, and code.
- **Type/naming consistency:** `fetchRouterApi`, `.api-fallback-notice`, `/api/devices`, `/api/firewall-rules` are used consistently by name across Tasks 5-8 wherever they're referenced.
- **Scope:** matches the approved Wave 1 scope exactly (Devices + Firewall & Port Forwarding only, desktop prototype only) — no other screens are touched by this plan.
