# Home Network Security Research — Consolidated Reference
*Combines sourced 2025–2026 survey data with general security best-practice knowledge, for designing a security-focused, non-technical-friendly router UI.*

---

## 1. Devices normally connected to a home network

**Sourced data:** Average smart-home-specific device count is 6.2 per household (down from a pandemic-era peak of 8). Counting *all* connected devices (phones, laptops, IoT, etc.), US households average 21 connected devices across 13 categories, and homes with 5+ devices now average 14.3 devices. Multi-router setups are increasingly common — 59% of US households now run 2+ routers/mesh nodes.

**Common device categories** (sourced + general knowledge):
- Smartphones & tablets (often multiple per person)
- Laptops & desktop computers
- Smart TVs & streaming devices (Roku, Apple TV, Fire TV, Chromecast) — smart TVs are the single most prevalent smart-home device at 57% of US households
- Gaming consoles (PlayStation, Xbox, Switch)
- Smart speakers/assistants (Echo, Nest) — 79% of smart-device households have one installed
- Wi-Fi printers/scanners
- Smart home / IoT: lights, plugs, thermostats, robot vacuums
- Security devices: cameras, video doorbells, smart locks — ~61% of US households now have at least one security camera
- Wearables (smartwatches, fitness trackers)
- Smart appliances, kids' tablets/toys, NAS/storage drives

**Design implication:** the device list has to handle 15–20+ items gracefully — icons, friendly names, and grouping (by person/room), not a raw technical table.

---

## 2. The core security gap (why this matters — sourced)

From a 2025 survey of 3,242 UK users (Broadband Genie, with McAfee input):
- 47% have never adjusted any router factory settings
- 81% have not changed the router admin password
- 69% have never changed their Wi-Fi password
- 84% have never updated router firmware
- 85% have never changed their network name
- 69% have never checked who's using their network (despite an average of 12 connected devices)
- **The critical insight:** 79% know *how* to change settings, but 73% don't know *why* they'd need to.

**Design implication:** the blocker isn't UI complexity alone — it's that security work feels optional. The UI needs to make the *stakes* visible (plain-language status) and make fixes near-zero-effort (auto-updates, forced setup steps) rather than just "easier to find."

---

## 3. Simple security needs for home networks (baseline checklist)

