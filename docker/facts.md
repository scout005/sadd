# Facts confirmed on the running OpenWrt VM (Task 2)

Captured 2026-08-31 by SSHing into the VM brought up per `docker/README.md`
(`bash docker/fetch-boot-image.sh` — no-op, image already present — then
`docker compose up -d --build` from `docker/`). The container reported
`healthy` (via the Task 1 `HEALTHCHECK`) about 9-12 seconds after
`docker compose up -d --build` returned. SSH connected cleanly on the
first attempt with no root-password prompt (the VM had apparently already
had a throwaway root password set from a prior session; if a truly fresh
image prompts you to set one, `test1234` is a fine throwaway):

```
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost -p 2223
```

`docker exec` into the `openwrt` container does **not** reach the guest —
confirmed by inspection of `docker/entrypoint.sh`: the container just runs
QEMU + socat: the guest is a separate VM reachable only over the
network (SSH/HTTP), not a process inside the container's own namespace.
SSH is the only way in, as the task brief expected.

Version: OpenWrt 23.05.5 r24106-10cc5fcd00, kernel 5.15.167, target x86/64
(from `ubus call system board`, full output below).

---

## 1. DHCP lease file

**Confirmed path:** `/tmp/dhcp.leases` — confirmed two ways:
- `uci show dhcp` shows `dhcp.@dnsmasq[0].leasefile='/tmp/dhcp.leases'` explicitly.
- The file exists at that exact path (`ls -la /tmp/dhcp.leases` → `-rw-r--r-- 1 root root 0 ... /tmp/dhcp.leases`).

**Contents on this fresh VM:** empty (0 bytes). No DHCP client has associated
yet (the only device docker/entrypoint.sh's tap0 setup gives the guest a
neighbor is `192.168.1.2` — the container's own tap-side socat relay
address — which is a static IP, not something that went through DHCP, so
it does not appear in the lease file; it does appear in `/proc/net/arp`
though — **see Section 9 below ("Misc supporting facts") for the full
liveness-heuristic trap this creates: a naive ARP-based "is this device
online" check will find 192.168.1.2 and must not report it as a real
device.** Task 2 does not attach a test DHCP client — that's explicitly
deferred to Task 5.

**Line format:** could not be confirmed from a live example on this VM
(file is empty), but is confirmed via the running dnsmasq's own version
banner and OpenWrt's documented behavior:

```
dnsmasq --version → "Dnsmasq version 2.90 ... Compile time options: ... DHCP ..."
```

This build has DHCP compiled in (the `--version` banner shows plain
`DHCP`, not `no-DHCP`) and is running as the VM's DHCP server (confirmed
via `ps`: `/usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf.cfg01411c...` is
live). dnsmasq's traditional lease-file format for IPv4 leases (one line
per lease, space-separated) is:

```
<expiry-epoch-seconds> <mac-address> <ip-address> <hostname-or-*> <client-id-or-*>
```

e.g. `1735689600 aa:bb:cc:dd:ee:ff 192.168.1.105 my-laptop 01:aa:bb:cc:dd:ee:ff`

Since the file is currently empty this format is stated from dnsmasq's own
documented behavior (matching the version actually running, 2.90) rather
than verified against a real populated line — **Task 5 must re-confirm
this against an actual populated line** before relying on fixed
whitespace-split parsing (a missing hostname is written as a literal `*`
in that field, not an empty string — worth defensive parsing).

### 1a. Addendum (Task 5) — real lease line format, confirmed live

Task 5 attached a real DHCP client and confirmed the format assumed above.
Mechanism: `docker exec` cannot reach the guest (see the top of this doc),
and there's no separate Docker network the guest's LAN side is bridged
onto either — `docker/entrypoint.sh` gives the `openwrt` container itself
a tap0 device (192.168.1.2/24) directly L2-adjacent to the guest's
br-lan, and that tap0 only exists inside the `openwrt` container's own
network namespace. The mechanism that worked: join that exact namespace
with a second, throwaway container and run a DHCP client on tap0 from
inside it:

```bash
docker run --rm --network container:openwrt --cap-add=NET_ADMIN busybox \
  sh -c "udhcpc -i tap0 -n -q -x hostname:sadd-test-client"
```

