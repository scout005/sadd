# Sadd → OpenWrt Implementation Mapping

### How every screen in the mockup maps to real OpenWrt mechanisms, packages, and config files

---

## Architecture Overview

Sadd's UI implies two distinct layers, and it's important to separate them before mapping individual screens:

1. **On-router layer (OpenWrt itself)** — UCI configs, LuCI/ubus, and standard packages running on the router hardware. This is where Wi-Fi, firewall, VLANs, DHCP, VPN, and QoS actually live.
2. **Cloud/companion layer (not OpenWrt)** — account management, MFA, push notifications, the mobile app backend, and remote cert issuance for "Easy setup" VPN. OpenWrt has no native concept of user accounts, subscriptions, or mobile push — these require a companion cloud service that talks to the router over a secured local API (ubus/rpcd over HTTPS, or an MQTT/WebSocket agent for cloud sync).

A small **on-router agent daemon** (custom-built, not stock OpenWrt) is the practical bridge between these two layers: it translates simple app actions ("pause Emma's device") into the correct UCI/firewall/dnsmasq changes, and reports status back to the cloud. Every screen below either maps to (a) a stock OpenWrt mechanism directly, or (b) requires this custom agent plus a cloud component — each entry is labeled accordingly.

**Legend:**
- 🟢 **Native OpenWrt** — stock package/UCI config, no custom development needed beyond UI wiring
- 🟡 **OpenWrt + custom agent** — built from OpenWrt primitives, but needs the custom Sadd agent to expose it simply
- 🔴 **Cloud/companion required** — not an OpenWrt concern at all; lives in the backend/mobile app

---

## 1. Onboarding & Account (Screens 1–3, 11–13)