**Sourced essentials** (from the same study's expert guidance):
- Change router admin password + Wi-Fi password — most effective, easiest fix
- Change the default network name (default names help attackers identify router models)
- Keep firmware updated, ideally automatically
- Regularly check the connected-device list and remove unrecognized devices

**Additional features generally expected in modern secure routers** (best-practice / industry-standard, not from a single cited study — treat as design targets rather than survey findings):
- WPA3 encryption by default, with an easy password-change flow
- Built-in firewall, on by default
- Guest network, isolated from main/IoT devices
- Device isolation/segmentation, especially for IoT devices (which carry a disproportionate share of vulnerabilities — smart TVs, smart plugs, and DVRs were among the most-vulnerable categories in past IoT vulnerability research)
- Real-time alerts ("new device joined," "suspicious activity")
- Network-level ad/malware/tracker blocking
- Optional network-wide or per-device VPN
- A simple security "health score" or scan
- Secure remote access without exposing the network directly

---

## 4. What parents want to control

**Sourced data:** Parental-control adoption is low and uneven — 51% of parents use them on tablets, 47% on smartphones, 43% on laptops, 38% on smart TVs, 35% on game consoles. This isn't apathy — controls are often easy for kids to defeat, which causes parents to give up. Content and *time spent* worry parents more than stranger contact (69% concerned about content impact, 64% about time spent, only 32% about strangers). Importantly, 89% of kids say they're comfortable telling a parent if something online feels unsafe — suggesting tools that support conversation (visibility/reports) may work better than pure lockdown.

**Commonly requested control types** (sourced concerns + general feature expectations):
- Content filtering by category (adult content, violence, gambling)
- Screen time / usage limits, per child or device
- Scheduled internet pauses (e.g., bedtime cutoff)
- App/game blocking
- Social media / YouTube restrictions (safe search, restricted mode)
- Usage reports and activity logs
- Instant pause for a specific device
- Simple profiles ("Kid," "Teen," "Adult") instead of manual rule-building
- One-tap "Family Mode" applying safe defaults across all child devices

**Design implication:** app-based parental controls are trivially bypassed by removing the app; a **network-level** control a child's device can't uninstall is a genuine differentiator for a router product.

---

## 5. Requested feature set (product requirements from stakeholder)

These are explicit features to design for, layered on top of the research above:

- **Multi-factor authentication (MFA)** for router admin login — not tied to one provider, should support multiple methods:
  - Mobile push/SMS
  - Email code
  - Authenticator app (Google Authenticator or any TOTP-compatible app)
- **Simple, non-technical-first UX/UI** across the whole app — consistent with the design direction in Section 6
- **A visible block page** shown when a website, app, or mobile app is blocked — rather than a silent failure/timeout. This needs to appear for:
  - Websites (browser-level)
  - Desktop/traditional applications
  - Mobile apps
- **Network-wide ad blocking**
- **Built-in VPN** at the router level (protects all connected devices without per-device setup)
- Open-ended — more features expected to be added as the spec develops

**Decisions (confirmed):**
- **MFA default:** SMS/mobile push is the recommended first option shown during setup — no app to install, works on any phone. Email code and authenticator app remain available as alternatives in the same setup flow, but push/SMS is the pre-selected default.
- **Block page behavior:** Friendly tone, but with **no self-serve "request access" button**. A blocked user sees a clear, non-alarming message (e.g., "This site is blocked by your network's Family settings"), but unblocking is a deliberate action the account admin/parent has to take from the app — not something the blocked person can trigger themselves.

**Design implications:**
- The MFA setup wizard should pre-select SMS/push and let the user complete it in one flow (enter number → confirm code), with "Use an authenticator app instead" or "Use email instead" as a visible but secondary option — not hidden in settings.
- Because there's no request-access flow, the block page should clearly point to *where* the fix happens ("Ask a parent to update this in the [App Name] app") so the blocked person isn't stuck with no next step, even without a self-serve unblock button — this avoids the page feeling like a dead end while still keeping unblock authority solely with the admin.
- Blocking mobile *apps* (not just sites) at the router level is technically harder than site/DNS-based blocking, since many apps don't map cleanly to blockable domains — this may need app-recognition/traffic-fingerprinting, which is worth flagging as a technical constraint to validate with engineering early.
- Ad blocking and VPN both benefit from a single "on/off" toggle for non-technical users, with any advanced configuration (custom block lists, VPN server location/protocol) tucked behind an "Advanced" area.

## 6. Router UI/UX design direction

**Design goal:** manage security in under 30 seconds, zero jargon, big touch targets, mobile-first with a simple web fallback.

### Home dashboard
- Large plain-language security status (e.g., "Your network is secure" / score or checkmark, not a percentage requiring interpretation)
- At-a-glance: device count, guest network status, update status
- One-tap actions: Pause All Internet, Scan Network, Add Guest, Security Tips

### Devices screen
- Visual list/grid with auto-detected icons and friendly names, not MAC addresses
- Tap a device → Rename, Pause, Block, Set Time Limits, Assign to Profile
- Unknown/new devices visually flagged with an immediate "Block?" option

### Security screen
- Checklist with toggles and one-tap "Fix" buttons per item
- "Enable All Recommended Protections" single action
- Friendly alerts feed, not a raw log

### Parental controls screen
- Profile cards per child, not per-device rule sheets
- Visual schedule sliders for bedtime/limits
- Category toggles for content filtering
- Simple weekly usage reports/charts

### Cross-cutting principles
- Color coding: green = safe, yellow = review, red = action needed
- A "not technical" default mode that hides advanced settings behind an explicit toggle
- Guided setup wizard; forced password/network-name change on first boot rather than optional
- Proactive suggestions ("We noticed a new smart camera — want to isolate it on its own network?") instead of relying on users to go check
- Accessibility: high contrast, dark/light mode, minimal required reading

---

---

## Key takeaway

The sourced research and general best practices agree on the same core finding: most users aren't blocked by *ability* — 79% already know how to access router settings — they're blocked by not understanding *why it matters* and by security tasks feeling skippable. The highest-leverage design move isn't more settings, it's making risk visible in plain language and removing the need for the user to act at all wherever automation is possible (auto-updates, forced first-run password change, automatic device flagging).

**Sources for cited figures:**
- Broadband Genie / McAfee, *Router Security Survey 2025* (3,242 UK respondents)
- Family Online Safety Institute (FOSI), *Connected and Protected: 2025 Online Safety Survey* (1,000 US parents + 1,000 children aged 10–17)
- Parks Associates, Home Networking consumer research (US households)
- SQ Magazine / IDC, *Smart Home Statistics 2026*
- ConsumerAffairs, *Average Number of Smart Devices in a Home 2026*