`--network container:openwrt` attaches the new container to the running
`openwrt` container's network namespace (not a shared bridge network —
there isn't one), which is what makes tap0 visible to it at all; `udhcpc`
(busybox's DHCP client, `-n` exit-on-failure, `-q` quit after obtaining
the lease) then performs a real DORA exchange over tap0 against the
guest's dnsmasq, using tap0's own real hardware MAC (a real, distinct MAC
from the container's static-relay address). This produced a real,
successful lease:

```
udhcpc: lease of 192.168.1.232 obtained from 192.168.1.1, lease time 43200
```

Confirmed afterward on the VM, `cat /tmp/dhcp.leases` returned exactly one
real line:

```
1788197175 a6:fe:23:e1:c6:ba 192.168.1.232 sadd-test-client 01:a6:fe:23:e1:c6:ba
```

This **exactly matches** the format assumed in Section 1 above:
`<expiry-epoch> <mac> <ip> <hostname-or-*> <client-id-or-*>` — confirmed,
not just assumed, as of this addendum. `/proc/net/arp` on the same VM
also picked up `192.168.1.232` (same MAC, non-zero flags) alongside the
pre-existing `192.168.1.2` tap-relay entry, confirming the ARP-based
liveness heuristic works against a real lease and that the two addresses
are distinguishable (the tap-relay address has no lease-file line at all,
so an endpoint that only iterates lease-file entries never reports it).

## 2. `ubus call dhcp ...` as an alternative to the lease file

The `dhcp` ubus object **does exist**:

```
$ ubus -v list dhcp
'dhcp' @6093621d
        "ipv4leases":{}
        "ipv6leases":{}
        "add_lease":{"ip":"String","mac":"String","duid":"String","hostid":"String","leasetime":"String","name":"String"}
```

`ubus call dhcp ipv4leases` (no args) on this fresh VM returns:

```json
{
	"device": {

	}
}
```

i.e. an object keyed by network device, empty because no leases exist yet.
This originally looked like it might be a real, structured alternative to
parsing the lease file, pending verification against a real lease
(Task 5's own recommendation below, at the time unconfirmed).

### 2a. Addendum (post-Task-5 fix work) — confirmed live: `ubus call dhcp ipv4leases` never reflects dnsmasq's leases on this VM

The prior recommendation above was never actually followed up before the
`/api/devices` endpoint was built — it went straight to lease-file
parsing. This addendum closes that gap: a real client was attached
(`docker run --rm --network container:openwrt --cap-add=NET_ADMIN busybox
sh -c "udhcpc -i tap0 -n -q -x hostname:ubus-check-client"`), producing a
real, confirmed line in `/tmp/dhcp.leases`:

```
1788198109 2e:c3:47:98:c7:12 192.168.1.211 ubus-check-client 01:2e:c3:47:98:c7:12
```

With that real lease genuinely present, `ubus call dhcp ipv4leases` was
called again — **still returns the empty shape**, `{"device": {}}`,
exactly as on the lease-free fresh VM. It never reflects dnsmasq's leases,
confirmed live rather than assumed.

**Root cause, confirmed:** `ps` shows both `odhcpd` and `dnsmasq` running.
Only `odhcpd` registers a ubus object relevant here — `ubus list` shows
`dnsmasq` and `dnsmasq.dns` objects, but `ubus -v list dnsmasq` exposes
only a `metrics` method (no lease-query method at all), and
`dnsmasq.dns` exposes nothing. The `dhcp` object (with `ipv4leases`/
`ipv6leases`) is odhcpd's. `uci show dhcp` explains why it's always
empty for IPv4: `dhcp.odhcpd.maindhcp='0'` — odhcpd is explicitly
configured **not** to be the main DHCP daemon on this VM. The `dhcp.lan`
section confirms the actual split: `dhcpv4='server'` is handled by
dnsmasq (which owns `/tmp/dhcp.leases` and writes it directly, with no
ubus method to query it), while `dhcpv6='server'` and `ra='server'` are
odhcpd's job, using odhcpd's own separate lease file
(`dhcp.odhcpd.leasefile='/tmp/hosts/odhcpd'`, confirmed not to exist yet
on this VM since no IPv6/RA client has ever gotten a lease from it).
`ubus call dhcp ipv4leases` therefore asks odhcpd — a daemon that, on
this VM's config, never tracks IPv4 leases at all — so it always reports
none, regardless of how many real DHCPv4 leases dnsmasq is actually
serving.

**Confirmed conclusion:** the prior review's hypothesis (a separate
daemon, odhcpd, serves the `dhcp` ubus object and doesn't reflect
dnsmasq's leases) was correct, and is now confirmed by direct observation
rather than assumed. There is no reliable ubus path to real-time IPv4
lease data on this VM's configuration — `/tmp/dhcp.leases` (Section 1)
remains the only correct data source for `/api/devices`, which is what
the shipped endpoint already does.

(Original Task 5 recommendation, for context: "prefer `ubus call dhcp
ipv4leases` if its populated shape ... reliably includes hostname/mac/ip/
expiry ... Either way, verify against a real attached client in Task 5
before committing to one approach" — this verification step is what 2a
above finally performs.)

## 3. `uci show network` (full output)

```
network.loopback=interface
network.loopback.device='lo'
network.loopback.proto='static'
network.loopback.ipaddr='127.0.0.1'
network.loopback.netmask='255.0.0.0'
network.globals=globals
network.globals.ula_prefix='fdd2:7aef:68d6::/48'
network.@device[0]=device
network.@device[0].name='br-lan'
network.@device[0].type='bridge'
network.@device[0].ports='eth0'
network.lan=interface
network.lan.device='br-lan'
network.lan.proto='static'
network.lan.ipaddr='192.168.1.1'
network.lan.netmask='255.255.255.0'
network.lan.ip6assign='60'
```

Note: there is no `network.wan` interface defined at all on this VM (Task 1's
README already documents "Single interface — eth0 is bridged into br-lan
only; there's no separate WAN interface wired up yet"). The firewall config
(section 4 below) still references a `wan` zone/network by name, which is
normal default OpenWrt config shipped even without a wan interface actually
existing — it's simply inactive/empty until one exists.

## 4. `uci show firewall` (full output)

```
firewall.@defaults[0]=defaults
firewall.@defaults[0].syn_flood='1'
firewall.@defaults[0].input='REJECT'
firewall.@defaults[0].output='ACCEPT'
firewall.@defaults[0].forward='REJECT'
firewall.@zone[0]=zone
firewall.@zone[0].name='lan'
firewall.@zone[0].network='lan'
firewall.@zone[0].input='ACCEPT'
firewall.@zone[0].output='ACCEPT'
firewall.@zone[0].forward='ACCEPT'
firewall.@zone[1]=zone
firewall.@zone[1].name='wan'
firewall.@zone[1].network='wan' 'wan6'
firewall.@zone[1].input='REJECT'
firewall.@zone[1].output='ACCEPT'
firewall.@zone[1].forward='REJECT'
firewall.@zone[1].masq='1'
firewall.@zone[1].mtu_fix='1'
firewall.@forwarding[0]=forwarding
firewall.@forwarding[0].src='lan'
firewall.@forwarding[0].dest='wan'
firewall.@rule[0]=rule
firewall.@rule[0].name='Allow-DHCP-Renew'
firewall.@rule[0].src='wan'
firewall.@rule[0].proto='udp'
firewall.@rule[0].dest_port='68'
firewall.@rule[0].target='ACCEPT'
firewall.@rule[0].family='ipv4'
firewall.@rule[1]=rule
firewall.@rule[1].name='Allow-Ping'
firewall.@rule[1].src='wan'
firewall.@rule[1].proto='icmp'
firewall.@rule[1].icmp_type='echo-request'
firewall.@rule[1].family='ipv4'
firewall.@rule[1].target='ACCEPT'
firewall.@rule[2]=rule
firewall.@rule[2].name='Allow-IGMP'
firewall.@rule[2].src='wan'
firewall.@rule[2].proto='igmp'
firewall.@rule[2].family='ipv4'
firewall.@rule[2].target='ACCEPT'
firewall.@rule[3]=rule
firewall.@rule[3].name='Allow-DHCPv6'
firewall.@rule[3].src='wan'
firewall.@rule[3].proto='udp'
firewall.@rule[3].dest_port='546'
firewall.@rule[3].family='ipv6'
firewall.@rule[3].target='ACCEPT'
firewall.@rule[4]=rule
firewall.@rule[4].name='Allow-MLD'
firewall.@rule[4].src='wan'
firewall.@rule[4].proto='icmp'
firewall.@rule[4].src_ip='fe80::/10'
firewall.@rule[4].icmp_type='130/0' '131/0' '132/0' '143/0'
firewall.@rule[4].family='ipv6'
firewall.@rule[4].target='ACCEPT'
firewall.@rule[5]=rule
firewall.@rule[5].name='Allow-ICMPv6-Input'
firewall.@rule[5].src='wan'
firewall.@rule[5].proto='icmp'
firewall.@rule[5].icmp_type='echo-request' 'echo-reply' 'destination-unreachable' 'packet-too-big' 'time-exceeded' 'bad-header' 'unknown-header-type' 'router-solicitation' 'neighbour-solicitation' 'router-advertisement' 'neighbour-advertisement'
firewall.@rule[5].limit='1000/sec'
firewall.@rule[5].family='ipv6'
firewall.@rule[5].target='ACCEPT'
firewall.@rule[6]=rule
firewall.@rule[6].name='Allow-ICMPv6-Forward'
firewall.@rule[6].src='wan'
firewall.@rule[6].dest='*'
firewall.@rule[6].proto='icmp'
firewall.@rule[6].icmp_type='echo-request' 'echo-reply' 'destination-unreachable' 'packet-too-big' 'time-exceeded' 'bad-header' 'unknown-header-type'
firewall.@rule[6].limit='1000/sec'
firewall.@rule[6].family='ipv6'
firewall.@rule[6].target='ACCEPT'
firewall.@rule[7]=rule
firewall.@rule[7].name='Allow-IPSec-ESP'
firewall.@rule[7].src='wan'
firewall.@rule[7].dest='lan'
firewall.@rule[7].proto='esp'
firewall.@rule[7].target='ACCEPT'
firewall.@rule[8]=rule
firewall.@rule[8].name='Allow-ISAKMP'
firewall.@rule[8].src='wan'
firewall.@rule[8].dest='lan'
firewall.@rule[8].dest_port='500'
firewall.@rule[8].proto='udp'
firewall.@rule[8].target='ACCEPT'
```

**Important for Task 7:** on this fresh VM there are **zero `config
redirect` sections** — the default OpenWrt firewall config only ships
`defaults`, `zone` (x2), `forwarding` (x1), and `rule` (x9) sections, all
addressed anonymously by UCI as `firewall.@<type>[<index>]` (e.g.
`firewall.@rule[3]`), none of them given an explicit name (no
`firewall.myrule=rule` style named section exists in the stock config —
every section here is anonymous). This means:
- Task 7 will be the first thing to ever create a `config redirect`
  section on this VM — there's no existing example to pattern-match, but
  it also means there's no legacy naming inconsistency to worry about.
- New sections added via `uci add firewall redirect` come back anonymous
  too (`firewall.@redirect[-1]` / `firewall.@redirect[0]` etc., addressed
  by index, exactly as the Task 7 brief already assumes) unless the code
  explicitly renames them with `uci rename firewall.@redirect[-1]=<name>`
  — worth doing in Task 7 so `DELETE /api/firewall-rules/<id>` can address
  a rule by a stable name instead of a potentially-shifting positional
  index after other rules are deleted. **Recommendation: have Task 7 name
  each created section explicitly** (e.g. `fwd_<timestamp>` or a short
  random id) right after `uci add`, and use that name as the `id` in the
  API — anonymous positional indices are not stable once other rules are
  deleted out from under them.

## 5. `nft list ruleset` (NAT-relevant chains — full ruleset trimmed, see note)

`nft list ruleset` runs cleanly (no errors) on this VM — `firewall4`/nftables
is active, confirming `uci`-driven firewall changes will actually take
effect via `fw4`/nftables, not legacy iptables. The full output also
includes the standard `input`/`forward`/`output`/`prerouting` filter chains,
SYN-flood protection, and the full ICMPv6 allow-list — all stock fw4
defaults with no bearing on Task 7's redirect work, omitted here to keep
this section focused; re-run `nft list ruleset` on a live VM if you need
to see them.

The chains that matter for Task 7 (port-forwarding = NAT, not filtering):

```
	chain dstnat {
		type nat hook prerouting priority dstnat; policy accept;
	}

	chain srcnat {
		type nat hook postrouting priority srcnat; policy accept;
	}

	chain srcnat_wan {
		meta nfproto ipv4 masquerade comment "!fw4: Masquerade IPv4 wan traffic"
	}
```

The `dstnat` chain is present but currently **empty** (`policy accept;`, no
rules) since there are no `config redirect` sections yet (see section 4) —
this is exactly where Task 7's added redirect rules will show up once
created, useful as the verification point Task 7 Step 4 already calls for.

## 6. `ubus list` (full output)

```
container
dhcp
dnsmasq
dnsmasq.dns
file
hotplug.dhcp
hotplug.iface
hotplug.neigh
hotplug.net
hotplug.ntp
hotplug.tftp
iwinfo
log
luci
luci-rpc
network
network.device
network.interface
network.interface.lan
network.interface.loopback
network.rrdns
network.wireless
rc
service
session
system
uci
```

Useful namespaces confirmed present: **`dhcp`**, **`network.device`**, and
**`system`** all exist (see sections 2, 7, 8).

## 7. `ubus call system board` (full output — useful for a future About screen)

```json
{
	"kernel": "5.15.167",
	"hostname": "OpenWrt",
	"system": "QEMU Virtual CPU version 2.5+",
	"model": "QEMU Standard PC (i440FX + PIIX, 1996)",
	"board_name": "qemu-standard-pc-i440fx-piix-1996",
	"rootfs_type": "ext4",
	"release": {
		"distribution": "OpenWrt",
		"version": "23.05.5",
		"revision": "r24106-10cc5fcd00",
		"target": "x86/64",
		"description": "OpenWrt 23.05.5 r24106-10cc5fcd00"
	}
}
```

`ubus call system info` also works (uptime, load, memory, root/tmp/swap
usage) — also useful for an About/System-status screen later:

```json
{
	"localtime": 1788151106,
	"uptime": 41,
	"load": [2816, 864, 128],
	"memory": {
		"total": 242728960,
		"free": 201531392,
		"shared": 57344,
		"buffered": 1466368,
		"available": 182411264,
		"cached": 9519104
	},
	"root": {"total": 100692, "free": 83628, "used": 17064, "avail": 81500},
	"tmp": {"total": 118520, "free": 118464, "used": 56, "avail": 118464},
	"swap": {"total": 0, "free": 0}
}
```

## 8. `ubus call network.device status` — device/link info

Works and returns per-device link state, MTU, MAC, and RX/TX statistics
for every network device (`br-lan`, `eth0`, `lo`) in one call — e.g.
`br-lan` shows `"up": true, "carrier": true, "bridge-members": ["eth0"]`.
Full JSON captured during this investigation is long (three devices'
worth of statistics); the shape above (section 3's `uci show network`)
plus this command together are enough to build a "network status" widget
without touching `/proc` directly. Available methods for this object per
`ubus -v list network.device`: `status`, `set_alias`, `set_state`,
`stp_init`.

## 9. Misc supporting facts

- `dnsmasq --version` → `Dnsmasq version 2.90`, compiled with `DHCP`
  support (not `no-DHCP`), confirming it's the live DHCP server for `lan`
  (`ps` shows `/usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf.cfg01411c...`
  running).
- `/proc/net/arp` on this fresh VM has exactly one entry:
  `192.168.1.2` (MAC `46:3d:ec:8c:db:e6`) on `br-lan` — this is the
  container's own tap-side socat relay address from `docker/entrypoint.sh`
  (a static IP assigned to the container's own tap0, not a DHCP client),
  **not** a real attached device. Task 5's liveness heuristic
  (ARP-table presence) should be aware this address will always show up
  and isn't a "real" LAN device to report.
- `uci show uhttpd` confirms `cgi_prefix='/cgi-bin'` and `home='/www'`
  (docroot) — directly relevant to Task 3/4's endpoint placement.

## 10. Task 7 addendum — `config redirect` zone/reachability investigation, confirmed live

Re-confirmed live before writing any code: `uci show network` and
`uci show firewall` on this VM still match Sections 3-4 above exactly —
zero `config redirect` sections, no `network.wan` interface, but a `wan`
*zone* still exists (`firewall.@zone[1].name='wan'`,
`.network='wan' 'wan6'`) referencing that non-existent network. This
section records what a real, live-added redirect actually does in this
topology, since Sections 3-4 only established the *inputs*, not the
generated-rule *behavior*.

**A `src='wan'` redirect generates a real, correct DNAT rule that is
permanently unreachable in this topology.** Added a throwaway
`config redirect` by hand (`src='wan'`, `proto='tcp'`, `src_dport='9999'`,
`dest_ip='192.168.1.232'`, `dest_port='8080'`, `target='DNAT'`), then
`fw4 reload` and inspected both `fw4 print` (dry-run) and the live
`nft list ruleset`. Both show the exact same result:

```
chain dstnat {
	type nat hook prerouting priority dstnat; policy accept;
	iifname "br-lan" jump dstnat_lan comment "!fw4: Handle lan IPv4/IPv6 dstnat traffic"
}
chain dstnat_lan {
}
chain dstnat_wan {
	meta nfproto ipv4 tcp dport 9999 counter dnat 192.168.1.232:8080 comment "!fw4: TestWanFwd"
}
```

The rule in `dstnat_wan` is exactly correct (right proto/port/dest match)
— but the top-level `dstnat` chain only ever jumps into `dstnat_lan`
(gated on `iifname "br-lan"`, the one real device that exists); there is
no equivalent jump into `dstnat_wan` because there is no wan
device/iifname to gate it on (no `network.wan` interface — Section 3).
**Confirmed conclusion: a `src='wan'` redirect is real, semantically
correct config that fw4 faithfully compiles to nftables, but zero packets
in this VM's topology can ever reach it** — not a bug in fw4 or in
anything built on top of it, a direct, confirmed consequence of this VM
having no WAN-facing path at all.

**A `src='lan'` redirect *is* reachable — traffic arriving via `br-lan`
(which does exist) jumps into `dstnat_lan`, and a redirect rule placed
there really does intercept and DNAT a live packet.** Repeated the same
experiment with `src='lan'`, `dest_ip='192.168.1.2'` (the container's own
tap-relay address — see Section 9 — chosen because it's the one address
in this topology that's both a real, already-configured local address in
the `openwrt` container's own netns *and* reachable from the guest via
`br-lan`). Result, confirmed live in `nft list ruleset`:

```
chain dstnat_lan {
	meta nfproto ipv4 tcp dport 9999 counter packets 0 bytes 0 dnat ip to 192.168.1.2:8080 comment "!fw4: ManualLanTest"
}
```

Sent one real TCP SYN at `192.168.1.1:9999` from a throwaway
`docker run --network container:openwrt` container (i.e. from the same
one real vantage point this topology offers "outside the guest" —
see Section 1a for the same attach mechanism). The counter above
incremented to exactly `packets 1 bytes 60` (one SYN-sized packet) the
moment the connection attempt was made, and **only** when the rule was
present — with the rule removed, the identical connection attempt fails
immediately (~0.5s, `ECONNREFUSED`-style fast failure, since nothing
listens on port 9999 directly), whereas with the rule present the same
attempt reliably runs the full 3s timeout instead (confirmed twice). This
differential (fast-refuse vs full-timeout, and the counter incrementing
exactly in step with each attempt) is a real, live, packet-level proof
that fw4's generated `dstnat_lan` rule is genuinely intercepting and
DNAT-rewriting a real TCP SYN — not simulated, not just "the config file
says so."

**Why the connection still doesn't fully complete (and why that's a
separate, well-understood limitation, not a redirect-mechanism failure):**
the "client" and the "target" in this test are unavoidably the same host
— every `docker run --network container:openwrt ...` invocation shares
the *exact same* network namespace as the `openwrt` container itself
(same `tap0`, same addresses), so there is no genuinely distinct
third network identity available in this topology to act as a separate
"internal target" reachable from the guest:
- The DHCP-lease route doesn't give one either: this environment's
  `busybox` image has **no `/usr/share/udhcpc/default.script`**
  (confirmed: `busybox udhcpc --help` shows that as the default `-s`
  value, and `ls /usr/share/udhcpc/` reports "No such file or
  directory") — so `udhcpc` completes a real DORA exchange and dnsmasq
  really does write a lease (Section 1a), but nothing ever runs `ip addr
  add` to apply that leased address to the client's own interface. A
  leased address like `192.168.1.232`/`192.168.1.145` is therefore a real
  server-side lease record but **not an address anything can actually
  bind or listen on** — confirmed live (a leased address never appears in
  `ip addr show tap0`, and nothing can `nc -l` on it).
- So the only two real, locally-ownable addresses in this whole topology
  are the guest itself (`192.168.1.1`) and the container netns
  (`192.168.1.2`) — and a redirect necessarily targets one of those two,
  making "client" and "DNAT target" the same host by construction.
  When the guest's DNAT rewrites the destination back to
  `192.168.1.2:8080` and forwards it back out `br-lan`, the reply
  (SYN-ACK) is computed by the *same* netns's kernel with destination
  `192.168.1.2` (the packet's original source) — since that address is
  locally owned, Linux delivers the reply via local/loopback-equivalent
  routing rather than sending it back out `tap0` through the guest a
  second time, so it never passes back through the guest's conntrack for
  the un-DNAT translation the original sender's TCP stack needs to
  recognize the reply as belonging to its own connection. This is the
  standard "hairpin NAT" problem (well documented in router/NAT
  literature generally, unrelated to this being OpenWrt specifically) —
  real routers normally solve it with an additional masquerade/SNAT step
  for intra-LAN loopback traffic (OpenWrt's own `wan`-zone "reflection"
  feature, seen as an fw4 warning during Section 4's investigation,
  exists for exactly this reason, but only reflects `wan`-zone redirects
  back into `lan` — it doesn't apply to a `lan`-sourced redirect at all).
  Confirmed conclusion: this is a structural limitation of this specific
  test topology (no third distinguishable network endpoint exists to
  serve as a genuinely separate "internal target"), not a defect in the
  redirect mechanism itself — the mechanism's packet-level interception
  and rewriting is independently proven by the counter/differential-
  timing evidence above.

**Practical takeaway for Task 7:** the `/api/firewall-rules` endpoint
hardcodes newly-created redirects to `src='wan'` (matching real port-
forwarding semantics, and matching the POST body shape, which has no
`src` field at all) — verification of *those* real, shipped rules is
therefore necessarily limited to confirming the exact generated `nft`
rule matches intended semantics (proto/port/dest, in the — currently
unreachable in this topology — `dstnat_wan` chain), which is still a real
proof that the full `uci add`/`set`/`rename`/`commit`/reload pipeline
this endpoint drives produces genuinely correct firewall config, not a
plausible-looking fake. The *separate*, `src='lan'` live-packet test
above (done by hand over SSH, not through the endpoint) exists purely to
prove the underlying reload/enforcement mechanism the endpoint relies on
is real — i.e. that if this VM ever gained a real WAN interface, the same
`src='wan'` rules this endpoint already creates would behave identically.

## 11. Wave 3 pre-investigation — no wireless config exists at all, but a manual one persists fine

Confirmed live (2026-08-31, before writing the Wave 3 plan): this VM has **no
`/etc/config/wireless` file at all** — `uci show wireless` fails with `uci:
Entry not found`, and `ls /etc/config/wireless` reports no such file. This
is expected: OpenWrt normally auto-generates this file by detecting real
wireless hardware during first boot (`wifi detect`), and this QEMU x86-64
"generic" image has no wireless PCI/USB device for it to find — consistent
with the already-documented Non-goal ("no physical wireless hardware exists
in a container").

**This does NOT block Settings/Guest-Wi-Fi work, it just means the config
has to be created, not just read.** Confirmed live:

```
touch /etc/config/wireless
uci set wireless.radio0=wifi-device
uci set wireless.radio0.type=mac80211
uci set wireless.radio0.disabled=1
uci set wireless.default_radio0=wifi-iface
uci set wireless.default_radio0.device=radio0
uci set wireless.default_radio0.network=lan
uci set wireless.default_radio0.mode=ap
uci set wireless.default_radio0.ssid='Smith Family'
uci set wireless.default_radio0.encryption=psk2
uci commit wireless
```

— all succeed, `uci show wireless` afterward reflects real, persisted
config exactly as set. `wifi reload` against this fake radio config also
runs cleanly (`exit 0`), just prints informational lines (`'radio0' is
disabled`, `radio0(mac80211): Interface type not supported`) rather than
erroring or hanging — safe to call from an API endpoint's write path,
consistent with the existing `uci firewall`/`fw4 reload` pattern.

**Implication for Wave 3's provisioning**: a baseline wireless config
(main SSID matching the mockup's static demo value "Smith Family", plus a
guest `wifi-iface` section) needs to be CREATED by a provisioning step
(the `touch` + `uci set` sequence above, adapted), not just read — there's
nothing to discover here the way `uci show firewall` already had real
zones/rules to build on in Wave 1. This mirrors Wave 1's firewall work in
spirit (real `uci` config, real reload, no real broadcast/traffic) but the
starting state is empty rather than pre-populated.

## 12. Wave 4 pre-investigation — real DNS blocklist and real VLAN interfaces, both confirmed live

Confirmed live (2026-09-01, before writing the Wave 4 plan):

**DNS-based ad blocking works via dnsmasq's own `confdir`, no new packages needed:**
```
mkdir -p /etc/dnsmasq.blocklist.d
echo "address=/doubleclick.net/0.0.0.0" > /etc/dnsmasq.blocklist.d/blocklist.conf
uci set dhcp.@dnsmasq[0].confdir=/etc/dnsmasq.blocklist.d
uci set dhcp.@dnsmasq[0].logqueries=1
uci commit dhcp
/etc/init.d/dnsmasq restart
```
`nslookup doubleclick.net 127.0.0.1` afterward genuinely resolves to `0.0.0.0` — real
blocking, not simulated. `logqueries=1` makes each query show up in `logread` with a
distinct, greppable line for a blocked hit: `... config doubleclick.net is 0.0.0.0`
(vs. a real upstream failure, which shows `... config error is REFUSED` — since this
VM has no WAN, ALL non-blocklisted/non-local lookups fail this way regardless of
blocking; there's no meaningful "blocked vs. successfully resolved" comparison to make
here, only "blocked vs. not queried/not in our list," and the blocked-hit log line is
the real, countable signal to build a "N blocked this week" stat from — parse
`logread` for `config <domain> is 0.0.0.0` lines where `<domain>` is in the blocklist,
same general approach as the existing `/api/logs` endpoint's `logread` parsing.

**VLANs are genuinely real at the kernel level, not just inert `uci` config:**
```
uci set network.kids=interface
uci set network.kids.proto=static
uci set network.kids.device=br-lan.2
uci set network.kids.ipaddr=192.168.2.1
uci set network.kids.netmask=255.255.255.0
uci commit network
/etc/init.d/network reload
```
`ip link show` afterward shows a genuine, `UP`, kernel-level 802.1q VLAN sub-interface:
`br-lan.2@br-lan`. `network reload` exits 0 cleanly (the radio0-related lines in its
output are just the same phantom-wireless noise `wifi reload` already produces
harmlessly, per §11 — unrelated to the VLAN interface itself). This is a stronger
result than Wave 3's original roadmap note assumed ("needs real multi-interface
trunking this VM's topology can't meaningfully demonstrate") — the VLAN tagging
itself is real and kernel-verifiable even without a second physical NIC to carry it
to a real trunked switch. Implication: Wave 4's planned read-only VLAN list can be
backed by genuinely created, genuinely `ip link`-visible interfaces, not just `uci`
strings — a stronger "real" bar than originally assumed, though still config-level
in the sense that no distinct physical port/hardware trunk exists to test end-to-end
inter-VLAN traffic isolation against.

## 13. Wave 5 pre-investigation — feasibility survey across all 10 remaining Group-1 roadmap items, confirmed live

Confirmed live (2026-09-01, before writing the Wave 5 plan). This VM was rebooted fresh via `docker compose up -d` (no state carried over from Wave 4's investigation session).

**`tc` is NOT installed and is a separate package**, unlike `ip` (already present):
```
$ ssh ... "which tc"
ash: tc: not found
```
Host has internet access and confirms an exact match for this target/release (`ip-full_6.3.0-1_x86_64.ipk`, `sqm-scripts_1.6.0-1_all.ipk` under `.../23.05.5/packages/x86_64/{base,packages}/`), so `tc`-based QoS is *technically* installable via the established host-download-then-scp pattern — but see the Traffic & QoS scoping note below on why this wave doesn't use it.

**No wireless-driver-style blocker for WireGuard — kernel module version matches this VM's exact kernel build:**
```
$ ssh ... "uname -r"
5.15.167
$ curl -s https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/packages/ | grep -io 'kmod-wireguard[^"]*\.ipk'
kmod-wireguard_5.15.167-1_x86_64.ipk
```
The kmod's version string (`5.15.167`) is an exact match to `uname -r`, not just a close one — OpenWrt kmod packages are normally version-pinned to one specific kernel build, so a mismatch would mean "cannot install." This one matches exactly, meaning `kmod-wireguard` is very likely to insmod cleanly. `wireguard-tools_1.0.20210914-2_x86_64.ipk` (the userspace `wg`/`wg-quick` tools) is under `.../packages/x86_64/base/` (not `packages/` or `routing/` — worth remembering for the provisioning script's download URL). Both `.ipk`s are architecture `x86_64`, matching `DISTRIB_ARCH` — no other feed had a wireguard-tools match. Neither package has been downloaded/installed yet as of this writing — only their existence and version-match was confirmed from the host.

**`nft` (fw4's backend) supports arbitrary counter objects, confirmed live:**
```
nft add table inet test5
nft add chain inet test5 c
nft add rule inet test5 c counter
nft list table inet test5   # -> "counter packets 0 bytes 0"
nft delete table inet test5
```
Real, incrementable byte/packet counters are available with no new packages — relevant to Traffic & QoS's "bandwidth used today" stat and a potential future Weekly Usage stat, if either is ever revisited.

**`cron`'s init script silently refuses to start crond unless `/etc/crontabs/` already has at least one file — confirmed by reading `/etc/init.d/cron` directly:**
```sh
start_service() {
	[ -z "$(ls /etc/crontabs/)" ] && return 1
	...
}
```
`/etc/init.d/cron start` returns exit 0 either way (the `return 1` only aborts `start_service`, procd still reports the overall init script call as successful), which makes the failure silent — running `/etc/init.d/cron start` against a stock fresh VM does NOT actually start `crond` (confirmed: `ps` showed no `crond` process afterward), and looks like it worked. **Implication for provisioning**: a script that wants a working cron must first create at least one file under `/etc/crontabs/` (e.g. `/etc/crontabs/root` with a comment line or a real entry) *before* calling `/etc/init.d/cron start`/`enable`, then verify via `ps` or `pgrep crond` that the daemon is actually up — not just trust the init script's exit code.

**Mockup content survey (`sadd-website.html`'s `screens` object, read directly, not assumed) for all 10 remaining Group-1 roadmap items — this materially changed the wave's scope from the roadmap's title-only listing:**

- **Per-Device Controls** (`devcontrols`) — a per-device detail screen (hardcoded to a demo device "Emma's iPhone" today) with: a `.timer-row` of `.timer-chip` buttons for "Pause internet" (15 min / 1 hr / Until tomorrow, no live countdown element in the markup), a `.switch`-based "Bedtime" toggle (School nights 9PM-7AM), a `.radio-card` group for "Content filter - this device" (Kid-safe / Teen / Off), and a static "Blocked apps - this device" list (TikTok/Instagram/YouTube/Roblox, Blocked/Allowed). Reached today only as a standalone demo screen, not linked from the real Devices list.
- **Developer & API Access** (`advapi`) — API keys section (masked demo key, "Generate new API key" - a Sadd-cloud concept, no OpenWrt/UCI equivalent), Webhooks (static "Not configured"), Remote access: an `SSH access` `.switch` (currently rendered `off` in the markup even though this VM's dropbear is actually always running) plus a plain `<button class="btn btn-secondary">Rotate now</button>` next to "Rotate SSH key" / "Generates a new key and invalidates the old one immediately", and static Docker-containers/opkg informational text.
- **VPN Server (WireGuard)** (`advwireguard`) — uses the established `.toggle-hero` + `.switch on` hero pattern (`<div class="th-main"><strong>WireGuard Server</strong><span>Running &middot; UDP port 51820</span></div><div class="switch on"></div>`, structurally identical to the About/Settings/Guest-Wi-Fi/Ad-Blocking hero rows this codebase already has a `syncFallbackNotice`-based pattern for) plus a `Connection details` block of `.tech-row`s (Protocol, Port, Public key, VPN subnet, Hostname), then Advanced toggles (persistent keepalive, redirect-all-client-traffic, full-LAN-access), a Client devices list with "Add client (generates QR code)", a measured-throughput stat, third-party-VPN device routing, Site-to-site, and an AmneziaWG section.
- **VPN Server (OpenVPN)** (`advvpn`) — same shape as WireGuard's screen (protocol/port/cipher/auth-digest/subnet tech-rows, advanced toggles, client certificates list), explicitly framed in its own copy as the non-default alternate protocol ("The one-tap toggle in Remote Access uses WireGuard by default").
- **Connect a Laptop (VPN)** (`laptopvpn`) — two client paths: an "Easy setup" path that references downloading a fictional "Sadd Connect" app (Windows/Mac) and signing in with a Sadd account, and a manual path ("Download your configuration file" -> `Download .ovpn` -> open in an OpenVPN-compatible app) - both feeding into a static `Server smith-family.saddvpn.com / Port 1194 (UDP)` details block.
- **Traffic & QoS** (`advqos`) — Gaming-priority and Video-call-priority toggles, a "Priority devices" list (2 hardcoded demo devices), and a static "Bandwidth used today" breakdown by device given as fixed percentages (Living Room TV 41%, Leo's Xbox 26%, Everything else 33%) with no chart/real-time element.
- **Multi-WAN & Failover** (`advwan`) — Primary (Fiber, 1000/500 Mbps, Connected) and Backup (Cellular, "Not configured") connections, auto-switch toggle, a Failover/Load-balance mode radio group, "Pin a device to one connection," and a static "Recent switch history" ("No failover events... stable for 30 days").
- **Parental Controls** (`parental`, the profile-level hub) — per-child profile cards (Emma/Leo), then for the selected child: Bedtime toggle, "Pause now" (profile-wide, not per-device), a Homework-mode custom weekly schedule grid, a Content-filter radio group (Kid-safe/Teen/Off/Custom with 15 named categories), Safe Search toggle, a custom-blocked-sites list, a Blocked-apps list explicitly split into "Reliable" vs. "Best-effort" tiers ("Best-effort apps use traffic patterns that can change - we can't promise 100% blocking the way we can for Reliable ones"), and per-site Exceptions.
- **Weekly Usage** (`usagereport`) — explicitly per-CHILD, not per-router: "Emma's Weekly Usage," a day-by-day screen-time breakdown for one calendar week, and a "Top apps & categories" list with real-looking per-app durations (YouTube 4h20m, Roblox 3h05m, etc.) plus a "Social media (blocked) 0m - filter working" line.
- **Notifications** (`notifications`) — on direct inspection this is a pure notification-**preferences** panel (toggle groups for "Notify me for" urgency level, "New device joins," "Security threats blocked," "Child device tries a blocked site," "Network goes offline" (always-on, can't be turned off), an industry-wide-security-incident alert opt-in with static preview text, and a weekly "Network Health summary" email opt-in with static preview text) — there is no live notification feed/list anywhere in this screen's markup, and no push/email delivery system exists (or is in scope) to back any of it with real state.

**Scoping implications drawn from the above** (see the Wave 5 plan for the full reasoning):
- Per-Device Controls, Developer & API Access, and VPN Server (WireGuard) each have at least one slice that's genuinely backable with real VM state using patterns already established in this codebase (real firewall/nft state, the hero-toggle pattern, a real dropbear action) — these are Wave 5's scope.
- Traffic & QoS's core content (the bandwidth-percentage breakdown) needs real, *substantial* per-device traffic to mean anything; this VM only ever carries trivial manual-test traffic, so a real number here would be technically real but not honestly representative. Deferred.
- Multi-WAN & Failover requires a second real WAN-side interface, which this single-NIC VM structurally does not have and cannot gain without a docker/entrypoint.sh networking rework (a second tap device) — out of proportion for a wave. Deferred.
- Parental Controls (profile-level), Weekly Usage, and most of VPN Server (WireGuard)'s own client-management/AmneziaWG/site-to-site sections, VPN Server (OpenVPN), and Connect a Laptop (VPN) all either depend on a child<->device "profile" concept that exists only in the fictional Sadd cloud app (not OpenWrt/UCI), or explicitly claim DPI-level per-app traffic detection ("Reliable" vs "Best-effort" blocking) this environment has no honest way to do, or reference a fictional client app that can't be made real regardless of VM state. Deferred/excluded.
- Notifications turned out, on actually reading its markup, to have no live state to back at all — reclassified from a Wave 5 candidate to Group 2 (pure UI, no work needed), not merely deferred.