| Screen | Mechanism | Notes |
|---|---|---|
| Login / Create account | 🔴 Cloud auth service | OpenWrt has no user-account concept. Standard email/password or OAuth backend (e.g. Cognito, Auth0, or custom) issues a session token the mobile app uses to authenticate to *your* cloud API — separate from the router. |
| Verify identity (MFA) | 🔴 Cloud (TOTP/SMS) | TOTP via a standard library (e.g. `pyotp` server-side) or SMS via Twilio/SNS. No router involvement. |
| Welcome / Connect router / Setup success | 🟡 OpenWrt `uci-defaults` + custom agent | First-boot state is staged via scripts in `/etc/uci-defaults/` that run once on first boot after `sysupgrade`/`firstboot`. The "Connect router" QR/pairing step needs a custom pairing daemon that generates a one-time claim token, exposed over the router's local AP before it's on the internet (similar pattern to Google Wifi/eero's captive setup flow). |

---

## 2. Core Setup (Screens 4–5, 27)

| Screen | Mechanism | Config file(s) | Notes |
|---|---|---|---|
| Name your Wi-Fi & password | 🟢 Native | `/etc/config/wireless` — `option ssid`, `option key`, `option encryption 'sae-mixed'` (WPA3/WPA2) | Applied via `wifi reload` or `ubus call network reload`. Requires `wpad-openssl` (not the smaller `wpad-basic`) for WPA3-SAE support. |
| Router name | 🟢 Native | `/etc/config/system` — `option hostname` | Also shown in DHCP/mDNS advertisements. |
| Auto-discover devices | 🟡 OpenWrt + custom agent | `dnsmasq` leases (`/tmp/dhcp.leases`), `ip neigh` (ARP/NDP table) | Device *type* guessing (phone vs. TV vs. console) needs MAC OUI lookup + optional mDNS/UPnP fingerprinting (`avahi-daemon`, `miniupnpd` logs) — this classification logic is custom, OpenWrt only gives you the raw lease/ARP data. |
| Connect a device (Wi-Fi join) | 🟢 Native | `hostapd` (via `wpad-openssl`) | This is just standard WPA2/WPA3-PSK client authentication — no custom work. The in-app QR/instructions screen is purely a UI convenience layer over data already in `wireless` config. |

---

## 3. Simple Mode — Daily Use (Screens 6–10, 19)

| Screen | Mechanism | Config file(s) / package | Notes |
|---|---|---|---|
| Home dashboard status | 🟡 Custom agent | `ubus call network.interface.wan status`, `logread`, ping checks | "Everything is working" is a synthesized health check — no single OpenWrt command produces this; the agent aggregates WAN link state, DNS resolution test, and recent `logread` errors into one verdict. |
| Devices list | 🟢 Native (read) | `/tmp/dhcp.leases`, `ip neigh`, `iwinfo assoclist` | Per-device online/offline and signal strength are all standard OpenWrt data sources. |
| Pause internet (per device) | 🟢 Native | `/etc/config/firewall` — `config rule` matching `src_mac`, target `REJECT`; or `nft` set membership | Simplest implementation: an nftables set (`ipset`-equivalent) named e.g. `paused_macs`, toggled by adding/removing the device's MAC. Timed pauses (15 min / 1 hr) use `at` or a short-lived `cron` entry to remove it automatically. |
| Bedtime schedule | 🟡 OpenWrt + custom agent | `cron` (`/etc/crontabs/root`) toggling the same MAC-based firewall/nft rule at set times | Native `cron` + firewall; the agent just manages the generated cron lines from the friendly time picker in the app. |
| Parental controls — content filter | 🟡 OpenWrt + custom agent | `dnsmasq` per-tag config: `dhcp-host` entries tag a device (`tag:kids`), then `address=/domain/0.0.0.0` or `server=/domain/` rules apply only to tagged clients | This is a well-established OpenWrt pattern (tag-based dnsmasq filtering). "Kid-safe / Teen / Off" presets are just pre-built domain-category lists the agent applies based on the selected tier. |
| Parental controls — named app blocking (TikTok, Instagram, etc.) | 🟡 OpenWrt + custom agent | Same dnsmasq tag mechanism, or SNI-based blocking via `nft` + `dnsmasq` for HTTPS domains | Blocking by app name really means blocking that app's known domains/CDN endpoints — the agent maintains a curated domain list per app, since apps change infrastructure occasionally and this list needs maintenance (this is *not* something OpenWrt ships out of the box). |
| Security — Ad Blocking | 🟢 Native (as DNS sinkhole) | `AdGuardHome` package, or `simple-adblock` / `banIP` + `dnsmasq` blocklists | AdGuard Home (full package, needs more RAM/flash) gives the richest UI/stats backend; `simple-adblock` is the lighter stock-friendly option for constrained hardware. |
| Security — Threat Protection | 🟡 OpenWrt + optional heavier package | `banIP` (IP/GeoIP blocklists), or Suricata/Snort via `luci-app-ids` on capable hardware | Full IDS/IPS (deep packet inspection) is realistic only on higher-end router SoCs (need more CPU/RAM than typical consumer routers) — lighter deployments should scope "Threat Protection" to blocklist-based (banIP), not full IDS, and set expectations accordingly in hardware selection. |
| Security — Automatic Updates | 🟢 Native | `auc` package (attended sysupgrade client) + `luci-app-attendedsysupgrade` | Handles unattended background firmware updates, which is exactly what the toggle promises. |
| Security — Smart Home Isolation | 🟢 Native | VLANs + firewall zones (see Screen 17 below) | Not a separate mechanism — this toggle in Simple Mode is really just a friendly on/off for the IoT VLAN/zone isolation that Advanced Mode exposes directly. |
| Remote Access (VPN on/off) | 🟢 Native | `openvpn-openssl` + `easy-rsa` + `luci-app-openvpn`; DDNS via `ddns-scripts` + `luci-app-ddns` | This is the simple-mode wrapper around Screen 24's full OpenVPN server config — same underlying mechanism, fewer visible knobs. |
| Guest Wi-Fi | 🟢 Native | Second `wifi-iface` in `/etc/config/wireless` bridged to a dedicated `guest` firewall zone with default-reject to `lan` | Time limit uses the same `cron`-based toggle pattern as bedtime schedules, applied to the guest zone/SSID instead of a device. |

---

## 4. Help & Settings (Screens 14–15)

| Screen | Mechanism | Notes |
|---|---|---|
| Help & Fixes — status checks | 🟢 Native (read) | `ubus call network.interface.wan status`, ping/DNS resolution tests, `iwinfo` signal readings — all standard OpenWrt diagnostic data, just re-surfaced in plain language. |
| Help & Fixes — guided restart | 🟢 Native | `reboot` triggered via authenticated ubus/rpcd call. |
| Settings — Wi-Fi name/password | 🟢 Native | Same `wireless` UCI as Screen 4. |
| Settings — Update router | 🟢 Native | `sysupgrade` / `auc`, same as Screen 9's Automatic Updates. |
| Settings — Notifications | 🔴 Cloud + 🟡 hotplug triggers | OpenWrt can fire local events (`hotplug`, `ubus` event subscriptions for e.g. new DHCP lease, WAN down) but actually delivering a push notification to a phone requires the cloud layer (APNs/FCM) — the agent forwards local events to the cloud, which handles push. |

---

## 5. Advanced Mode (Screens 16–18, 20–23, 24, 26, 28)

| Screen | Mechanism | Config file(s) / package | Notes |
|---|---|---|---|
| Network & VLANs | 🟢 Native | `/etc/config/network` (VLAN `device`/`bridge-vlan` sections on DSA-based OpenWrt, or `.vlan` interfaces on swconfig-based), each VLAN paired with a `/etc/config/firewall` zone | This screen is essentially a friendly reskin of LuCI's own Network > Interfaces and Firewall > Zones pages. Each "network" (Main, Kids, IoT, Guests) = one VLAN + one firewall zone with explicit forwarding rules between zones. |
| Firewall & Port Forwarding | 🟢 Native | `/etc/config/firewall` — `config redirect` sections (DNAT rules) | Directly maps to LuCI's Firewall > Port Forwards. "Block unsolicited inbound" = the zone's default `input`/`forward` policy set to `REJECT`/`DROP`. UPnP toggle maps to enabling/disabling `miniupnpd`. |
| Traffic & QoS | 🟢 Native | `sqm-scripts` + `luci-app-sqm` (bufferbloat/queue management); per-device priority via `tc`/`nft` DSCP marking or `cake`'s per-host fairness | Gaming/video-call prioritization in plain language = pre-built SQM/QoS profiles the agent applies; "priority devices" list maps to per-MAC traffic classes. |
| Multi-WAN & Failover | 🟢 Native | `mwan3` package + `luci-app-mwan3` | Direct 1:1 mapping — mwan3 is the standard OpenWrt multi-WAN load-balance/failover solution, including health-check-based automatic switching exactly as described in the screen. |
| Diagnostics & Logs | 🟢 Native | `logread`, `luci-app-statistics` (collectd + rrdtool graphs), `nlbwmon` or `vnstat` for per-device bandwidth history | Live throughput numbers come from `nlbwmon`/`vnstat`; the plain-language activity log (e.g. "Emma's iPhone joined the network") is the agent translating raw `logread`/DHCP-lease-event lines into readable sentences. |
| Developer & API Access | 🟡 OpenWrt (`rpcd`) + custom scoping | `rpcd` + ACL files in `/usr/share/rpcd/acl.d/` | OpenWrt's own admin UI (LuCI) already runs entirely on ubus/rpcd's JSON-RPC API — exposing a *scoped* subset of it as a documented "API key" system is custom work: defining a restricted ACL per key and a token-auth wrapper around rpcd. Webhooks (arbitrary outbound HTTP on events) are fully custom — not a stock OpenWrt feature. |
| VPN Server (OpenVPN) | 🟢 Native | `openvpn-openssl`, `easy-rsa`, `/etc/config/openvpn`, `luci-app-openvpn` | Direct mapping — per-client certs are generated via `easy-rsa`'s `build-client-full`, and the "issued/revoke" UI in the mockup maps to `easy-rsa revoke` + regenerating the CRL. Cipher/digest/subnet fields in the mockup are literal OpenVPN server config directives. |
| Per-device parental controls | 🟡 OpenWrt + custom agent | Combines: `dhcp-host` static leases (to reliably tag a device by MAC), dnsmasq tag-based filtering (content filter override), MAC-based firewall/nft rules (pause, bedtime), and traffic monitoring (`nlbwmon`) for screen-time counting | "Screen time used today" is the one feature with no direct OpenWrt equivalent — it requires the agent to actively track a device's connection/traffic activity over time and maintain a running daily counter, since OpenWrt itself has no concept of "active usage minutes." |
| Connect a laptop (VPN) — Easy setup | 🔴 Cloud + 🟡 router-side signing endpoint | Custom "Sadd Connect" desktop app (not OpenWrt) + a router-side signing endpoint | The one-click "sign in and connect" flow requires: (1) a custom cross-platform desktop client wrapping an OpenVPN library, (2) a cloud auth handoff proving the user's identity, and (3) an authenticated router-side API (via the custom agent) that runs `easy-rsa build-client-full` on demand and returns the resulting cert/config to the desktop app automatically. None of this exists in stock OpenWrt — it's the most custom-engineering-heavy screen in the whole set. |
| Connect a laptop (VPN) — Manual/managed path | 🟢 Native | Same `easy-rsa`-generated `.ovpn` file as Screen 24's "Add client" | This fallback path is actually the *simpler* one to build — it's just exposing an existing OpenVPN client config file for download, no custom signing flow needed. |

---

## Required Non-Stock / Custom Components (Summary)

These don't exist in a default OpenWrt image and need to be built or integrated:

1. **Sadd Agent daemon** — the on-router bridge between simple app actions and UCI/firewall/dnsmasq changes; also the source of plain-language status summaries and activity logs.
2. **Cloud backend** — accounts, MFA, subscriptions, push notifications, cert-issuance handoff for laptop "Easy setup" VPN.
3. **Pairing/claim flow** — first-boot QR pairing between a fresh router and a phone/account.
4. **App-domain-list maintenance** — the curated, updated domain lists behind "block TikTok/Instagram/etc." (this is an ongoing content-ops task, not a one-time engineering task).
5. **Device-type classification** — MAC OUI + mDNS/UPnP fingerprinting logic for the auto-discover flow's "Phone / TV / Console" labels.
6. **Screen-time tracking** — active-usage counting per device, layered on top of `nlbwmon`/traffic data.
7. **Scoped API/webhook layer** — a restricted, documented wrapper around `rpcd` for the Developer & API screen.
8. **Sadd Connect desktop client** — the laptop-side app for one-click VPN in Screen 28's Easy setup path.

## Suggested Base Package List

```
# Wi-Fi / WPA3
wpad-openssl

# Firewall / NAT (stock on most images)
firewall4  (nftables-based, current OpenWrt default)

# VPN
openvpn-openssl
easy-rsa
luci-app-openvpn

# DDNS
ddns-scripts
luci-app-ddns

# Ad blocking / DNS filtering
adguardhome        # richer option, needs more flash/RAM
# — or —
simple-adblock      # lighter option
banIP                # IP/GeoIP blocklists, threat protection

# QoS
sqm-scripts
luci-app-sqm

# Multi-WAN
mwan3
luci-app-mwan3

# Diagnostics
luci-app-statistics
collectd-mod-*      # per relevant metrics
nlbwmon
luci-app-nlbwmon

# Auto-updates
auc
luci-app-attendedsysupgrade

# Guest network / UPnP (optional, off by default per Screen 18)
miniupnpd
```

---

## Overall Take

Roughly **60% of the product maps to stock OpenWrt packages with zero custom firmware work** — VLANs, firewalls, VPN, QoS, multi-WAN, and diagnostics are all mature, well-documented OpenWrt subsystems already exposed (in raw form) through LuCI. The real engineering investment is concentrated in exactly the places the product brief predicted it would be: the **translation layer** between OpenWrt's technical primitives and Sadd's plain-language UI (the custom agent), plus the **cloud account/notification/cert-issuance layer** that OpenWrt was never designed to provide on its own.
