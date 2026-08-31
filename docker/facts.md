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
