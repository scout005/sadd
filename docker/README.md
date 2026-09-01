# Real OpenWrt in Docker

A real OpenWrt 23.05.5 (x86-64) instance, booted with KVM-accelerated QEMU,
reachable from the host for LuCI, SSH, and a small `/api/*` backend the
frontend prototype talks to (thirteen screens/sections wired to it so far,
across six completed waves — Devices/Firewall & Ports, About/Diagnostics &
Logs, Settings/Guest Wi-Fi, Ad Blocking/Network & VLANs, Developer & API
Access/VPN Server (WireGuard)/Per-Device Controls, and, as of Wave 6, VPN
Server (WireGuard)'s Client devices list + Traffic & QoS). See
`docs/superpowers/specs/2026-08-30-openwrt-integration-pilot-design.md` for
the full design/roadmap and `docs/superpowers/plans/2026-08-30-openwrt-integration-wave1.md`,
`docs/superpowers/plans/2026-08-31-openwrt-integration-wave2.md`,
`docs/superpowers/plans/2026-08-31-openwrt-integration-wave3.md`,
`docs/superpowers/plans/2026-09-01-openwrt-integration-wave4.md`,
`docs/superpowers/plans/2026-09-01-openwrt-integration-wave5.md`, and
`docs/superpowers/plans/2026-09-01-openwrt-integration-wave6.md` for the
implementation plans this environment supports.

## Quick start

```bash
# One-time: download and prepare the OpenWrt disk image (gitignored — not
# committed, ~120MB; safe to re-run, it's a no-op if boot.img already exists)
bash docker/fetch-boot-image.sh

cd docker
docker compose up -d --build
```

Then:
- http://localhost:8081/ — before running the Provisioning steps below,
  this is OpenWrt's stock landing page (redirects to `cgi-bin/luci/`); once
  Provisioning step 3 has run, this serves `sadd-website.html` instead —
  LuCI is still reachable at `cgi-bin/luci/` directly either way, it just
  loses the auto-landing redirect from `/` (see "Why `/cgi-bin/api/ping`
  and not `/api/ping`" below for the docroot layout).
- SSH: `ssh root@localhost -p 2223` (no password set yet on a fresh image —
  OpenWrt prompts you to set one on first LuCI/SSH login)

Give it ~10-15 seconds after `docker compose up -d` for the kernel to boot
and services to start before the ports respond.

Tear down: `docker compose down` (add `-v` to also drop the named volume,
if one is in use — the current setup doesn't use one, state lives only in
the mounted `boot.img`, so `docker compose down` alone is enough for a
clean stop; deleting `boot-image/boot.img` and re-running `fetch-boot-image.sh`
gets you back to a completely fresh, unconfigured OpenWrt).

## How it works

```
docker compose up
        │
        ▼
Dockerfile.qemu-direct (debian:bookworm-slim + qemu-system-x86 + iproute2 + socat)
        │  entrypoint.sh:
        │  1. creates a tap device (tap0) in this container's network namespace
        │  2. assigns it 192.168.1.2/24 — the same subnet as OpenWrt's default
        │     br-lan (192.168.1.1), so the two are direct L2 neighbors
        │  3. starts socat relays: container:80 → 192.168.1.1:80,
        │     container:22 → 192.168.1.1:22
        │  4. execs qemu-system-x86_64, KVM-accelerated, disk = /boot.img
        │     (bind-mounted from docker/boot-image/boot.img), networking =
        │     the tap0 device (not QEMU's usermode/slirp NAT)
        ▼
Real OpenWrt kernel boots, br-lan comes up at 192.168.1.1 (its own static
default — OpenWrt never runs a DHCP client on its LAN interface)
        │
        ▼
docker-compose's `ports: 8081:80 / 2223:22` maps the host to this
container's own port 80/22 (where socat is listening), which relays
onward to the guest's real 192.168.1.1 over the tap link.
```

## Why this specific setup (not the two things tried first)

Two other approaches were tried and abandoned — both are documented in
detail, with exact error messages and root causes, in the design spec's
"Environment bring-up: findings from a live investigation" section:

1. **`qemux/qemu` generic wrapper** (this repo's original stub) — hit a
   benign-but-fatal gzip extraction bug on the official OpenWrt image, and
   even after working around that, its disk-boot logic couldn't boot a
   pre-built (non-installer) raw disk image correctly.
2. **`albrechtloh/openwrt-docker`** (purpose-built for OpenWrt specifically,
   including a documented `LAN_IF: veth` mode for exactly this
   no-physical-NIC scenario) — correctly detects KVM, but its container
   self-discovery step (`nsenter --target 1 --mount docker inspect ...`)
   requires a `docker` CLI binary to exist in the *true* host's root
   filesystem. That's true on a normal Linux Docker host (confirmed via
   the project's own issue tracker: the one case where this broke on
   native Linux was traced to Docker having been installed via `snap`,
   whose confinement hides the binary the same way — the actual maintainer
   fix was "install Docker via the normal apt method instead of snap").
   Docker Desktop's host namespace is a minimal, purpose-built LinuxKit VM
   that was never going to have a `docker` binary in it at all — this
   isn't a workaround-able config issue, it's an architectural mismatch
   with Docker Desktop specifically.

Also ruled out along the way: plain QEMU usermode/slirp networking
(`-netdev user,hostfwd=...`) genuinely cannot reach a router guest's own
address — slirp only forwards to whatever private address *it* hands the
guest (e.g. `10.0.2.15`), and OpenWrt's `br-lan` never requests one; it
just self-assigns `192.168.1.1` regardless. The tap-device approach above
is the minimum needed to give the guest's own chosen address a real,
reachable presence in the container's network namespace.

## Provisioning

The VM's own disk (`boot-image/boot.img`) is a running, mutable state, not
a durable/reviewable artifact — it's gitignored, and `docker compose down`
followed by deleting and re-fetching `boot.img` wipes it back to a bare,
unconfigured OpenWrt (see "Known limitations" below). Anything installed
or written by hand over SSH needs to be re-applied after that. The
`docker/provision/` scripts capture exactly that: what to run, in order,
against a fresh VM to get from a bare boot to a VM with the `/api/*`
backend ready.

**Important environmental fact these scripts work around:** this VM has no
WAN interface (see "Known limitations" below), so it has **no outbound
internet route at all** — `opkg update`/`opkg install <name>` genuinely
fail from inside the VM for every package, confirmed live (`opkg update`
fails with "Network unreachable" for every feed; `opkg install <name>`
then fails with "Unknown package" because there's no cached package list
to resolve names against). Because of this, `docker/provision/01-install-api-packages.sh`
runs on the **host** (which does have internet), not piped into an SSH
session on the VM — it downloads the two small `.ipk` files the VM needs
from the official OpenWrt feed, sha256-verifies them, copies them onto the
VM over `scp`, and only then runs `opkg install` there, against the local
files (which needs no network on the VM side).

After `docker compose up -d --build` (and the container has reported
`healthy`), run, from the repo root:

```bash
# 1. Install the Lua interpreter the CGI endpoint needs (see the script's
#    own header comment for exactly why uhttpd-mod-lua wasn't used and why
#    this can't just be `ssh ... opkg install lua`).
bash docker/provision/01-install-api-packages.sh

# 2. Copy the tracked API scripts onto the VM's CGI directory and make
#    them executable (this repo has core.filemode=false, so git does not
#    track the executable bit on these files — see the script's header
#    comment — so it's set explicitly on the VM after every copy).
bash docker/provision/02-copy-www.sh

# 3. Copy the frontend prototype (repo root's sadd-website.html) onto the
#    VM's docroot as index.html, so the VM's own uhttpd serves it at `/`.
bash docker/provision/03-copy-frontend.sh

# 4. Deploy the /api/devices endpoint (real DHCP-lease-backed device list)
#    and verify it responds with a JSON array. Self-contained/idempotent —
#    also re-runnable on its own against an already-provisioned VM.
bash docker/provision/04-provision-devices-api.sh

# 5. Deploy the /api/firewall-rules endpoint (real GET/POST/DELETE against
#    this VM's own UCI firewall config + fw4/nftables) and verify it
#    responds with a JSON array. Self-contained/idempotent, same pattern
#    as step 4.
bash docker/provision/05-provision-firewall-api.sh

# 6. Deploy the /api/system-info endpoint (real ubus-backed distro/
#    hardware/uptime info for the About screen) and verify it responds
#    with a JSON object. Self-contained/idempotent, same pattern as steps
#    4 and 5.
bash docker/provision/06-provision-system-info-api.sh

# 7. Deploy the /api/logs endpoint (real logread-backed recent-activity
#    log for the Diagnostics & Logs screen) and verify it responds with a
#    JSON array. Self-contained/idempotent, same pattern as steps 4-6.
bash docker/provision/07-provision-logs-api.sh

# 8. Create the baseline wireless config (this VM has NO wireless config at
#    all on a fresh boot — no wireless hardware for OpenWrt to have
#    auto-detected; see docker/facts.md Section 11) and deploy the
#    /api/wifi endpoint (real UCI-backed SSID + guest-network on/off state
#    for the Settings/Guest Wi-Fi screens) and verify it responds with a
#    JSON object. Idempotent AND self-healing (safe to re-run against an
#    already-configured VM — each section is checked for completeness via a
#    field-by-field readback, not just existence), unlike steps 4-7 this one
#    also creates real VM state, not just a stateless endpoint. If a section
#    is ever found partially/incorrectly configured (e.g. left behind by a
#    prior run that failed partway through), it's reverted (`uci revert
#    wireless`) and recreated rather than left broken and silently skipped
#    forever — same rollback-on-failure pattern as step 5's
#    /api/firewall-rules endpoint.
bash docker/provision/08-provision-wifi-api.sh

# 9. Create a baseline DNS ad-blocklist (this VM has NO dnsmasq confdir/
#    blocklist config at all on a fresh boot; see docker/facts.md Section 12)
#    via dnsmasq's own `confdir` mechanism (no new opkg package needed) and
#    deploy the /api/adblock endpoint (real dnsmasq-log-backed
#    enabled/blockedThisWeek state for the Ad Blocking screen) and verify it
#    responds with a JSON object. Idempotent AND self-healing, same pattern
#    as step 8: the blocklist file's content is checked byte-for-byte
#    (not just "does it exist") and both uci options are read back and
#    compared against their expected values; an incomplete/stale config
#    (e.g. left behind by a prior run, or a hand-edited file missing a
#    domain) is reverted (`uci revert dhcp`) and recreated rather than left
#    broken and silently skipped forever — same rollback-on-failure pattern
#    as steps 5 and 8. Also runs a genuine functional check every time (not
#    just after a fresh create): a real `nslookup doubleclick.net 127.0.0.1`
#    over SSH, confirmed to resolve to `0.0.0.0` — real proof the
#    confdir/logqueries/restart pipeline is actually in effect, not just
#    that uci claims it is.
bash docker/provision/09-provision-adblock-api.sh

# 10. Create the 4 missing baseline VLAN interfaces (this VM already has
#     network.lan = 192.168.1.0/24 from a stock boot; the demo VLANs shown
#     in sadd-website.html's screens['advnetwork'] — Kids/192.168.2.0/24,
#     IoT-Smart-Home/192.168.3.0/24, Guests/192.168.4.0/24,
#     Quarantine/192.168.5.0/24 — do not exist yet; see docker/facts.md
#     Section 12) via real `uci network` interface sections
#     (proto=static, device=br-lan.<2|3|4|5>, matching ipaddr/netmask) and
#     `/etc/init.d/network reload`, and deploy the /api/vlans endpoint
#     (real UCI + kernel-backed name/subnet/active state for the Network &
#     VLANs screen's VLAN list) and verify it responds with a JSON array of
#     all 5 networks. Idempotent AND self-healing, same two-layer pattern
#     as steps 8/9 (uci-completeness readback, revert+recreate on
#     incompleteness) PLUS a second, kernel-level layer this step alone
#     needs: after `network reload`, each `br-lan.N` device is checked to
#     genuinely show the `UP` flag in `ip link show` — not just that `uci`
#     claims the section is correct — since a real kernel VLAN
#     sub-interface, not just inert config, is what this step actually
#     creates (confirmed live in docker/facts.md Section 12: `ip link show`
#     shows a genuine, `UP`, `br-lan.2@br-lan`-style 802.1q interface). A
#     device found not up is handled the same revert-and-retry-once way as
#     an incomplete uci section, never left silently broken.
bash docker/provision/10-provision-vlans-api.sh

# 11. Install WireGuard support (wireguard-tools + the full 9-package
#     transitive kmod dependency chain — this VM has NO WireGuard config or
#     packages at all on a fresh boot; see docker/facts.md Section 14) and
#     bring up a real, persisted `wg0` interface (proto=wireguard,
#     listen_port=51820, addresses=10.9.0.1/24) via real `uci network`
#     config + `ifup`. Idempotent AND self-healing, same
#     verify-completeness/revert-and-retry-once discipline as steps 8-10 —
#     but unlike those, its "already done" check is kernel-level first (a
#     real `wg0` link up and `wg show wg0` succeeding), since a working
#     WireGuard interface is the thing being guaranteed, not just uci state.
#     The private key is generated once (`wg genkey` into
#     /etc/wireguard-privkey) and reused across re-runs, so the derived
#     public key stays stable across idempotent re-provisioning. Also
#     deploys and curl-verifies the /api/wireguard endpoint (real
#     ubus/`wg show`-backed running/port/publicKey status for the VPN
#     Server screen, plus a real on/off toggle over `network.wg0.disabled`)
#     onto the VM. As of Wave 6, this same step also deploys and
#     curl-verifies the /api/wireguard-clients endpoint (real per-client
#     WireGuard keypair generation, real `wireguard_wg0` uci peer sections,
#     and a real per-client enable/disable toggle) for the VPN Server
#     screen's "Client devices" list — folded into this step rather than a
#     separate script, the same "one feature, one step" reasoning step 13
#     already used for the devpause sweep + endpoint pair.
bash docker/provision/11-provision-wireguard-api.sh

# 12. Deploy the /api/ssh-key endpoint (real dropbear host-key rotation for
#     the Developer & API Access screen's "Rotate SSH key" button) and
#     verify GET is correctly rejected with 405 (this endpoint is
#     POST-only). Unlike steps 8-11, this needs no baseline VM state to
#     provision — dropbear already runs on every fresh boot with nothing new
#     to create first — so this step matches steps 4-7's "stateless
#     endpoint, nothing to provision beyond the file itself" shape. The
#     verify step deliberately checks GET's 405 rejection rather than
#     issuing a real POST, so running this provisioning script never itself
#     rotates the VM's real SSH host keys.
bash docker/provision/12-provision-ssh-key-api.sh

# 13. Deploy the per-device pause auto-expiry sweep, then the
#     /api/device-pause endpoint itself: copies
#     docker/provision/lib/devpause-sweep.sh onto the VM as
#     /usr/bin/devpause-sweep.sh, seeds /etc/crontabs/root with an
#     every-minute cron entry for it (idempotent — grep -qF guards against
#     duplicating the line on re-run), enables and starts cron, then
#     verifies crond is genuinely running via `pgrep crond` rather than
#     trusting the init script's own exit code (docker/facts.md Section 13:
#     `/etc/init.d/cron start` silently no-ops if /etc/crontabs/ is empty
#     when it runs — seeding the crontab first, before calling start, is
#     what avoids that trap here). This is the baseline-state half of the
#     Per-Device Controls feature: real pause CREATION is
#     /cgi-bin/api/device-pause's job, which this same step then deploys
#     (and curl-verifies GET returns the correct "not paused" shape for a
#     MAC with no active pause) — the sweep only ever DELETES expired
#     `devpause-<mac>` uci firewall rules whose custom `paused_until`
#     (epoch-seconds) option has passed, so provisioning it first (before
#     the endpoint that creates those rules) is still safe and correctly
#     ordered.
bash docker/provision/13-provision-devpause-api.sh

# 14. Deploy the /api/qos-priority endpoint (real per-device traffic
#     marking — a uci firewall rule with target=MARK, set_mark=0x2a,
#     src=lan, dest=wan, landing in the real mangle_forward nft chain — for
#     the Traffic & QoS screen's "Priority devices" list) and verify GET
#     responds with a JSON array. Like step 12's /api/ssh-key and step 13's
#     /api/device-pause, this needs no baseline VM state to provision — uci
#     firewall rule sections already exist as a concept on a fresh VM — so
#     this step is deploy-and-verify only, no baseline-config half. POST is
#     idempotent per MAC (a second POST for an already-marked device is a
#     no-op success, not a duplicate rule or an error), and there is no
#     DELETE (same read-mostly-list choice /api/vlans made — a rule created
#     here can currently only be removed by hand over SSH).
bash docker/provision/14-provision-qos-priority-api.sh

# 15. Deploy the per-device Bedtime enforcement sweep: copies
#     docker/provision/lib/bedtime-sweep.sh onto the VM as
#     /usr/bin/bedtime-sweep.sh, seeds /etc/crontabs/root with an
#     every-5-minutes cron entry for it (idempotent — grep -qF guards
#     against duplicating the line on re-run), enables and starts cron,
#     then verifies crond is genuinely running via `pgrep crond` rather
#     than trusting the init script's own exit code (same discipline as
#     step 13). This is the baseline-state half of the Bedtime feature: the
#     sweep reconciles every existing `bedtime-<mac>` uci firewall rule's
#     `enabled` option to match whether the current UTC hour falls in the
#     fixed 21:00-07:00 window, but never creates or deletes a rule itself
#     — real device-bedtime rule CREATION (`/cgi-bin/api/device-bedtime`)
#     is deployed by a later step in this plan, once that endpoint exists.
#     Safe and correctly ordered to run before that endpoint exists, same
#     "provision the enforcement half first" precedent step 13 established
#     for devpause-sweep.sh.
bash docker/provision/15-provision-bedtime-api.sh

# 16. Verify.
curl -s http://localhost:8081/cgi-bin/api/ping     # -> {"ok":true}
curl -sI http://localhost:8081/cgi-bin/api/ping    # -> Content-Type: application/json among the headers
curl -sI http://localhost:8081/                    # -> 200 OK, serving sadd-website.html
curl -sI http://localhost:8081/cgi-bin/luci/       # -> reachable (403 login-required, not 404)
curl -s http://localhost:8081/cgi-bin/api/devices  # -> JSON array of current DHCP leases (empty `[]` until a real client has a lease — see "Getting a real device onto the lease list" below)
curl -s http://localhost:8081/cgi-bin/api/firewall-rules  # -> JSON array of current port-forward rules (empty `[]` on a fresh VM)
curl -s http://localhost:8081/cgi-bin/api/system-info  # -> JSON object of real distro/hardware/uptime info, e.g. {"distribution":"OpenWrt","version":"23.05.5","revision":"r24106-10cc5fcd00","target":"x86/64","model":"QEMU Standard PC (i440FX + PIIX, 1996)","kernel":"5.15.167","uptime":117}
curl -s http://localhost:8081/cgi-bin/api/logs  # -> JSON array (newest-first, capped at 30) of real logread lines, e.g. [{"timestamp":"Mon Aug 31 15:18:55 2026","message":"authpriv.info dropbear[2232]: Exit (root) from <192.168.1.2:60990>: Disconnect received"}, ...]
curl -s http://localhost:8081/cgi-bin/api/wifi  # -> JSON object of real UCI wireless state, e.g. {"ssid":"Smith Family","guestEnabled":false}
curl -s http://localhost:8081/cgi-bin/api/adblock  # -> JSON object of real dnsmasq-blocklist state, e.g. {"enabled":true,"blockedThisWeek":4} — blockedThisWeek increases by exactly 1 per subsequent real blocked lookup (e.g. `ssh root@localhost -p 2223 nslookup doubleclick.net 127.0.0.1`), confirmed live
curl -s http://localhost:8081/cgi-bin/api/vlans  # -> JSON array of all 5 real networks, e.g. [{"name":"Main Network","subnet":"192.168.1.0/24","active":true},{"name":"Kids","subnet":"192.168.2.0/24","active":true},{"name":"IoT / Smart Home","subnet":"192.168.3.0/24","active":true},{"name":"Guests","subnet":"192.168.4.0/24","active":true},{"name":"Quarantine","subnet":"192.168.5.0/24","active":true}] — `active` reflects genuinely live kernel state: `ssh root@localhost -p 2223 ip link set br-lan.2 down` flips Kids' `active` to `false` immediately, confirmed live
curl -s http://localhost:8081/cgi-bin/api/wireguard  # -> JSON object of real WireGuard server state, e.g. {"running":true,"port":51820,"publicKey":"n4W57HtezCeRGFeKQ/PM19i2YrsN3OFNbgQETg/6x28=","subnet":"10.9.0.0/24"} — `running`/`publicKey` reflect genuinely live kernel state: `POST -d '{"enabled":false}'` makes `ip link show wg0` report "can't find device", `POST -d '{"enabled":true}'` brings the real interface back with the same public key, confirmed live
curl -s http://localhost:8081/cgi-bin/api/wireguard-clients  # -> `[]` on a fresh VM
curl -s -X POST -d '{"name":"Docs Test Client"}' http://localhost:8081/cgi-bin/api/wireguard-clients  # -> real client creation, e.g. {"ok":true,"id":"wgc_1788280178_722a2f","publicKey":"ruXtbMRJhith76Hid+c+pjMH+59JYah86EZb2eMqFxo=","config":"[Interface]\nPrivateKey = 2AbL415PbaXFA7+hFT3g4xUpuC0p/2OtE4w0jMFyKUQ=\nAddress = 10.9.0.2/32\n\n[Peer]\nPublicKey = n4W57HtezCeRGFeKQ/PM19i2YrsN3OFNbgQETg/6x28=\nEndpoint = smith-family.saddvpn.com:51820\nAllowedIPs = 10.9.0.0/24\nPersistentKeepalive = 25\n"} — confirmed live: `uci show network | grep wgc_1788280178_722a2f` shows a real `wireguard_wg0` peer section with this exact `public_key`/`allowed_ips`; a subsequent GET returns `[{"id":"wgc_1788280178_722a2f","name":"Docs Test Client","publicKey":"ruXtbMRJhith76Hid+c+pjMH+59JYah86EZb2eMqFxo=","enabled":true,"added":"Sep 01"}]`; the response's `PrivateKey` line is the one-shot secret — it is never written to uci and never appears in a later GET
curl -s -X POST -d '{"id":"wgc_1788280178_722a2f","enabled":false}' http://localhost:8081/cgi-bin/api/wireguard-clients  # -> {"ok":true,"enabled":false} — confirmed live: `ssh root@localhost -p 2223 "wg show wg0"` drops the peer from its listing entirely; `POST -d '{"id":"...","enabled":true}'` brings it back into `wg show wg0`'s output with the same public key and allowed-ips
curl -s -X POST http://localhost:8081/cgi-bin/api/ssh-key  # -> real dropbear RSA host-key rotation, e.g. {"ok":true,"fingerprint":"SHA256:6Kl/5/4foMm95Fv+cFOkg9KeqmAWqdvFjMqihufCN5k"} — confirmed live to genuinely change the real key each call: `ssh -p 2223 root@localhost "dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key | grep Fingerprint"` shows a different fingerprint before vs. after, matching the response's `fingerprint` field exactly, and a second POST changes it again to a third distinct value (not toggling between two); `curl -s http://localhost:8081/cgi-bin/api/ssh-key` (a GET) -> 405
curl -s "http://localhost:8081/cgi-bin/api/device-pause?mac=11:22:33:44:55:66"  # -> {"paused":false,"remainingSeconds":0} for a MAC with no active pause rule
curl -s -X POST -d '{"mac":"11:22:33:44:55:66","minutes":15}' http://localhost:8081/cgi-bin/api/device-pause  # -> real per-MAC block, e.g. {"ok":true,"paused":true,"remainingSeconds":900} — confirmed live: `uci show firewall | grep devpause-112233445566` shows a real `rule` section with `src='lan'`, `src_mac='11:22:33:44:55:66'`, `dest='wan'`, `target='REJECT'`; a subsequent GET for the same mac reports `paused:true` with a real, ticking-down `remainingSeconds`; and — proven via a genuine 65+ second wait for a real cron tick, not simulated — a rule whose `paused_until` has passed is actually removed by `/usr/bin/devpause-sweep.sh` (confirmed both for a single expired rule and for three rules expiring in the same minute, see the `devpause-sweep.sh` file note below for the exact live multi-expiry proof)
curl -s http://localhost:8081/cgi-bin/api/qos-priority  # -> `[]` on a fresh VM
curl -s -X POST -d '{"mac":"11:22:33:44:55:66"}' http://localhost:8081/cgi-bin/api/qos-priority  # -> {"ok":true,"mac":"11:22:33:44:55:66"} — confirmed live: `uci show firewall | grep qospriority_112233445566` shows a real `rule` section with `src='lan'`, `src_mac='11:22:33:44:55:66'`, `dest='wan'`, `target='MARK'`, `set_mark='0x2a'`; a subsequent GET returns `[{"mac":"11:22:33:44:55:66"}]`; `ssh root@localhost -p 2223 "nft list ruleset"` shows the real `mangle_forward` chain entries (`ether saddr 11:22:33:44:55:66 ... meta mark set 0x0000002a`, one for tcp and one for udp) — genuinely marking the device's forwarded traffic, not just config; a second identical POST is idempotent (`uci show firewall | grep -c qospriority_112233445566` stays at exactly 7 lines = 1 section, not 2)
```

**Step 3 in detail — overwriting the stock landing page is intentional:**
`uhttpd.main.home='/www'` (confirmed in `docker/facts.md`), and a stock
OpenWrt image already ships `/www/index.html` there as a small redirect
page to `cgi-bin/luci/`. `docker/provision/03-copy-frontend.sh` copies
`sadd-website.html` over that same path (`/www/index.html`), so visiting
`http://localhost:8081/` now serves the frontend prototype instead of the
auto-redirect. This was confirmed to be an acceptable tradeoff for this
dev/test VM: LuCI itself is untouched and still fully reachable directly
at `/cgi-bin/luci/` (returns a real login page, not a 404) — the only
thing lost is the auto-landing convenience redirect from `/`. The existing
`/www/cgi-bin/` directory (LuCI's CGI dispatcher plus the `/api/*`
scripts from Task 3) is a sibling directory and is not touched by this
script.

All three scripts accept `OPENWRT_HOST`/`OPENWRT_PORT` env var overrides if
you've remapped the compose ports; they default to `localhost`/`2223`,
matching this repo's `docker-compose.yml`.

**Why `/cgi-bin/api/ping` and not `/api/ping`:** `uci show uhttpd` on this
VM confirms `uhttpd.main.home='/www'` (the docroot) and
`uhttpd.main.cgi_prefix='/cgi-bin'` (uhttpd's built-in CGI dispatch
prefix under that docroot). `/www/cgi-bin/` already exists on a stock
image — the `luci` CGI dispatcher lives there — so
`docker/provision/www/` mirrors the *contents* of that directory
(currently just `api/ping`) and gets copied to `/www/cgi-bin/`
specifically, as a sibling of `luci`, not a replacement for it.

**Files:**
- `docker/provision/01-install-api-packages.sh` — side-loads a Lua
  interpreter (`lua` + its `liblua5.1.5` dependency) onto the VM.
- `docker/provision/02-copy-www.sh` — copies `docker/provision/www/` onto
  the VM's `/www/cgi-bin/` and chmods any CGI scripts executable.
- `docker/provision/www/api/ping` — the tracked source of truth for the
  `/api/ping` endpoint (a `#!/usr/bin/lua` CGI script using uhttpd's
  built-in CGI support — no extra uhttpd package needed for this). The
  copy living on the VM's disk is just where it happens to currently run;
  this file is what to edit.
- `docker/provision/03-copy-frontend.sh` — copies the repo root's
  `sadd-website.html` onto the VM as `/www/index.html`, so the VM's own
  uhttpd serves the frontend prototype at `http://localhost:8081/`. The
  repo root's `sadd-website.html` is the tracked source of truth; this
  script just re-copies it onto the VM's (untracked, gitignored) disk
  state after a fresh boot.
- `docker/provision/04-provision-devices-api.sh` — copies (and chmods,
  and curl-verifies) `docker/provision/www/api/devices` onto the VM's
  `/www/cgi-bin/api/devices`. A dedicated, self-contained step even
  though `02-copy-www.sh` already copies everything under
  `docker/provision/www/` generically (this file included) — see the
  script's own header comment for why.
- `docker/provision/www/api/devices` — the tracked source of truth for
  the `/api/devices` endpoint: parses `/tmp/dhcp.leases` into
  `{hostname, ip, mac, leaseExpires, online}` entries (`online` comes from
  cross-referencing each lease's own IP against `/proc/net/arp` — keyed by
  IP, not MAC, since every test client sharing tap0's one hardware MAC
  with the container's own relay address would otherwise collide with it;
  see the script's own header comment) and prints
  them as a JSON array. Hand-builds its JSON (with a defensive escaper)
  rather than installing `lua-cjson` — see the script's own header
  comment for the reasoning. Excludes the container's own static tap-relay
  address (`192.168.1.2`, see `docker/facts.md` Section 9) — moot in
  practice since that address is never DHCP-issued and this endpoint only
  ever iterates real lease-file lines, but a defensive IP-string check is
  in there too.
- `docker/provision/05-provision-firewall-api.sh` — copies (and chmods,
  and curl-verifies) `docker/provision/www/api/firewall-rules` onto the
  VM's `/www/cgi-bin/api/firewall-rules`. Same dedicated-step rationale as
  `04-provision-devices-api.sh`.
- `docker/provision/www/api/firewall-rules` — the tracked source of truth
  for the `/api/firewall-rules` endpoint: `GET` lists this VM's real
  `config redirect` (port-forward) sections (parsed from `uci show
  firewall`) as `[{id, name, proto, src_dport, dest_ip, dest_port}, ...]`;
  `POST` hand-parses a small flat JSON body (`{name, proto, src_dport,
  dest_ip, dest_port}` — no `lua-cjson`, see the script's own header
  comment), validates it, `uci add`s a new `redirect` section, immediately
  `uci rename`s it to a stable generated id (`fwd_<unix-time>_<6 hex
  chars>`, per `docker/facts.md` Section 4's recommendation — anonymous
  `@redirect[N]` indices shift when other rules are deleted), sets its
  fields (**`src` is hardcoded to `'wan'`** — see "Real connectivity test"
  below for why), `uci commit`s, and reloads live via `/etc/init.d/firewall
  reload`; `DELETE` (id from `PATH_INFO` or `?id=`) removes that section by
  its stable name the same way. Every value that reaches a shell command
  is quoted defensively (`shell_quote()`); the DELETE id is additionally
  restricted to `[%w_]+` and checked to actually be a `redirect` section
  before deletion.
- `docker/provision/06-provision-system-info-api.sh` — copies (and chmods,
  and curl-verifies) `docker/provision/www/api/system-info` onto the VM's
  `/www/cgi-bin/api/system-info`. Same dedicated-step rationale as
  `04-provision-devices-api.sh`.
- `docker/provision/www/api/system-info` — the tracked source of truth for
  the `/api/system-info` endpoint: shells out to `ubus call system board`
  and `ubus call system info` (already present on a stock OpenWrt image —
  no new opkg package needed) and returns a flat
  `{distribution, version, revision, target, model, kernel, uptime}`
  object shaped for the About screen. Both `ubus call` commands' output
  shapes were confirmed live against this VM before writing the endpoint
  (`docker/facts.md` Section 7 captured them first; re-confirmed via a
  fresh SSH session during this task, values matched field-for-field).
  Since every field this endpoint needs is a top-level-unique key in one
  command's known, fixed output, field extraction uses plain
  `string.match` patterns anchored on `"key":` rather than a general JSON
  parser (unlike `firewall-rules`, which does carry a small parser — but
  that one has to accept an *arbitrary* client-supplied POST body, a
  genuinely different problem) — see the script's own header comment for
  the full reasoning. Hand-builds its response JSON (with the same
  defensive escaper as `devices`/`firewall-rules`) rather than installing
  `lua-cjson`, for the same no-outbound-internet reason.
- `docker/provision/07-provision-logs-api.sh` — copies (and chmods, and
  curl-verifies) `docker/provision/www/api/logs` onto the VM's
  `/www/cgi-bin/api/logs`. Same dedicated-step rationale as
  `04-provision-devices-api.sh`.
- `docker/provision/www/api/logs` — the tracked source of truth for the
  `/api/logs` endpoint: shells out to `logread -l 30` (`logread`'s own
  built-in tail-style line cap — confirmed live via `logread --help`,
  confirmed to behave identically to `logread | tail -n 30`) and returns a
  JSON array of `{timestamp, message}` entries for the Diagnostics & Logs
  screen's "Recent activity" list. The real, live-confirmed `logread`
  output format is an asctime-style datetime prefix (weekday, month, day,
  `HH:MM:SS`, year) followed by `<facility>.<severity> <tag>[optional
  [pid]]: <message>`, e.g. `Mon Aug 31 15:16:32 2026 authpriv.info
  dropbear[2185]: Exit (root) from <192.168.1.2:50572>: Disconnect
  received` — confirmed directly over SSH during this task, not assumed
  from generic syslog conventions. Only the fixed-width datetime prefix is
  split out into its own field; the facility/tag/message remainder is kept
  as one `message` string, since that boundary isn't unambiguous in
  general (message text itself can and does contain further colons) — see
  the script's own header comment for the full reasoning, the same
  "don't force a shape reality doesn't support" judgment call
  `system-info` documents for its own field extraction. `logread` always
  emits oldest-first; this endpoint reverses its capped output to
  newest-first to match the `advlogs` screen's existing static
  `.tech-row` list ordering (most-recent-activity-first), so Task 4's
  frontend wiring doesn't need to re-sort. Hand-builds its response JSON
  (with the same defensive escaper as `devices`/`firewall-rules`/
  `system-info`) rather than installing `lua-cjson`, for the same
  no-outbound-internet reason.
- `docker/provision/08-provision-wifi-api.sh` — unlike 04-07, this step
  does two things: (1) creates a baseline `/etc/config/wireless` on the VM
  over SSH (this VM has none at all on a fresh boot — see
  `docker/facts.md` Section 11 — so there's nothing to just copy/read the
  way firewall/system-info/logs had real underlying state already);
  (2) copies (and chmods, and curl-verifies)
  `docker/provision/www/api/wifi` onto the VM's `/www/cgi-bin/api/wifi`.
  Idempotent and self-healing: each section (`radio0`, `default_radio0`,
  `guest`) is skipped only if it already exists AND every one of its
  expected fields reads back correctly via `uci get
  wireless.<section>.<option>` — a bare `uci get wireless.<section>`
  succeeding (mere existence) is not enough, since that would also match a
  half-configured section left behind by a prior run that died partway
  through its own `uci set` sequence, and would then skip re-creating it
  forever. When a section exists but fails that completeness check, its
  uncommitted changes are reverted (`uci revert wireless`) and it's
  recreated from scratch, verified again, and only committed once complete
  (one retry, then a loud failure with a revert, never a silent partial
  commit) — same verify-before-commit/revert-on-failure pattern
  `docker/provision/www/api/firewall-rules` uses for its own POST handler.
  Re-running this script against an already-configured VM neither fails nor
  duplicates sections — confirmed live by running it twice in a row and
  diffing `uci show wireless` (identical, one of each section both times) —
  and re-running it against a VM with a deliberately-corrupted partial
  section correctly detects the incompleteness, reverts, and re-establishes
  the full correct config instead of leaving it stuck broken.
- `docker/provision/www/api/wifi` — the tracked source of truth for the
  `/api/wifi` endpoint: `GET` reads `uci get wireless.default_radio0.ssid`
  and `uci get wireless.guest.disabled`, returning `{ssid, guestEnabled}`
  where `guestEnabled` is `true` unless `disabled` reads exactly `'1'`
  (UCI's own disabled-option convention — absence of the option means
  enabled). Both section/option names match exactly what
  `08-provision-wifi-api.sh` creates. `POST` reads a JSON body
  `{guestEnabled: true|false}` (a minimal hand-rolled parser, same rationale
  as `firewall-rules`), sets `wireless.guest.disabled` to the inverse
  (`'0'` when `guestEnabled:true`, `'1'` when `false`), verifies the write
  before committing, `uci revert wireless` and a `Status: 500` on any
  partial failure, `Status: 400` on a missing/non-boolean `guestEnabled`,
  runs `wifi reload` (confirmed safe against this VM's phantom radio — just
  informational "not supported" lines, not a hang) after a successful
  commit, and responds with the new `{ssid, guestEnabled}` state — same
  verify-before-commit/rollback discipline as `firewall-rules`' POST
  handler. Hand-builds its response JSON (with the same defensive escaper
  as the other endpoints in this directory) rather than installing
  `lua-cjson`, for the same no-outbound-internet reason. Graceful
  degradation on `GET`: if a `uci get` fails for any reason (missing
  config/section, `uci` erroring), `ssid` falls back to `""` and
  `guestEnabled` falls back to `false` (matching the mockup's static
  "Guest network: Off" default) rather than crashing or emitting malformed
  JSON.
- `docker/provision/09-provision-adblock-api.sh` — same shape as
  `08-provision-wifi-api.sh`: (1) creates a baseline DNS blocklist on the VM
  over SSH (this VM has no dnsmasq `confdir`/blocklist config at all on a
  fresh boot — see `docker/facts.md` Section 12 for the confirmed live
  sequence this script uses unmodified: `mkdir -p
  /etc/dnsmasq.blocklist.d`, an `address=/<domain>/0.0.0.0` line per demo
  domain — `doubleclick.net`, `adservice.google.com`, `tracker.example.com`,
  the exact three shown in `sadd-website.html`'s `screens['adblock']`
  "This week" mini-log, confirmed by reading the actual HTML, not assumed —
  `dhcp.@dnsmasq[0].confdir` and `dhcp.@dnsmasq[0].logqueries=1` via `uci`,
  commit, `/etc/init.d/dnsmasq restart`); (2) copies (and chmods, and
  curl-verifies) `docker/provision/www/api/adblock` onto the VM's
  `/www/cgi-bin/api/adblock`. Idempotent and self-healing: the blocklist
  file's content is compared byte-for-byte against the expected three lines
  (not just "does the file exist") and both uci options are read back and
  compared against their expected values — a config left behind by a
  prior partial run, or hand-edited to drop a domain, is detected as
  incomplete rather than silently trusted. When incomplete, uncommitted
  `dhcp` changes are reverted (`uci revert dhcp`) and the whole config is
  recreated from scratch, verified again, and only committed once complete
  (one retry, then a loud failure with a revert) — same
  verify-before-commit/revert-on-failure pattern as
  `08-provision-wifi-api.sh` and `firewall-rules`' POST handler. Beyond the
  uci/file readback, this script also runs a genuine functional check every
  time it runs (not just after a fresh create): a real `nslookup
  doubleclick.net 127.0.0.1` over SSH, confirmed to return `Address:
  0.0.0.0` — real proof the confdir/logqueries/restart pipeline is actually
  in effect, not just that uci claims it is. Confirmed idempotent live by
  running it twice in a row against an already-configured VM (second run
  skips config creation entirely, logs "already exists and is complete,
  skipping", and still passes the functional nslookup check and endpoint
  redeploy/verify) and by running it against a VM with a deliberately
  stale/partial blocklist file (a leftover single-domain file from an
  earlier manual test) — correctly detected as incomplete, reverted, and
  recreated with the full three-domain content.
- `docker/provision/www/api/adblock` — the tracked source of truth for the
  `/api/adblock` endpoint: `GET` returns `{"enabled": <bool>,
  "blockedThisWeek": <int>}`. `enabled` is whether `uci get
  dhcp.@dnsmasq[0].confdir` currently equals the exact path
  `09-provision-adblock-api.sh` provisions
  (`/etc/dnsmasq.blocklist.d`) — checked live, not cached, so a
  hand-reverted or repointed config is correctly reported as disabled.
  `blockedThisWeek` counts real `logread` lines matching `config <domain>
  is 0.0.0.0` for each of the three blocklisted domains — the real, live-
  confirmed log signature `logqueries=1` produces for a blocked hit
  (`docker/facts.md` Section 12), genuinely distinct from `config error is
  REFUSED`, which is what every *other* lookup on this WAN-less VM shows
  regardless of blocking. Unlike `logs` (`logread -l 30`, capped for a short
  UI list), this endpoint runs plain `logread` with no line cap, so a count
  isn't silently truncated by unrelated log noise (dropbear session lines,
  etc.) crowding out older blocked-hit lines. Matching is a plain literal
  substring search (`string.find(line, needle, 1, true)`) rather than a
  `string.match` pattern, since the three domains are fixed known constants
  with nothing to capture — deliberately simpler than `logs`/`system-info`'s
  pattern-based field extraction, which both need capture groups for
  genuinely variable content. **"This week" is aspirational, documented as
  such in the code**: `logread`'s buffer is a small fixed-size ring, nowhere
  near a full week's history, so this counts everything currently in that
  buffer, not a true rolling 7-day count — real numbers, not guaranteed
  complete-week coverage; real week-long persistence is explicitly out of
  scope. Hand-builds its response JSON (no free-form string fields, so no
  escaper needed) rather than installing `lua-cjson`, for the same
  no-outbound-internet reason as every other endpoint in this directory.
  Graceful degradation: a failed `uci get` or `logread` degrades to
  `enabled:false` / `blockedThisWeek:0` rather than crashing or emitting
  malformed JSON.
- `docker/provision/10-provision-vlans-api.sh` — same shape as
  `08-provision-wifi-api.sh`/`09-provision-adblock-api.sh`: (1) creates the
  4 missing baseline VLAN `network` interface sections on the VM over SSH
  (this VM already has `network.lan` = 192.168.1.0/24 from a stock boot —
  see `docker/facts.md` Section 3 — but no config at all for the other 4
  demo VLANs shown in `sadd-website.html`'s `screens['advnetwork']`; see
  `docker/facts.md` Section 12 for the confirmed live sequence this script
  uses unmodified: `proto=static`, `device=br-lan.<N>`, matching
  `ipaddr`/`netmask`, `uci commit network`, `/etc/init.d/network reload`);
  (2) copies (and chmods, and curl-verifies)
  `docker/provision/www/api/vlans` onto the VM's `/www/cgi-bin/api/vlans`.
  VLAN id mapping chosen (matches each subnet's third octet, for
  readability): `kids`→id 2/`br-lan.2`/192.168.2.1, `iot`→id
  3/`br-lan.3`/192.168.3.1, `guests`→id 4/`br-lan.4`/192.168.4.1,
  `quarantine`→id 5/`br-lan.5`/192.168.5.1. Idempotent AND self-healing,
  with a SECOND verification layer `08`/`09` didn't need: (a)
  uci-completeness — each section is checked for every expected field via
  readback, not mere existence, same revert-and-recreate-on-incompleteness
  discipline as `08`/`09`; (b) kernel-liveness — after `network reload`,
  each `br-lan.N` device is independently checked to genuinely show the
  `UP` flag in `ip link show <device>` (not just that `uci` claims the
  section is correct), since this step is the first one in this directory
  that creates a real, kernel-verifiable interface, not just config/file
  state (confirmed live in `docker/facts.md` Section 12: a genuine, `UP`,
  802.1q `br-lan.2@br-lan`-style sub-interface). A device found not up
  after reload is handled the same revert+recreate+reload-once-more way as
  an incomplete uci section, never left silently broken. Confirmed
  idempotent live by running it twice in a row against an
  already-configured VM (second run skips all 4 sections' creation,
  confirms all 4 devices already up with no reload needed, and still
  passes the endpoint redeploy/verify) and confirmed the kernel-liveness
  check reflects genuinely live state (not just post-creation): manually
  running `ip link set br-lan.2 down` over SSH and then re-running this
  script detects the down interface, brings it back up via the
  revert+recreate+reload retry path, confirmed live.
- `docker/provision/www/api/vlans` — the tracked source of truth for the
  `/api/vlans` endpoint: `GET` returns
  `[{"name","subnet","active"}, ...]` for a fixed, known list of all 5
  networks (`lan`, `kids`, `iot`, `guests`, `quarantine`), in the same
  order as the mockup's VLAN list. `name` is a small hardcoded
  section-name → human-label map (uci section identifiers can't contain
  spaces/slashes, so there's no uci field to derive "IoT / Smart Home"
  from). `subnet` is computed, not hardcoded: `network.<name>.ipaddr` (a
  host address, e.g. `192.168.2.1`) AND `network.<name>.netmask` (e.g.
  `255.255.255.0`), via a hand-rolled 8-bit bitwise AND (Lua 5.1 on this VM
  has no native bitwise ops/`bit32`) applied octet-by-octet to get the real
  network address, plus a real popcount of the netmask's set bits for the
  CIDR prefix length (not an assumed `/24`) — formatted as
  `<network-address>/<prefix-len>` (e.g. `192.168.2.0/24`), confirmed live
  against all 5 real networks. `active` is real kernel interface state via
  `ip link show <device>` (`lan`→`br-lan`, the 4 VLANs→`br-lan.<N>`),
  checking for the exact `UP` flag token in the device's flag list —
  chosen over `ubus call network.interface.<name> status` (which also
  carries a real `up` boolean) because ubus's output is a much larger
  nested JSON object that would need a real parser this VM doesn't have
  (no lua-cjson), while `ip link show`'s flag list is one plain-text line
  a single Lua pattern parses robustly. Confirmed live that `active`
  reflects genuinely live state, not a cached value: manually bringing
  `br-lan.2` down over SSH and re-curling this endpoint immediately flips
  Kids' `active` to `false`; bringing it back up flips it back to `true`.
  Deliberately excludes a device-count field — out of scope per the plan
  (would need a real per-VLAN DHCP service, a materially bigger
  undertaking; this VM's dnsmasq still serves one shared lease pool off
  `lan`/`br-lan`) — the frontend keeps a static demo number for that
  column instead. Graceful degradation: any network whose `ipaddr`/
  `netmask` can't be read, or whose `ip link show` fails, still gets an
  entry in the response (the array is always exactly 5 entries), just with
  `subnet` falling back to `""` and/or `active` falling back to `false`
  rather than crashing or emitting malformed JSON. Hand-builds its
  response JSON (with the same defensive escaper as every other endpoint
  in this directory) rather than installing `lua-cjson`, for the same
  no-outbound-internet reason.
- `docker/provision/11-provision-wireguard-api.sh` — unlike 08-10, this step
  installs real opkg packages before touching any config (this VM has no
  WireGuard packages OR config of any kind on a fresh boot): the full
  9-package transitive kmod dependency chain plus `wireguard-tools`, all
  from the target-specific/kernel-version-pinned feed (see
  `docker/facts.md` Section 14 for exactly which two of opkg's own
  first-round error messages hide a second, undeclared dependency layer),
  downloaded on the host and `scp -O`'d to the VM's `/tmp/` (this VM has no
  outbound route, same reason 01 runs on the host). After `opkg install`,
  `modprobe wireguard` + `lsmod` are checked explicitly (opkg exiting 0
  alone isn't proof the module actually probes — confirmed live: an
  earlier partial install of just `kmod-wireguard`/`wireguard-tools`
  "succeeded" per opkg while leaving the module unprobeable), then
  `/etc/init.d/network restart` (a full daemon restart, not
  `reload`/`ifup`) is required once so netifd re-scans
  `/lib/netifd/proto/*.sh` and actually recognizes `proto=wireguard` — both
  gotchas confirmed live and documented in `docker/facts.md` Section 14.
  Then creates the baseline `network.wg0` interface (`proto=wireguard`,
  `private_key` from `/etc/wireguard-privkey` — generated once via
  `wg genkey` and reused on every re-run so the derived public key stays
  stable across idempotent re-provisioning — `listen_port=51820`,
  `addresses=10.9.0.1/24`). Idempotent AND self-healing, same two-layer
  discipline as `10-provision-vlans-api.sh`, run entirely inside one remote
  SSH session (not split across local round-trips): (1) uci-completeness —
  every expected field is read back via `uci get` against uci's own
  uncommitted staged view (no commit needed to check it) before
  `uci commit` ever runs, so commit genuinely only happens after
  verification passes, not before — one revert+retry on an incomplete
  section, then a loud failure with a revert, same as 08/10; (2) kernel-
  liveness — after `ifup wg0`, `ubus call network.interface.wg0 status`,
  `ip link show wg0`, and `wg show wg0` are independently checked for a
  real up interface, the `wireguard` proto, and the expected listening
  port, since a uci section can read back correct with no live interface
  behind it if `ifup` raced; not up is handled with one
  `ifdown`+`ip link delete`+`ifup` retry, then a loud failure, never left
  silently broken. The top-level idempotency check (skip package
  install/config entirely) is kernel-level first — a real `wg0` link up
  and `wg show wg0` succeeding — since a working interface, not just uci
  state, is what's actually being guaranteed. Confirmed idempotent live by
  tearing down `network.wg0` (uci delete + `ip link delete wg0`, packages
  left installed) and running the script twice in a row: the first run
  recreates and verifies everything from scratch on its first attempt (no
  retry needed), the second run skips package install and uci config
  creation entirely and still independently re-verifies kernel liveness —
  and the derived public key was confirmed identical across both runs,
  proving `/etc/wireguard-privkey` reuse works. Also `scp -O`'s (and
  curl-verifies) `docker/provision/www/api/wireguard` onto the VM's
  `/www/cgi-bin/api/wireguard`. Same dedicated-step rationale as
  08-10's own endpoint deploys. **As of Wave 6**, also `scp -O`'s (and
  chmods, and curl-verifies GET returns a JSON array)
  `docker/provision/www/api/wireguard-clients` onto the VM's
  `/www/cgi-bin/api/wireguard-clients`, for the VPN Server screen's
  "Client devices" list — folded into this same step rather than a new
  numbered script, since it extends the same `wg0` server this step
  already brings up, the same "one feature, one step" reasoning step 13
  applied to the devpause sweep + endpoint pair.
- `docker/provision/www/api/wireguard` — the tracked source of truth for
  the `/api/wireguard` endpoint: `GET` returns
  `{"running": <bool>, "port": <int>, "publicKey": "<string>", "subnet":
  "<string>"}` — `running` from `ubus call network.interface.wg0 status`
  (real kernel-liveness signal, same idea as `/api/vlans`'s `ip link show`
  check), `port`/`publicKey` always read live from `wg show wg0` (never
  from uci, which only ever stores the *private* key) with a fallback to
  the provisioned port (51820) and an empty publicKey when wg0 doesn't
  exist (e.g. mid-toggle-off), and `subnet` a hardcoded `10.9.0.0/24` — the
  one baseline value `11-provision-wireguard-api.sh` always provisions,
  not yet user-editable through this screen. `POST` reads a JSON body
  `{"enabled": <bool>}` and writes `network.wg0.disabled` (`0` for
  enabled, `1` for disabled), using the same hand-rolled
  `json_parse_flat_object` + literal `"true"`/`"false"` string validation
  and write-then-readback-verify-then-commit-or-revert discipline as
  `wifi`/`adblock`'s POST handlers. Both toggle directions confirmed live
  against this running VM: `enabled:false` runs `ifdown wg0` and makes
  `ip link show wg0` genuinely report "can't find device"; `enabled:true`
  runs `ifup wg0` and brings the real interface back with the same
  public key as before (private key persists in
  `/etc/wireguard-privkey` regardless of the toggle).
- `docker/provision/www/api/wireguard-clients` (Wave 6) — the tracked
  source of truth for the `/api/wireguard-clients` endpoint, extending the
  real `wg0` server `docker/provision/11-provision-wireguard-api.sh`
  already provisions with real per-client peer management for the VPN
  Server screen's "Client devices" list. `GET` returns
  `[{"id","name","publicKey","enabled","added"}, ...]`, one entry per real
  `wireguard_wg0` uci peer section. `POST` is dispatched by shape: a body
  with `name` creates a new client — generates a real keypair (`wg genkey`
  / `wg pubkey`), assigns the next unused `/32` in `10.9.0.2`-`10.9.0.254`
  (scanning existing peers' `allowed_ips`), `uci add`s a
  `wireguard_wg0` peer section, immediately `uci rename`s it to a stable
  `wgc_<time>_<6 hex>` id (same firewall-rules/device-pause/vlans stable-id
  precedent), and returns the client's WireGuard config text — **the
  private key is returned exactly once in this response and is never
  written to uci, logged, or retrievable again** (matches real-world
  WireGuard practice: the server only ever needs each peer's *public* key).
  A body with `id`+`enabled` instead toggles that peer's `disabled` uci
  option and runs `ifdown wg0; ifup wg0`, confirmed live to genuinely
  add/remove the peer from `wg show wg0`'s own output in both directions.
  Same write-then-readback-verify-then-commit-or-revert discipline, and the
  same canonical `json_escape()`, as every other write endpoint in this
  directory. No `DELETE` — same read-mostly-list choice `/api/vlans` made;
  a client created here can currently only be removed by hand over SSH.
  **Security note — a real command-injection vulnerability was found and
  fixed here during code review (commit `cfbb97d`):** the toggle path's
  client-supplied `id` is concatenated directly into `uci get`/`uci set`
  command strings (`shell_quote()` only escapes option *values*, not the
  section-id position in the command itself), and the first version of
  this endpoint accepted any non-empty string `id` with no further check —
  a genuine shell-injection hole (a crafted `id` like `` `touch
  /tmp/pwned` `` would have executed on the VM). Fixed by rejecting any
  `id` containing a character outside `[A-Za-z0-9_]` (`id:find("[^%w_]")`)
  *before* the id ever touches a uci command — mirroring the same
  `[%w_]+`-only precedent `firewall-rules`' `DELETE` handler already
  established for its own client-supplied section id, the only other place
  in this codebase that accepts one. `qos-priority` (below) was built with
  this lesson already in hand, and never accepts a client-supplied section
  id at all, deriving its own ids internally from a strictly-validated MAC
  instead.
- `docker/provision/12-provision-ssh-key-api.sh` — copies (and chmods, and
  curl-verifies) `docker/provision/www/api/ssh-key` onto the VM's
  `/www/cgi-bin/api/ssh-key`. Unlike `08`-`11`, this step provisions no
  baseline VM state at all beyond the endpoint file itself — dropbear
  already runs on every fresh OpenWrt boot with real host keys already
  present, so there's nothing to create first, matching `06`/`07`'s
  "stateless endpoint" shape rather than `08`-`11`'s "create baseline
  config/packages first" shape. Its verify step deliberately checks that a
  `GET` is rejected with a real `405` (this endpoint is POST-only) rather
  than issuing an actual `POST`, so simply (re-)running this provisioning
  script never itself rotates the VM's real SSH host keys as a side effect
  — a real rotation only happens when something (a person, or a later
  frontend wiring task) deliberately POSTs to the deployed endpoint.
- `docker/provision/www/api/ssh-key` — the tracked source of truth for the
  `/api/ssh-key` endpoint: `POST` (no request body read) deletes both
  `/etc/dropbear/dropbear_rsa_host_key` and
  `/etc/dropbear/dropbear_ed25519_host_key`, then runs
  `/etc/init.d/dropbear restart` — standard OpenWrt/dropbear behavior is to
  auto-regenerate any missing host key file on start, with no
  `dropbearkey`-invocation step needed in this handler at all. After a
  brief defensive `sleep 1` (to give dropbear's restart time to finish
  writing the new key file before it's read back, removing any race under
  uhttpd's CGI process model — not needed in the interactive testing this
  was confirmed against, but harmless here), the endpoint reads the new RSA
  key's fingerprint back via `dropbearkey -y -f
  /etc/dropbear/dropbear_rsa_host_key | grep -i Fingerprint` and returns
  `{"ok":true,"fingerprint":"SHA256:..."}`; if the fingerprint can't be
  read back for any reason, it returns `Status: 500` with
  `{"ok":false,"error":"..."}` rather than a false success. Only the RSA
  key's fingerprint is surfaced (matching what a real SSH client shows on
  first connect) — the ed25519 key is rotated identically alongside it, but
  the mockup's "Rotate now" button has no per-key-type UI to show a second
  fingerprint for. Confirmed live end-to-end against this running VM
  (`docker/facts.md` Section 14, and re-confirmed independently of the
  endpoint's own claim during this task): the real RSA fingerprint read
  directly over SSH before vs. after a `POST` to this endpoint genuinely
  differs and matches the response's `fingerprint` field exactly, and a
  second `POST` changes it again to a third distinct value — real proof of
  a rotation on every call, not a toggle between two fixed values. Any
  method other than `POST` gets `Status: 405`. This is safe specifically
  for this project's own SSH-based verification workflow because every SSH
  connection this project makes always passes `-o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null` — there's no persisted `known_hosts`
  entry anywhere for a rotated key to conflict with; a real deployment
  using normal host-key pinning would need to separately warn the operator
  their client will show a "host key changed" prompt after calling this
  (out of scope to simulate here — the screen's own copy already says
  "invalidates the old one immediately", which is accurate). Uses the same
  canonical table-based `json_escape()` as every other endpoint in this
  directory.
- `docker/provision/13-provision-devpause-api.sh` — does two things, in
  order. First (unlike 04-07/12's "stateless endpoint" shape and 08-11's
  "create baseline uci config" shape), it provisions a standalone cron job,
  not a `/cgi-bin/api/*` HTTP endpoint.
  `scp -O`'s `docker/provision/lib/devpause-sweep.sh` onto the VM as
  `/usr/bin/devpause-sweep.sh` and chmods it executable, then seeds
  `/etc/crontabs/root` with `* * * * * /usr/bin/devpause-sweep.sh`
  (idempotent — `grep -qF` before appending, confirmed live by running the
  script twice in a row and diffing `/etc/crontabs/root`: one line both
  times), then `/etc/init.d/cron enable && /etc/init.d/cron start`.
  Critically, it does NOT trust that start's own exit code as proof cron is
  actually running: `docker/facts.md` Section 13 confirms live, by reading
  `/etc/init.d/cron` directly, that `start_service()` does
  `[ -z "$(ls /etc/crontabs/)" ] && return 1` — on a fresh VM with an empty
  `/etc/crontabs/`, `/etc/init.d/cron start` silently no-ops (crond never
  actually starts) while still reporting overall success. Seeding the
  crontab file *before* calling `start` (this script's own step order)
  avoids that trap, but the script verifies anyway with `pgrep crond`
  rather than relying on the ordering alone; if crond isn't found running,
  it retries once with `/etc/init.d/cron restart` and re-checks, failing
  loudly only if still not running after that. Confirmed idempotent live by
  running the script twice in a row (second run skips nothing but leaves
  the crontab at exactly one matching line and crond still running).
  Deliberately kept under `docker/provision/lib/`, NOT
  `docker/provision/www/lib/` (a code-review finding on the first version
  of this task): `02-copy-www.sh` generically copies everything under
  `docker/provision/www/` onto the VM's web-servable `/www/cgi-bin/`, so a
  `www/`-nested source would make a normal re-run of step 2 also deposit an
  unrequested, non-executable second copy at
  `/www/cgi-bin/lib/devpause-sweep.sh` for no reason — confirmed live after
  the fix that re-running `02-copy-www.sh` creates no `/www/cgi-bin/lib/`
  path at all. Second, once the sweep is deployed and crond confirmed
  running, this script copies (and chmods, and curl-verifies)
  `docker/provision/www/api/device-pause` onto the VM's
  `/www/cgi-bin/api/device-pause` — same dedicated-step rationale as
  `04-provision-devices-api.sh`, folded into this same numbered step rather
  than a separate `14-...` script since the sweep and the endpoint it
  services are one feature. The verify step here is a real, safe `GET`
  (unlike `ssh-key`'s deliberately-inert 405-only check, since a `GET` here
  never mutates anything): confirms the response for a MAC with no active
  pause reads exactly `{"paused":false,"remainingSeconds":0}`.
- `docker/provision/www/api/device-pause` — the tracked source of truth for
  the `/api/device-pause` endpoint: `GET
  /cgi-bin/api/device-pause?mac=<mac>` returns `{"paused":
  <bool>,"remainingSeconds": <int>}` by looking up a `devpause-<mac>` uci
  `firewall` rule section and comparing its `paused_until` (epoch seconds)
  against `os.time()`. `POST /cgi-bin/api/device-pause` (body `{"mac":
  "<mac>", "minutes": <int, 1-1440>}`) creates (or REPLACES, so a second
  POST for the same MAC extends/shortens the pause rather than
  accumulating duplicate rules) a real `rule` section with `src='lan'`,
  `src_mac=<mac>`, `dest='wan'`, `target='REJECT'`, `proto='all'`, and the
  custom `paused_until` option the sweep script reads — `dest='wan'` is
  required (not `src='lan'` alone) to land the rule in the `forward_lan`
  chain as a real reject of the device's outbound traffic, rather than only
  `input_lan` (traffic addressed to the router itself), confirmed live in
  `docker/facts.md` Section 14. Same stable-id-rename-before-any-further-
  read/write discipline as `firewall-rules`/`vlans` (a positionally-
  addressed `@rule[-1]`/`@rule[N]` section is not safe to keep addressing
  across separate `uci` process invocations) — plus a fix, caught by this
  endpoint's own pre-release verification, that a uci section IDENTIFIER
  can't contain the hyphens `devpause-<mac>` (the rule's `.name` OPTION
  value, which `devpause-sweep.sh`'s scan depends on matching literally)
  uses, so the section is renamed to a separate underscored
  `devpause_<mac>` id instead. Same write-then-readback-verify-then-commit-
  or-revert discipline, MAC/minutes input validation (strict 6-octet
  colon-hex; integer 1-1440), and canonical `json_escape()` as every other
  write endpoint in this directory. This endpoint only ever creates or
  replaces a pause rule — it never deletes an expired one itself (no
  request happens to land at exactly the right moment); that's
  `devpause-sweep.sh`'s job, described next.
- `docker/provision/lib/devpause-sweep.sh` — the tracked source of truth
  for `/usr/bin/devpause-sweep.sh`, run every minute by the cron entry
  `13-provision-devpause-api.sh` seeds. Finds uci `firewall` rule sections
  this project created for a per-device pause (`name` starting with
  `devpause-`, extracted with POSIX `sed`/`grep` only — busybox ash,
  matching every other script in this directory's tooling assumptions, not
  bash/gawk), reads each one's custom `paused_until` (epoch-seconds) uci
  option — uci tolerates arbitrary option names on a rule section, and fw4
  silently ignores ones it doesn't recognize, confirmed live (a `[!]
  ... specifies unknown option 'paused_until'` warning on `fw4 reload`, not
  a failure) — and `uci -q delete`s any section whose `paused_until` has
  already passed, `uci commit firewall`ing and `fw4 reload`ing once at the
  end only if at least one section was actually removed (both failures are
  now explicitly `logger`'d rather than silently swallowed — a code-review
  fix). Every deletion is also `logger -t devpause-sweep`'d for
  auditability. This script only ever DELETES expired pause rules; real
  pause CREATION is `/cgi-bin/api/device-pause`'s job (deployed by this same
  `13-provision-devpause-api.sh`, described above).
  **Multi-expiry-per-tick fix (code review):** this VM's `firewall` rules
  are anonymous sections addressed positionally
  (`firewall.@rule[N]`, confirmed live in `docker/facts.md` Section 13/14 —
  the same shape device-pause creation uses). The first version of this
  script collected every expired section's id in ONE upfront `uci show`
  snapshot, then deleted them in that same order — but deleting a
  lower-indexed `@rule[N]` immediately renumbers every higher-indexed
  section by one in the live staged uci state, so every id after the first
  delete in a batch pass could address whatever section shifted into that
  vacated slot instead of the rule actually intended, whenever >=2 pauses
  expired in the same minute. Fixed by having `find_one_expired_id()`
  re-run a completely fresh `uci show firewall` scan on every single call,
  with the main loop calling it again immediately after each delete and
  repeating until a fresh scan finds nothing left to expire — never acting
  on a stale batch of ids.
  Confirmed live end-to-end, including the multi-expiry scenario the fix
  specifically targets: a single hand-crafted `devpause-aabbccddeeff` rule
  with `paused_until` 5 seconds in the past was genuinely removed by the
  next real cron tick (`uci show firewall | grep devpause-aabbccddeeff`
  went from a match to no match, `exit=1`, within 65 seconds, no manual
  intervention), while a sibling `devpause-112233445566` rule with
  `paused_until` 300 seconds in the future survived that same sweep cycle
  untouched. Separately, after the ordering fix, the exact scenario the fix
  targets was reproduced and proven live: THREE simultaneously expired
  rules (`devpause-aaaaaaaaaaaa`, `devpause-bbbbbbbbbbbb`,
  `devpause-cccccccccccc`, `paused_until` a few seconds in the past) plus a
  fourth, non-expired `devpause-dddddddddddd` (`paused_until` 300 seconds
  in the future) were created back-to-back at positions `@rule[9]`-`[12]`
  and left for one real cron tick. Afterward, `uci show firewall | grep
  devpause-` showed exactly one line left —
  `firewall.@rule[9].name='devpause-dddddddddddd'` — proving all three
  expired rules were removed in that single pass, not just the first
  (which is what the pre-fix batched-snapshot ordering bug would have
  left behind), while the still-future rule survived even though repeated
  deletions shifted it down to reuse the very `@rule[9]` address three
  now-removed rules had each occupied in turn — real proof `paused_until`
  is re-read fresh at each address rather than acted on from a stale
  snapshot. `logread` corroborates from the same cron invocation (pid
  11962): three separate `devpause-sweep: removing expired pause:
  firewall.@rule[9] (paused_until=1788262016, now=1788262080)` lines, all
  timestamped `Tue Sep 1 11:28:00 2026` — one per deletion, each correctly
  reporting the rule occupying `@rule[9]` at that moment, confirming the
  fresh-rescan loop cleared every same-tick expiry in one pass rather than
  one per minute.
- `docker/provision/14-provision-qos-priority-api.sh` — deploy-and-verify
  only, matching `12-provision-ssh-key-api.sh`'s and
  `13-provision-devpause-api.sh`'s own endpoint-deploy shape: no baseline
  uci config to create first (unlike steps 8-11), since a `uci firewall`
  rule section already exists as a concept on a fresh VM. `scp -O`'s
  `docker/provision/www/api/qos-priority` onto
  `/www/cgi-bin/api/qos-priority`, chmods it executable, then verifies with
  a real `curl -sf` `GET` — checked to be a genuine JSON array (`[...]`)
  rather than string-matching one specific empty/non-empty body, since this
  step can be re-run against a VM that already has priority rules on it
  from prior use, unlike `device-pause`'s verify (which checks an exact
  not-paused body for a MAC that has no rule of its own yet).
- `docker/provision/www/api/qos-priority` — the tracked source of truth for
  the `/api/qos-priority` endpoint: `GET /cgi-bin/api/qos-priority` returns
  `[{"mac":"AA:BB:CC:DD:EE:FF"}, ...]`, one entry per uci `firewall` rule
  section whose `.name` starts with `qospriority-`, parsed the same
  `list_rule_sections()`-style approach `device-pause` uses (generalized
  here as `list_priority_sections()`/`find_priority_rule()`). Only `mac` is
  returned — no display name is stored server-side; the frontend
  cross-references a fresh `/api/devices` fetch by MAC at render time,
  falling back to the raw MAC for a device that isn't currently
  DHCP-leased, an intentional, honest behavior (a prioritized device isn't
  guaranteed to always be online), not a bug. `POST /cgi-bin/api/qos-priority`
  (body `{"mac": "<mac>"}`) creates a real `rule` section with `src='lan'`,
  `src_mac=<mac>`, `dest='wan'`, `target='MARK'`, `set_mark='0x2a'` —
  confirmed live to land in the real `mangle_forward` nft chain (not just
  `input_lan`), genuinely marking the device's own forwarded traffic, the
  same `src=lan`/`dest=wan` distinction `device-pause`'s own investigation
  established for `REJECT` rules (docker/facts.md Section 14) applying
  identically here for `MARK` (confirmed live again for this endpoint,
  docker/facts.md Section 15). `0x2a` is a fixed, arbitrary mark value —
  there's no second priority tier or tc/SQM queueing discipline consuming
  it yet in this wave, so its exact numeric value has no behavioral meaning
  beyond proving the marking mechanism itself is real. Same stable-id-rename
  discipline as `device-pause` (`qospriority-<mac-no-colons>` as the rule's
  `.name` value, `qospriority_<mac-no-colons>` — underscored, since uci
  section identifiers can't contain hyphens — as the actual rename target),
  and the same write-then-readback-verify-then-commit-or-revert discipline,
  strict MAC validation, and canonical `json_escape()` as every other write
  endpoint in this directory. A second `POST` for a MAC that already has a
  rule is idempotent: `find_priority_rule()` finds the existing section by
  its `.name` and returns `{"ok":true,"mac":"..."}` immediately without any
  further uci write — confirmed live (`uci show firewall | grep -c
  qospriority_112233445566` stays at exactly 7 lines, i.e. one section, not
  two, across repeated POSTs for the same MAC). No `DELETE` — the mockup has
  no remove affordance for these rows, the same choice `/api/vlans` made for
  its own read-mostly list; a rule created here can currently only be
  removed by hand over SSH, a known, documented limitation rather than a
  silently-missing feature. **Security note (code-review-driven extra
  scrutiny):** unlike `wireguard-clients`' toggle path, which accepted a
  client-supplied section id and — before a real command-injection bug was
  found and fixed in commit `cfbb97d` — concatenated it unquoted into shell
  commands with only a `type=="string"` check, this endpoint never accepts
  a client-supplied section id at all; both `qospriority-<mac>` and
  `qospriority_<mac>` are derived internally from `mac`, which is strictly
  regex-validated (`is_valid_mac`, the same 6-octet colon-hex pattern
  `device-pause` uses) before it touches any uci command, and every value
  interpolated into a shell command also goes through `shell_quote()` as
  defense in depth. Confirmed live: `POST` bodies with MAC-shaped-looking
  payloads containing `;`, backticks, and `$()` (e.g. `"11:22:33:44:55:66;
  touch /tmp/pwned_qos_test #"`, `` "`touch /tmp/pwned_qos_test2`" ``,
  `"$(touch /tmp/pwned_qos_test3)"`) are all rejected with a clean `400` by
  `is_valid_mac`'s regex before any uci call runs, and none of the target
  files were created on the VM.
- `docker/provision/15-provision-bedtime-api.sh` — deploys only the
  baseline-state (sweep) half of the Bedtime feature, matching
  `13-provision-devpause-api.sh`'s own sweep-half shape: `scp -O`'s
  `docker/provision/lib/bedtime-sweep.sh` onto the VM as
  `/usr/bin/bedtime-sweep.sh` and chmods it executable, then seeds
  `/etc/crontabs/root` with `*/5 * * * * /usr/bin/bedtime-sweep.sh`
  (idempotent, `grep -qF`-guarded), enables and starts cron, and verifies
  `pgrep crond` reports a real PID rather than trusting the init script's
  own exit code (same `/etc/init.d/cron start` empty-crontab-directory trap
  as step 13, documented in `docker/facts.md` Section 13). Unlike step 13,
  this script does not also deploy an endpoint yet — real device-bedtime
  rule CREATION (`/cgi-bin/api/device-bedtime`) is a separate task in this
  same plan, not yet built when this script was written; the sweep is
  provably safe to run standalone before that endpoint exists (nothing for
  it to reconcile until something starts creating `bedtime-<mac>` rules).
- `docker/provision/lib/bedtime-sweep.sh` — the tracked source of truth for
  `/usr/bin/bedtime-sweep.sh`, run every 5 minutes by the cron entry
  `15-provision-bedtime-api.sh` seeds. Finds every uci `firewall` rule
  section whose `.name` starts with `bedtime-` and sets that section's own
  `enabled` uci option to `1` if the current UTC hour is `>=21` or `<7`,
  else `0` — never creating or deleting a rule, only toggling whether fw4
  emits an already-existing one (`enabled='0'` + `fw4 reload` makes the
  rule genuinely absent from `nft list ruleset`; `enabled='1'` brings it
  back, confirmed live). This VM has no configured timezone at all
  (`docker/facts.md` Section 16: `date` shows UTC, `uci get
  system.@system[0].zonename` returns "Entry not found"), so a fixed UTC
  window is this feature's honest, disclosed approximation of "the
  family's bedtime hours" rather than a real per-family local schedule.
  Deliberately never wraps the zero-padded `date -u +%H` output in `$(( ))`
  arithmetic expansion — confirmed live before this script was written that
  doing so misparses a value like `"08"` as invalid octal on this VM's
  busybox ash, and that ash's usual `10#$HOUR` base-10-prefix workaround
  also fails here (`ash: arithmetic syntax error`); POSIX `test`/`[`'s
  `-ge`/`-lt` compare the zero-padded string correctly with no such
  reinterpretation. No top-level `set -e`, same reasoning as
  `devpause-sweep.sh`: one section's uci get/set failing shouldn't cancel
  the sweep for every other section that tick; `uci commit`/`fw4 reload`
  failures are explicitly logged via `logger -t bedtime-sweep` rather than
  silently swallowed. Confirmed live in both directions against a real
  `bedtime-aabbccddeeff` test rule: with the VM's real UTC hour
  out-of-window (17:00 UTC), the sweep flipped a pre-existing `enabled='1'`
  rule to `'0'` and the rule's `REJECT` entries genuinely disappeared from
  `nft list ruleset`; with the VM's clock temporarily set to 23:00 UTC (an
  in-window hour), the sweep flipped `enabled` from `'0'` back to `'1'` and
  the same `REJECT` entries reappeared in `nft list ruleset` — the VM's
  clock was restored to the real current time immediately afterward.

### Real connectivity test — what it actually means in this topology

The plan this endpoint was built from originally called for a literal
"run a listener on the internal target, curl the forwarded external port
from this repo's normal shell, confirm it connects" test. **That's not
possible here**, and not for a superficial reason — `docker/facts.md`
Section 10 has the full live investigation, summarized:

- This VM has no `network.wan` interface (`docker/facts.md` Section 3).
  A `config redirect` with `src='wan'` (the only sensible default for a
  real port-forward — see the endpoint's own header comment) generates a
  correct, real DNAT rule, confirmed live in `nft list ruleset` — but fw4
  places it in a `dstnat_wan` chain nothing ever jumps into, since there's
  no wan device to gate that jump on. **Zero packets can ever reach a
  `src='wan'` rule in this VM's topology**, confirmed by direct inspection,
  not assumed.
- A `src='lan'` rule *is* reachable (traffic via the real `br-lan` device
  does get routed into `dstnat_lan`), and a manually-added one was proven,
  live, to actually intercept and DNAT a real TCP SYN packet (the
  `nft` rule's own packet counter incremented in lockstep with real
  connection attempts, and removing the rule measurably changed the
  connection's failure mode from an instant refusal to a full 3-second
  timeout). What could **not** be proven is a *complete* end-to-end
  connection, because this topology has no third, genuinely distinct
  network identity to act as a separate "internal target" — every
  throwaway test container shares the exact same network namespace as the
  `openwrt` container itself, and a DHCP-leased address from this
  environment's `busybox` image is never actually applied to an interface
  (no `/usr/share/udhcpc/default.script` present) so nothing can bind or
  listen on one. The resulting client-is-also-the-target scenario hits the
  well-known "hairpin NAT" limitation (the reply routes back locally
  instead of back through the guest for un-DNAT) — a structural property
  of this test topology, not a defect in the redirect mechanism itself.

Given that, what this endpoint's shipped verification actually is: (1) a
POST creates a real `redirect` section with `src='wan'`, confirmed via
`uci show firewall` and via the exact matching rule appearing in `nft list
ruleset`'s `dstnat_wan` chain (correct proto/port/dest, not a fabricated
or hand-typed value) — real proof the whole `uci add`/`rename`/`set`/
`commit`/reload pipeline produces genuinely correct firewall config; and
(2) `docker/facts.md` Section 10 separately documents a hand-run,
`src='lan'` live-packet test (not part of this endpoint — it always uses
`src='wan'`) proving the underlying reload/enforcement mechanism itself is
real, so if this VM ever gains a real WAN interface, the same `src='wan'`
rules this endpoint already creates would behave identically with zero
further changes.

### Getting a real device onto the lease list

A freshly-provisioned VM's `/tmp/dhcp.leases` is empty — nothing has
asked the guest's dnsmasq for a lease yet — so `/api/devices` correctly
returns `[]` until something does. `docker exec` does **not** reach the
guest (see `docker/facts.md`'s intro) and there's no separate Docker
network the guest's LAN side sits on either; what does work is attaching
a second, throwaway container directly to the `openwrt` container's own
network namespace (where `docker/entrypoint.sh`'s tap0 device lives) and
running a DHCP client on tap0 from inside it:

```bash
docker run --rm --network container:openwrt --cap-add=NET_ADMIN busybox \
  sh -c "udhcpc -i tap0 -n -q -x hostname:sadd-test-client"
```

This performs a real DORA exchange against the guest's dnsmasq using
tap0's own real hardware MAC, confirmed live to produce a real lease
(`udhcpc: lease of 192.168.1.232 obtained from 192.168.1.1 ...`) and a
matching real line in `/tmp/dhcp.leases` — see `docker/facts.md` Section
1a for the exact confirmed line and more detail. After running this,
`curl http://localhost:8081/cgi-bin/api/devices` reflects that real
device.

## Known limitations for this dev/test environment

- No physical Wi-Fi radio — this is a router with one virtual wired NIC
  only. Any Wi-Fi-related config work is at the `uci`/config level, not an
  actually-broadcasting network.
- Single interface — `eth0` is bridged into `br-lan` only; there's no
  separate WAN interface wired up yet. If a later wave needs a real
  separate WAN link, that's additional tap/network setup, not something
  this environment already provides.
- State lives only in `boot-image/boot.img`, gitignored and untracked —
  don't treat this as a durable environment; `docker compose down` followed
  by deleting and re-fetching `boot.img` gets you back to a pristine state,
  which is exactly what Task 9's full verification pass exercises.
- No end-to-end WAN packet test for firewall port-forwarding — a `src='wan'`
  redirect rule genuinely lands in a real `fw4` nftables chain (`dstnat_wan`),
  but that chain is topologically unreachable in this VM's single-interface
  setup (confirmed by exhaustive `nft list ruleset` inspection). See "Real
  connectivity test" above for what was actually proven instead (a `src='lan'`
  rule intercepting real live traffic, proving the same underlying mechanism).
- **Network & VLANs has no real device-count** — `/api/vlans` deliberately
  excludes a per-VLAN device count (see `docker/provision/www/api/vlans`'s
  header comment): this VM's dnsmasq serves one shared lease pool off
  `lan`/`br-lan`, so a genuine per-VLAN count would need a real, separate
  DHCP service per interface, a materially bigger undertaking than this
  wave's narrow read-only scope. The frontend shows a static "—" placeholder
  in that column for every real row instead of fabricating a plausible
  number.
- **Ad Blocking's "This week" count is real but not a true rolling week** —
  `/api/adblock`'s `blockedThisWeek` counts real `logread` lines matching a
  blocked-domain signature, but `logread`'s buffer is a small fixed-size
  ring, nowhere near a full week's history; the count reflects whatever's
  currently in that buffer, not genuine 7-day persistence. Real numbers,
  not guaranteed complete-week coverage — documented as aspirational in
  `docker/provision/www/api/adblock` itself. Also worth noting: this VM's
  blocklist is a fixed 3-domain demo set (`doubleclick.net`,
  `adservice.google.com`, `tracker.example.com`) provisioned by
  `09-provision-adblock-api.sh`, not a real, maintained, updatable
  third-party blocklist feed — adding/removing domains from the live
  blocklist isn't exposed through the UI or API in this wave.
- **No authentication on `/cgi-bin/api/*`**, and `docker-compose.yml` binds
  port 8081 to all interfaces, not just `localhost` — anyone reachable on
  the local network can add/delete real firewall rules, flip the real guest
  Wi-Fi network on/off, flip real ad blocking on/off, flip the real
  WireGuard server on/off, pause/unpause a real device's internet access,
  create or toggle a real WireGuard client peer, or mark a real device's
  traffic for priority, with a plain `curl` (eight independent
  write-capable endpoints: `/api/firewall-rules`, `/api/wifi`,
  `/api/adblock`, `/api/wireguard`, `/api/ssh-key`, `/api/device-pause`,
  and, as of Wave 6, `/api/wireguard-clients` and `/api/qos-priority` —
  `/api/ssh-key` is a little different in kind from the rest: it doesn't
  mutate any persisted uci config the way they do, but a plain
  unauthenticated `POST` still immediately rotates this VM's real SSH host
  keys with no confirmation, undo, or operator warning, so it belongs in
  this list too).
  Acceptable only because this is an explicitly local, single-user dev/test
  tool — not something to carry into a later wave or real deployment as-is.
  The **read-only** endpoints (`/api/devices`, `/api/logs`, `/api/system-info`,
  as of Wave 4 `/api/vlans`, as of Wave 5 `/api/device-pause`'s own
  `GET` — which discloses whether a specific MAC is currently paused and,
  if so, for how much longer — and, as of Wave 6, `/api/wireguard-clients`'
  own `GET` (discloses every configured client's name/public key/enabled
  state) and `/api/qos-priority`'s own `GET` (discloses which MACs are
  currently marked for priority)) are equally unauthenticated — anyone on
  the local network can silently read real device/MAC/IP presence, real log
  lines, real hardware/uptime info, real VLAN topology, real per-device
  pause status, real WireGuard client identity/key data, and real
  priority-marking status with a plain `curl`. Disclosure rather than
  mutation, but the same "local, single-user dev tool only" caveat applies.
- **Per-device pause is a real firewall block, but not end-to-end
  WAN-testable** — `POST /api/device-pause` creates a genuine `uci`/`fw4`
  `rule` section (`src='lan'`, `src_mac=<device>`, `dest='wan'`,
  `target='REJECT'`) that would actually reject that device's outbound
  traffic on real hardware, but like every other WAN-dependent feature in
  this project (see the firewall port-forwarding limitation above), this VM
  has no real WAN interface to prove the full path against — the rule's
  correctness was confirmed the same way port-forwarding's was: real,
  correct config and a real chain placement, not a real dropped packet.
- **"Until tomorrow" is a client-side approximation, not a schedule** — the
  third Pause-internet chip sends `minutes-until-next-local-midnight`
  (`minutesUntilNextMidnight()` in `sadd-website.html`) as a plain minutes
  value like the other two chips; there's no per-family bedtime/schedule
  concept behind it, just "how many minutes are left in today," computed in
  the browser off the viewer's own clock.
- **SSH key rotation's safety is specific to this project's own SSH
  convention, not a general guarantee** — `/api/ssh-key`'s `POST` is safe to
  call repeatedly here only because every SSH connection this project makes
  always passes `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`
  (no persisted `known_hosts` entry anywhere to conflict with a rotated
  key). A real deployment using normal host-key pinning would see clients
  hit a "host key changed" warning after every rotation — this project
  doesn't simulate or warn about that client-side experience; only the
  screen's own "invalidates the old one immediately" copy hints at it.
- **The devpause cron sweep runs on a 60-second cadence, not instantly** —
  `docker/provision/lib/devpause-sweep.sh` is invoked once a minute by cron
  (the tightest interval OpenWrt's `crond` supports), so an expired pause is
  real but can take up to roughly 60 seconds after its `paused_until` time
  to actually be lifted, not the instant the countdown hits zero. Confirmed
  live down to this exact granularity (see `docker/provision/lib/devpause-sweep.sh`'s
  own file note above) — worth being explicit about rather than implying a
  precision the mechanism doesn't have.
- **A WireGuard client's private key is shown exactly once, never persisted
  server-side** — `POST /api/wireguard-clients` (create) returns the new
  client's full config text, private key included, in that one response
  only; the endpoint never writes the private key to uci, never logs it,
  and has no way to reconstruct or re-display it afterward. This is a real,
  standard WireGuard operational fact (the server only ever needs to know a
  peer's *public* key), not a bug — but it does mean that if the "New
  client config" panel is dismissed in the UI without saving its contents
  first, that config is genuinely gone; the only recovery is removing the
  client (by hand over SSH — see the next bullet) and adding it again,
  which issues a fresh keypair.
- **Priority devices and WireGuard clients both have no remove/delete
  affordance in the UI** — neither `/api/qos-priority` nor
  `/api/wireguard-clients` exposes a `DELETE`, matching the same
  read-mostly-list choice already made for `/api/vlans` in Wave 4: the
  mockup itself has no remove control for either row type. A rule or client
  created through either screen can currently only be removed by hand over
  SSH (`uci delete firewall.qospriority_<mac>` / `uci delete
  network.<wgc_id>`, then `uci commit` and the appropriate reload/`ifup`),
  a known, documented limitation rather than a silently-missing feature.
- **The QoS mark value (`0x2a`) has no consuming queueing discipline yet**
  — `/api/qos-priority`'s `POST` creates a real, kernel-verifiable
  `MARK`/`set_mark=0x2a` rule in the real `mangle_forward` nft chain (the
  marking mechanism itself is genuinely real, confirmed live against `nft
  list ruleset`), but nothing on this VM currently reads that mark to
  actually prioritize the marked traffic's latency or bandwidth — no `tc`
  qdisc, no SQM instance, nothing consumes `0x2a` for anything today. A
  device added to "Priority devices" is real, inspectable state, but has no
  behavioral effect on its own traffic yet. Wiring a real `tc`/SQM setup
  keyed on this mark is its own future wave (see the design spec's Wave 7
  "Bandwidth used today" entry, which needs the same missing piece), not
  something this wave's narrow scope (proving the marking mechanism itself
  is real) included.
- The global search feature (built earlier this session, unrelated to this
  work) can't highlight search results on the Devices, Firewall & Ports
  (port-forwarding rules only), and Diagnostics & Logs screens when the
  router is reachable and responding quickly — real data overwrites the
  static demo text those search-index entries point at before the
  highlight fires. Confirmed during Wave 2's verification pass to extend
  to all of Diagnostics & Logs' "Recent activity" search entries (its
  whole log list is real-data-backed, unlike Firewall & Ports where only
  the port-forwarding rows are affected). The About screen is unaffected —
  none of its indexed search entries (App version's label, "Built on
  OpenWrt", the CVE table, pricing promise) point at the one span that
  actually goes dynamic, since only the factual version *value* is
  replaced, not any indexed label text. Settings and Guest Wi-Fi (Wave 3)
  are unaffected for the same reason, confirmed by checking the actual
  `searchIndex` entries rather than assuming: every entry pointing at those
  two screens ("Wi-Fi name & password", "Guest Wi-Fi", "Smith Guest")
  targets static label/marketing text, never the two now-dynamic spans
  (`#settingsWifiName`/`#settingsGuestStatus`) or the toggle switch/its
  description (`#guestWifiSwitch`/`#guestWifiDesc`) — search highlighting on
  both screens works correctly whether the router is reachable or not.
  Navigation still lands on the correct screen every time on every affected
  screen; only the cosmetic pulse is silently skipped, exactly matching the
  search feature's own designed "fail silently on content drift" behavior.
  **Wave 4 update:** Ad Blocking is unaffected for the same reason as
  Settings/Guest Wi-Fi — none of its three `searchIndex` entries ("Ad
  Blocking", "doubleclick.net", "adservice.google.com") target the two
  spans that actually go dynamic (`#adblockStat`/`#adblockSwitch`); all
  three point at content the plan deliberately kept static (the screen
  label, and the mini-log's top-3-domains list). Network & VLANs is
  different from every other affected-or-unaffected screen so far: its five
  `searchIndex` entries ("Main Network", "Kids", "IoT / Smart Home",
  "Guests", "Quarantine") DO target the one span that goes dynamic — the
  VLAN list itself, fully replaced by `renderVlansScreen` — yet highlighting
  still works, confirmed live (headless Chrome via `puppeteer-core` against
  the real VM): because the real `/cgi-bin/api/vlans` response's `name`
  field is a hardcoded human-label map matching these exact demo strings
  (`docker/provision/www/api/vlans`'s own header comment), the freshly
  re-rendered `.adv-row` elements still contain the matchText the index was
  authored against, so `highlightAndScroll` finds it. This is a coincidence
  of the two being authored to agree, not a design guarantee — a future
  edit to either the blocklist domains or the VLAN name map would silently
  reintroduce the Devices/Firewall-rules/Logs-style miss for whichever
  entries drift out of sync. Full detail in the design spec's Error
  Handling section.
