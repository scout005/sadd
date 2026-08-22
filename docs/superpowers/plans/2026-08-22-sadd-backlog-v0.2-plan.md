# Sadd Product Backlog & User Stories v0.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce `docs/03-Sadd-Product-Backlog-User-Stories.html`, a new v0.2 requirements reference that merges Sadd's existing product brief (`docs/home-router-user-needs-analysis.md`) with gated-in material from the new Sentinel reference docs (`docs/01-Competitive-Analysis-Firewalla.html`, `docs/02-Product-Backlog-User-Stories.html`), tag the pre-merge repo state `v1` in git, and wire the new doc into `docs/README.md` as the canonical requirements reference.

**Architecture:** A single static HTML doc reusing the sidebar/TOC/search/progress-bar/topbtn chrome already proven in the two Sentinel reference docs (same CSS structure, same vanilla-JS active-section-highlighting/search/mobile-menu script), re-themed to Sadd's brand (teal `#0D9488`, Baloo 2 + Nunito). Built incrementally: Task 1 lays down the full shell + Vision + Personas + Epic Overview; Tasks 2–7 append story content epic-group by epic-group using a stable boundary-anchored `Edit` pattern (insert immediately before a unique closing-tag sequence, so each task's `old_string` still matches regardless of what earlier tasks inserted); Task 8 appends the Roadmap/DoR/DoD/Health-Snapshot/Change-Log sections; Task 9 wires up `docs/README.md`, tags `v1`, and pushes everything.

**Tech Stack:** Static HTML/CSS/vanilla JS (no build step), Git.

---

## Content authoring note (read before Task 2)

Tasks 2–7 do **not** contain literal pre-written final HTML for every story — with ~18 epics and roughly 90+ resulting stories, hand-writing every row here isn't practical (see the design spec's "Authoring approach" section for why this is an intentional, approved deviation from putting complete final content in every step). Instead, each of those tasks gives the implementer:

- The exact epics in scope for that task, with the rationale/provenance text to use (already drafted below — this part IS literal, copy it as given).
- For each epic, a **source map**: which Sentinel stories (by ID, from `docs/02-Product-Backlog-User-Stories.html`) to pull in, which existing Sadd material (by section, from `docs/home-router-user-needs-analysis.md`) to formalize into stories, and explicit merge/exclude notes for near-duplicates.
- The **exact row format** to use, with one fully-worked example story per task so the format is unambiguous.
- The **tier tag** (`[Simple]` / `[Advanced]` / `[Business]`) and **provenance tag** (`[Sadd]` / `[Sentinel]` / `[NEW]`) rule, applied per-story.

The implementer drafts the actual story text/acceptance-criteria/points within that brief. This is a content-authoring task, not a mechanical code change — use judgment consistent with Sadd's plain-language voice for `[Simple]`-tier stories.

---

## File Structure

- Create: `docs/03-Sadd-Product-Backlog-User-Stories.html` — the new backlog doc (all of Tasks 1–8)
- Modify: `docs/README.md` — add a pointer to the new doc as the canonical reference (Task 9)
- Git: tag `v1` at pre-work HEAD, pushed to `origin` (Task 9)

---

### Task 1: Scaffold the document — shell, CSS, JS, Vision, Personas, Epic Overview

**Files:**
- Create: `docs/03-Sadd-Product-Backlog-User-Stories.html`

- [ ] **Step 1: Write the full file**

Create `docs/03-Sadd-Product-Backlog-User-Stories.html` with exactly this content:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Product Backlog &amp; User Stories · Sadd</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Baloo+2:wght@500;600;700;800&family=Nunito:wght@400;500;600;700;800&family=IBM+Plex+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#0d1117;
  --sidebar:#0a0e13;
  --sidebar-border:#1c2530;
  --paper:#fbfbf9;
  --ink:#1b2027;
  --ink-soft:#525a66;
  --line:#e4e2dc;
  --accent:#0D9488;
  --accent-soft:#F0FDFA;
  --accent-strong:#0F766E;
  --amber:#e2a53a;
  --red:#e0596b;
  --slate:#8a93a3;
  --mono: 'IBM Plex Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  --sans: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  --display: 'Baloo 2', var(--sans);
}
*{box-sizing:border-box;}
html{scroll-behavior:smooth;}
body{
  margin:0; font-family:var(--sans); color:var(--ink); background:var(--paper);
  font-size:16px; line-height:1.6;
}
::selection{ background:var(--accent-soft); }

#progress{
  position:fixed; top:0; left:0; height:3px; width:0%;
  background:linear-gradient(90deg,var(--accent),var(--accent-strong));
  z-index:1000; transition:width .1s linear;
}

.sidebar{
  position:fixed; top:0; left:0; bottom:0; width:300px;
  background:var(--sidebar); border-right:1px solid var(--sidebar-border);
  overflow-y:auto; padding:0 0 40px 0; z-index:100;
  scrollbar-width: thin; scrollbar-color: #2a3542 transparent;
}
.sidebar::-webkit-scrollbar{width:8px;}
.sidebar::-webkit-scrollbar-thumb{background:#2a3542; border-radius:4px;}

.brand{
  padding:22px 20px 16px 20px; border-bottom:1px solid var(--sidebar-border);
  position:sticky; top:0; background:var(--sidebar); z-index:5;
}
.brand .mark{
  display:inline-flex; align-items:center; gap:8px;
  font-family:var(--mono); font-size:11px; letter-spacing:.14em; color:var(--accent);
  text-transform:uppercase;
}
.brand .mark::before{
  content:""; width:8px; height:8px; border-radius:50%;
  background:var(--accent); box-shadow:0 0 8px var(--accent);
  display:inline-block;
}
.brand h1{
  font-family:var(--display); font-size:16px; margin:10px 0 2px 0; color:#f2f4f7; font-weight:700; line-height:1.3;
}
.brand p{ margin:0; font-size:12.5px; color:#7d8998; }

.docswitch{
  display:block; margin:14px 20px 0 20px; padding:9px 12px;
  border:1px solid var(--sidebar-border); border-radius:7px;
  color:#c7d0db; text-decoration:none; font-size:12.5px; font-family:var(--mono);
  transition:.15s; background:#0e141b;
}
.docswitch:hover{ border-color:var(--accent); color:var(--accent); }

.searchwrap{ padding:14px 20px 4px 20px; }
#search{
  width:100%; padding:9px 10px; border-radius:7px; border:1px solid var(--sidebar-border);
  background:#0e141b; color:#e7ebf0; font-size:13px; font-family:var(--sans);
  outline:none;
}
#search:focus{ border-color:var(--accent); }
#search::placeholder{ color:#5b6675; }

nav.toc{ padding:10px 10px 20px 10px; }
nav.toc ul{ list-style:none; margin:0; padding-left:0; }
nav.toc > ul { padding-left:6px; }
nav.toc ul ul{ padding-left:16px; border-left:1px solid var(--sidebar-border); margin-left:6px; }
nav.toc li{ margin:0; }
nav.toc a{
  display:block; padding:6px 10px; color:#a7b1bf; text-decoration:none;
  font-size:13px; border-radius:6px; line-height:1.35;
  border-left:2px solid transparent;
}
nav.toc > ul > li > a{ font-weight:600; color:#dbe2ea; font-size:13.5px; margin-top:6px;}
nav.toc a:hover{ background:#121a23; color:var(--accent); }
nav.toc a.active{
  background:#0f2622; color:var(--accent); border-left:2px solid var(--accent);
}
nav.toc li.hidden{ display:none; }

.wrap{ margin-left:300px; min-height:100vh; }
.topbar{
  position:sticky; top:0; z-index:50;
  background:rgba(251,251,249,.88); backdrop-filter:blur(8px);
  border-bottom:1px solid var(--line);
  padding:10px 48px; display:flex; align-items:center; justify-content:space-between;
}
.topbar .path{ font-family:var(--mono); font-size:12px; color:var(--ink-soft); }
.topbar .path b{ color:var(--ink); }
.topbar .actions a{
  font-size:12.5px; font-family:var(--mono); color:var(--accent-strong);
  text-decoration:none; margin-left:16px; border:1px solid var(--accent-soft);
  padding:5px 10px; border-radius:6px; background:var(--accent-soft);
}
.topbar .actions a:hover{ background:var(--accent); color:#fff; }

main{ max-width:900px; padding:56px 48px 120px 48px; }

.doc-header{ margin-bottom:40px; }
.kicker{
  font-family:var(--mono); font-size:12px; letter-spacing:.14em; color:var(--accent-strong);
  text-transform:uppercase; margin:0 0 14px 0; display:flex; align-items:center; gap:10px;
}
.kicker::before{ content:"//"; color:var(--slate); }
.doc-header h1{ font-family:var(--display); font-size:38px; margin:0 0 8px 0; letter-spacing:-.02em; font-weight:700; }
.doc-header .sub{ font-size:16px; color:var(--ink-soft); margin:0; }

h2{
  font-family:var(--display); font-size:24px; margin:52px 0 16px 0; padding-top:8px; font-weight:700;
  letter-spacing:-.01em; scroll-margin-top:80px; border-top:1px solid var(--line); padding-top:28px;
}
main > h2:first-of-type{ border-top:none; padding-top:0; }
h3{ font-family:var(--display); font-size:18.5px; margin:32px 0 12px 0; font-weight:700; color:#242a33; scroll-margin-top:80px; }
h4{ font-family:var(--display); font-size:15px; margin:22px 0 8px 0; font-weight:700; color:#3a414c; scroll-margin-top:80px;}
p{ margin:0 0 16px 0; color:#333a44; }
strong{ color:#151a20; }
a{ color:var(--accent-strong); }
hr{ border:none; border-top:1px solid var(--line); margin:36px 0; }

ul,ol{ margin:0 0 16px 0; padding-left:22px; color:#333a44; }
li{ margin-bottom:6px; }
li > ul, li > ol{ margin-top:6px; }

code{
  font-family:var(--mono); font-size:.86em; background:#eef0ee; color:#1b2027;
  padding:1.5px 5px; border-radius:4px;
}
code.story-id{
  background:var(--accent-soft); color:var(--accent-strong); font-weight:600;
  white-space:nowrap;
}
code.epic-id{
  background:#eee6d8; color:#8a5a13; font-weight:700;
}
pre{ background:#11151a; color:#e7ebf0; padding:16px 18px; border-radius:10px; overflow-x:auto; }
pre code{ background:none; color:inherit; padding:0; }

blockquote.revnote{
  margin:20px 0; padding:16px 20px; background:#fff8e9; border-left:3px solid var(--amber);
  border-radius:0 8px 8px 0; color:#5a4b1f; font-size:14.5px;
}
blockquote.revnote p{ margin:0; color:#5a4b1f; }
blockquote.revnote p + p{ margin-top:10px; }

.table-wrap{ overflow-x:auto; margin:20px 0 28px 0; border:1px solid var(--line); border-radius:10px; }
table{ border-collapse:collapse; width:100%; font-size:14px; }
thead th{
  text-align:left; background:#f1f0eb; color:#1b2027; font-weight:650;
  padding:10px 14px; border-bottom:1px solid var(--line); white-space:nowrap;
  position:sticky; top:0;
}
tbody td{ padding:10px 14px; border-bottom:1px solid #ecebe5; vertical-align:top; color:#3a414c; }
tbody tr:last-child td{ border-bottom:none; }
tbody tr:hover{ background:#f7f8f5; }

.badge{
  display:inline-block; font-family:var(--mono); font-size:11px; font-weight:700;
  padding:2px 7px; border-radius:5px; letter-spacing:.03em;
}
.badge-p0{ background:#fde8e8; color:#b3273c; }
.badge-p1{ background:#fdf1dc; color:#946111; }
.badge-p2{ background:#eef1f5; color:#4c5967; }

.tag{
  display:inline-block; font-family:var(--mono); font-size:10.5px; font-weight:700;
  padding:2px 7px; border-radius:5px; letter-spacing:.02em; vertical-align:2px;
}
.tag-tier{ background:#e4f8f4; color:var(--accent-strong); }
.tag-tier.advanced{ background:#e9edfb; color:#3949ab; }
.tag-tier.business{ background:#f2e9fb; color:#7b2fbd; }
.tag-src{ background:#eef1f5; color:#4c5967; }
.tag-src.sentinel{ background:#fdf1dc; color:#946111; }
.tag-src.new{ background:#fbe9f0; color:#c22367; }

#topbtn{
  position:fixed; bottom:28px; right:28px; z-index:60;
  width:42px; height:42px; border-radius:50%; background:var(--ink);
  color:#fff; border:none; cursor:pointer; opacity:0; pointer-events:none;
  transition:.2s; font-size:16px; display:flex; align-items:center; justify-content:center;
  box-shadow:0 6px 18px rgba(0,0,0,.25);
}
#topbtn.show{ opacity:1; pointer-events:auto; }
#topbtn:hover{ background:var(--accent-strong); }

@media (max-width: 880px){
  .sidebar{ transform:translateX(-100%); transition:.2s; width:82vw; }
  .sidebar.open{ transform:translateX(0); }
  .wrap{ margin-left:0; }
  main{ padding:40px 22px 100px 22px; }
  .topbar{ padding:10px 18px; }
  #menubtn{ display:inline-flex !important; }
}
#menubtn{ display:none; background:none; border:1px solid var(--line); border-radius:7px; padding:7px 10px; font-family:var(--mono); font-size:12px; cursor:pointer; }

@media print{
  .sidebar,.topbar,#topbtn,#progress{ display:none; }
  .wrap{ margin-left:0; }
  main{ max-width:none; padding:0; }
}
</style>
</head>
<body>
<div id="progress"></div>

<aside class="sidebar">
  <div class="brand">
    <span class="mark">Sadd · Product Docs</span>
    <h1>Product Backlog &amp; User Stories</h1>
    <p>Sadd Home Router</p>
  </div>
  <a class="docswitch" href="README.md">← Design Package Index</a>
  <div class="searchwrap">
    <input id="search" type="text" placeholder="Filter sections…">
  </div>
  <nav class="toc">
    <div class="toc">
<ul>
<li><a href="#1-product-vision">1. Product Vision</a></li>
<li><a href="#2-personas">2. Personas</a></li>
<li><a href="#3-epics">3. Epics</a></li>
<li><a href="#4-product-backlog-by-epic">4. Product Backlog (by Epic)</a><ul>
</ul>
</li>
</ul>
</div>

  </nav>
</aside>

<div class="wrap">
  <div class="topbar">
    <span class="path"><b>Product Backlog</b> &nbsp;/&nbsp; SADD PRODUCT DOCS · v0.2</span>
    <button id="menubtn">☰ Menu</button>
    <span class="actions"><a href="README.md">Design Package Index →</a></span>
  </div>
  <main>
    <div class="doc-header">
      <p class="kicker">SADD PRODUCT DOCS · v0.2</p>
      <h1>Product Backlog &amp; User Stories</h1>
      <p class="sub">Sadd Home Router — Simple by Default, Powerful Underneath</p>
    </div>
    <p><strong>Prepared by:</strong> Product Owner / Scrum Master &nbsp;·&nbsp; <strong>Version:</strong> v0.2 — Merge &amp; Expansion Pass</p>
    <blockquote class="revnote">
      <p><strong>Revision note (v0.2):</strong> This document merges Sadd's original product brief (<code>home-router-user-needs-analysis.md</code> Part 6) with gated-in requirements from a newly-completed Firewalla/"Sentinel" competitive research pass (<code>01-Competitive-Analysis-Firewalla.html</code>, <code>02-Product-Backlog-User-Stories.html</code>). Sadd's brand, simple-first positioning, and Simple/Advanced Mode split are unchanged and are not up for revision here — this pass adds formal Epic → User Story → Acceptance Criteria structure (which Sadd did not previously have in document form) and pulls in applicable Sentinel material, tier-gated so nothing bypasses Sadd's "simple by default" promise. The pre-merge repository state is tagged <code>v1</code> in git.</p>
      <p>Every story below carries two tags: a <strong>tier</strong> (<span class="tag tag-tier">Simple</span> <span class="tag tag-tier advanced">Advanced</span> <span class="tag tag-tier business">Business</span> — which layer of Sadd's interface it lives in) and a <strong>provenance</strong> (<span class="tag tag-src">Sadd</span> already implied/stated in Sadd's existing docs, now formalized · <span class="tag tag-src sentinel">Sentinel</span> pulled in from the new reference backlog, tier-gated · <span class="tag tag-src new">New</span> synthesized during this merge, not sourced from either existing doc).</p>
    </blockquote>
    <hr />

    <h2 id="1-product-vision">1. Product Vision</h2>
    <blockquote class="revnote">
      <p>Simple by default, powerful underneath. A router that gives a non-technical household the protection level of a prosumer setup — without ever requiring them to touch a settings menu to get it — while never walling off the advanced user who wants full control.</p>
    </blockquote>
    <p>Sadd competes by matching prosumer-grade security tools (Firewalla-class DPI, IDS/IPS, VLAN segmentation, VPN) feature-for-feature, delivered through the simplicity of eero-class onboarding, and differentiates on three things neither camp fully offers today: a true progressive-disclosure interface (Simple Mode default, Advanced Mode opt-in, never a prerequisite), free-for-life core security with no subscription required for baseline protection, and a mobile app that gives full remote access — VPN, cameras, parental controls — from anywhere, not just local Wi-Fi.</p>
    <p>Sadd is built on <strong>OpenWrt</strong> (see Epic 18), giving it a real, evidence-based "built on a router-native embedded OS" claim rather than a generic open-source marketing line — mirroring the architecture rationale confirmed in the competitive analysis (Firewalla itself runs on Ubuntu, not a router-native OS).</p>
    <hr />

    <h2 id="2-personas">2. Personas</h2>
    <p>Full persona detail (needs broken out by sub-category) lives in <code>home-router-user-needs-analysis.md</code> Part 1; this table is the condensed reference used to tag backlog stories.</p>
    <div class="table-wrap"><table>
    <thead><tr><th>Persona</th><th>Core Need</th><th>Key Requirements</th></tr></thead>
    <tbody>
    <tr><td><strong>P1 — Gamers / Tech Enthusiasts</strong></td><td>Deterministic performance — zero latency spikes, maximum control.</td><td>QoS/latency prioritization, Wi-Fi 7 MLO, multi-gig wired ports, port forwarding/VPN, detailed telemetry.</td></tr>
    <tr><td><strong>P2 — Parents / Household Admins</strong></td><td>Digital governance, safety, and operational control.</td><td>Content filtering, scheduled pauses, usage dashboards, IoT isolation, mobile-app setup, guest network.</td></tr>
    <tr><td><strong>P3 — Kids / Teens</strong></td><td>Fast, uninterrupted access — indifferent to admin/security settings.</td><td>Strong bedroom Wi-Fi, low latency, earned extra time, personal device profile, transparent limits.</td></tr>
    <tr><td><strong>P4 — Remote Workers / Enterprise-at-Home</strong></td><td>Connection stability, security compliance, clear call quality.</td><td>App-aware QoS, multi-WAN failover, VPN, guest/VLAN segmentation from corporate devices.</td></tr>
    <tr><td><strong>P5 — Streamers / Media Households</strong></td><td>High aggregate throughput for simultaneous streams.</td><td>Strong 5/6GHz throughput, MU-MIMO/OFDMA, QoS fairness under peak load.</td></tr>
    <tr><td><strong>P6 — Smart Home Enthusiasts (IoT-Heavy)</strong></td><td>High device density with seamless cross-room handoffs.</td><td>Tri-band capacity, dedicated IoT VLAN, Thread/Matter/Zigbee compatibility, mesh roaming.</td></tr>
    <tr><td><strong>P7 — Away-From-Home Users</strong></td><td>Securely reach and control the home network from anywhere.</td><td>Remote camera viewing, remote IoT control, geofencing, VPN-based remote access, DDNS.</td></tr>
    <tr><td><strong>P8 — Pet Owners</strong></td><td>Always-on, low-latency connectivity for monitoring devices.</td><td>Reliable scheduled connectivity, low-power IoT support, same remote-access needs as P7.</td></tr>
    <tr><td><strong>P9 — Non-Tech-Savvy Users / Seniors</strong></td><td>"Set it and forget it" reliability with zero maintenance.</td><td>App-guided QR setup, automated updates, self-healing network, accessible/high-contrast UI.</td></tr>
    <tr><td><strong>P10 — Privacy / Security-Conscious Users</strong></td><td>Control over what leaves the network and what the vendor does with data.</td><td>WPA3, automatic updates, threat blocking, no data harvesting, local-first option, open-firmware access.</td></tr>
    <tr><td><strong>P11 — Large / Multi-Generational Households</strong></td><td>Whole-home coverage without performance loss as user count grows.</td><td>Mesh coverage, band steering, multiple SSIDs/zones.</td></tr>
    <tr><td><strong>P12 — Roommates / Shared Housing</strong></td><td>Fair, neutral access without one person acting as network admin over others.</td><td>Flat guest-style access, per-device usage visibility, privacy between users, easy reset on move-out.</td></tr>
    <tr><td><strong>P13 — Renters / Apartment Dwellers</strong></td><td>Portability and resilience in dense, interference-prone environments.</td><td>Compact portable form factor, automatic channel management.</td></tr>
    <tr><td><strong>P14 — Multi-Property / Vacation Home Owners</strong></td><td>Monitor and control a property the owner isn't physically present at.</td><td>Network-down alerts, remote reboot, cellular failover, time-limited guest credentials.</td></tr>
    <tr><td><strong>P15 — Small Business / Home-Business Hybrid</strong></td><td>Business-grade reliability and access control on residential infrastructure.</td><td>Static IP/DDNS, multi-WAN failover, isolated POS network, guest Wi-Fi for customers, bandwidth prioritization.</td></tr>
    <tr><td><strong>P16 — <span class="tag tag-src new">New</span> Compliance-Conscious Carl</strong></td><td>Explicitly checks country-of-origin and supply-chain documentation before purchasing, post-FCC Covered List rule.</td><td>Clear "designed/made in USA" or equivalent claim, visible HBOM/SBOM or trust signal, confidence in continued legal sellability.</td></tr>
    </tbody>
    </table></div>
    <hr />

    <h2 id="3-epics">3. Epics</h2>
    <div class="table-wrap"><table>
    <thead><tr><th>ID</th><th>Epic</th><th>Rationale &amp; Provenance</th></tr></thead>
    <tbody>
    <tr><td><code class="epic-id">E1</code></td><td>Onboarding &amp; Setup</td><td>Sadd's existing MVP onboarding, formalized; adds passkey auth, multi-user pairing, and local-web-UI-as-escape-hatch from Sentinel. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E2</code></td><td>Core Threat Protection (DPI / IDS / IPS)</td><td>Formalizes Sadd's existing Security section using Sentinel's DPI/IDS/IPS breakdown; Simple = defaults on, Advanced = rule/threshold tuning. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E3</code></td><td>Network Segmentation &amp; Zero Trust</td><td>Sadd's Kids/Guest/Smart-Home zone presets (Simple) plus Sentinel's full VLAN/microsegmentation/Zero-Trust material (Advanced) — already named as a V2 target in Sadd's own brief. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E4</code></td><td>Transparency &amp; Explainability</td><td>New formal epic built from Sentinel's "why was this blocked" material, matched against Sadd's own stated differentiator language. <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E5</code></td><td>Parental Controls &amp; Content Filtering</td><td>Sadd's flagship epic, enriched with Sentinel's symmetric allow/block scheduling and SafeSearch specifics. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E6</code></td><td>VPN &amp; Remote Access</td><td>Sadd's one-tap VPN (Simple) plus Sentinel's OpenVPN alternative, per-device client routing, site-to-site, and AmneziaWG (Advanced/optional). <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E7</code></td><td>Wi-Fi Integration</td><td>Sadd's integrated-Wi-Fi assumption plus Sentinel's mesh AP accessory and Wi-Fi 7 driver-maturity risk flag. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E8</code></td><td>Ad &amp; Tracker Blocking</td><td>Sadd's ad-block-by-default plus Sentinel's custom blocklist import and whitelist-broken-site flow (Advanced). <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E9</code></td><td>Reliability &amp; Multi-WAN</td><td>Formalizes Sadd's V2 multi-WAN mention with Sentinel's failover/load-balancing/diagnostics/uptime-target stories. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E10</code></td><td>Mobile App &amp; Dashboard</td><td>Sadd's core hub plus Sentinel's tablet layout, home-screen widget, and symmetric-scheduling UI. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E11</code></td><td>Privacy &amp; Data Handling</td><td>Resolves Sadd's own open product question (§6.6, "data privacy stance") using Sentinel's local-first-default/retention/deletion structure. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E12</code></td><td>Developer &amp; Power-User Extensibility</td><td>Sadd's V2 API/webhook mention plus Sentinel's Docker/SSH/open-firmware/opkg material, gated to Advanced/Developer tier. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E13</code></td><td>Fleet &amp; Small-Business Mode</td><td>Sadd's existing Persona 15 plus Sentinel's MSP-style console/API/compliance-report material, gated to an explicit optional Business tier. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E14</code></td><td>Trust, Disclosure &amp; Vulnerability Management</td><td>New epic: public CVE/advisory page, disclosed responsible-disclosure policy, no shared/fixed SSH backdoor, incident-response playbook. <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E15</code></td><td>Regulatory Compliance &amp; Manufacturing</td><td>New epic: manufacturing-origin disclosure, HBOM/SBOM, compliance statement — business/legal work with one real UI touchpoint. <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E16</code></td><td>Beginner-First Education &amp; Onboarding Content</td><td>New epic, strongly aligned with Sadd's core mission: glossary/primer, two-path wizard branch, video walkthroughs, accessibility path. <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E17</code></td><td>Hardware &amp; Pricing</td><td>Sadd's open hardware-tier question plus Sentinel's simple-SKU-ladder and Pricing Promise/no-retroactive-paywall commitments. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    <tr><td><code class="epic-id">E18</code></td><td>OpenWrt Platform Foundation</td><td>Formalizes what <code>sadd-openwrt-mapping.md</code> already assumes, using Sentinel's version/target-lock, GPL-boundary, sysupgrade OTA, LuCI-based Advanced Mode web UI, and package-manifest stories. <span class="tag tag-src">Sadd</span> + <span class="tag tag-src sentinel">Sentinel</span></td></tr>
    </tbody>
    </table></div>
    <hr />

    <h2 id="4-product-backlog-by-epic">4. Product Backlog (by Epic)</h2>
    <p>Format: <strong>US-#.#</strong> — As a [persona], I want [capability], so that [benefit].
    Tier: <span class="tag tag-tier">Simple</span> <span class="tag tag-tier advanced">Advanced</span> <span class="tag tag-tier business">Business</span> — which layer of Sadd's interface this lives in.
    Provenance: <span class="tag tag-src">Sadd</span> <span class="tag tag-src sentinel">Sentinel</span> <span class="tag tag-src new">New</span> — see Section 3.
    Priority: <strong>P0</strong> (MVP-blocking) / <strong>P1</strong> (fast-follow) / <strong>P2</strong> (roadmap) — MoSCoW-style.
    Estimate: Story points (Fibonacci: 1,2,3,5,8,13).</p>

  </main>
</div>

<button id="topbtn" title="Back to top">↑</button>
<script>
const links = [...document.querySelectorAll('nav.toc a')];
const targets = links.map(a => document.querySelector(a.getAttribute('href'))).filter(Boolean);
function onScroll(){
  let idx = 0;
  const y = window.scrollY + 100;
  targets.forEach((t,i) => { if (t && t.offsetTop <= y) idx = i; });
  links.forEach(l => l.classList.remove('active'));
  if (links[idx]) links[idx].classList.add('active');

  const h = document.documentElement;
  const scrolled = (h.scrollTop) / (h.scrollHeight - h.clientHeight) * 100;
  document.getElementById('progress').style.width = scrolled + '%';

  document.getElementById('topbtn').classList.toggle('show', window.scrollY > 600);
}
document.addEventListener('scroll', onScroll, {passive:true});
onScroll();

document.getElementById('topbtn').addEventListener('click', () => window.scrollTo({top:0, behavior:'smooth'}));

const search = document.getElementById('search');
search.addEventListener('input', () => {
  const q = search.value.trim().toLowerCase();
  document.querySelectorAll('nav.toc li').forEach(li => {
    const a = li.querySelector(':scope > a');
    if (!a) return;
    const text = a.textContent.toLowerCase();
    const childMatch = [...li.querySelectorAll('a')].some(x => x.textContent.toLowerCase().includes(q));
    li.classList.toggle('hidden', q.length > 0 && !text.includes(q) && !childMatch);
  });
});

const menubtn = document.getElementById('menubtn');
const sidebar = document.querySelector('.sidebar');
if (menubtn){
  menubtn.addEventListener('click', () => sidebar.classList.toggle('open'));
  document.addEventListener('click', (e) => {
    if (sidebar.classList.contains('open') && !sidebar.contains(e.target) && e.target !== menubtn){
      sidebar.classList.remove('open');
    }
  });
}

document.querySelectorAll('nav.toc a').forEach(a=>{
  a.addEventListener('click', () => { if(sidebar.classList.contains('open')) sidebar.classList.remove('open'); });
});
</script>
</body>
</html>
```

- [ ] **Step 2: Verify**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -c "<h2 id=\"4-product-backlog-by-epic\">" docs/03-Sadd-Product-Backlog-User-Stories.html
grep -c "</main>" docs/03-Sadd-Product-Backlog-User-Stories.html
```
Expected: both `1`. Open the file in a browser (`start docs/03-Sadd-Product-Backlog-User-Stories.html` on Windows) and confirm the sidebar, search box, and section 1–4 headers render without console errors.

- [ ] **Step 3: Commit**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add docs/03-Sadd-Product-Backlog-User-Stories.html && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: scaffold Sadd Product Backlog & User Stories v0.2 (shell, Vision, Personas, Epics)"
```

---

## Boundary-anchoring pattern used by Tasks 2–8 (read once, applies to all of them)

Every epic-content task inserts **TOC entries** and **body sections** using `Edit` with `old_string`/`new_string`, anchored on the file's stable closing-tag sequences so the match stays unique no matter what earlier tasks already inserted (same technique used successfully in the mobile-app plan):

- **TOC insertion boundary** (insert new `<li>` entries for epics just before this, keep the tail intact in `new_string`):
```
</ul>
</li>
</ul>
</div>

  </nav>
</aside>
```

- **Body insertion boundary** (insert new `<h3>`/table sections just before this, keep the tail intact in `new_string`):
```
  </main>
</div>

<button id="topbtn"
```

Each task's `new_string` = [new content] + [the exact boundary tail shown above], so the next task can match the same tail again.

---

### Task 2: Epics 1–3 — Onboarding & Setup, Core Threat Protection, Network Segmentation & Zero Trust

**Files:** Modify `docs/03-Sadd-Product-Backlog-User-Stories.html`

**TOC insert** (use the TOC boundary above):
```html
<li><a href="#epic-1-onboarding-setup">Epic 1 — Onboarding &amp; Setup</a></li>
<li><a href="#epic-2-core-threat-protection">Epic 2 — Core Threat Protection (DPI / IDS / IPS)</a></li>
<li><a href="#epic-3-network-segmentation-zero-trust">Epic 3 — Network Segmentation &amp; Zero Trust</a></li>
</ul>
</li>
</ul>
</div>

  </nav>
</aside>
```

**Body content brief** (use the body boundary above; write `<h3 id="epic-N-...">Epic N — Title</h3>` followed by one `<div class="table-wrap"><table>` per epic with the standard columns: ID / Story / Acceptance Criteria / Tier / Provenance / Priority / Points):

- **Epic 1 — Onboarding & Setup [Simple unless noted]:** Formalize Sadd's existing onboarding (`home-router-user-needs-analysis.md` §6.3.A — mobile-app-first setup, QR pairing, auto-detect ISP topology, guided household setup flow: add family → assign devices → pick protection level) into 3–4 `[Sadd]` P0 stories. Pull in from Sentinel (`02-Product-Backlog-User-Stories.html` Epic 1): `US-1.5` (static IP + local web UI, `[Advanced]`), `US-1.6` (multi-user pairing, `[Simple]`), `US-1.7` (passkey auth, `[Simple]`). Do not pull Sentinel's `US-1.1`–`US-1.4` verbatim — they largely duplicate Sadd's own onboarding stories; merge overlapping acceptance criteria into the `[Sadd]` versions instead of creating near-duplicate rows, citing both provenances on the merged story (e.g. `[Sadd] + [Sentinel]`).

- **Epic 2 — Core Threat Protection (DPI/IDS/IPS):** Formalize Sadd's existing Security section (§6.3.E — network-wide ad block, automatic threat/malware blocking, automatic firmware updates, IoT auto-isolation) as `[Simple]` P0 defaults-on stories, `[Sadd]`. Pull in from Sentinel Epic 2 (gated `[Advanced]` unless noted): `US-2.2` (real-time IDS push alerts — keep `[Simple]`, this is a notification not a config surface), `US-2.3` (auto-block/IPS toggle — `[Simple]` default-on, `[Advanced]` per-rule tuning), `US-2.4` (geo-IP filtering, `[Advanced]`), `US-2.5` (open-port scanning, `[Advanced]`), `US-2.6` (new-device quarantine — merge with Sadd's existing "IoT auto-isolation" into one `[Sadd] + [Sentinel]` `[Simple]` P0 story). Exclude `US-2.1`'s literal DPI-engine-integration framing (that's OpenWrt/engineering detail — route it into Epic 18 instead as a platform story, not a user story).

- **Epic 3 — Network Segmentation & Zero Trust:** Formalize Sadd's existing Kids/Guests/Smart-Home auto-zone presets (§6.2 table, §6.3) as `[Simple]` P0, `[Sadd]`. Pull in from Sentinel Epic 3, gated `[Advanced]`: `US-3.3` (device microsegmentation), `US-3.5` (Zero Trust allow-list rules), `US-3.6` (MAC-randomization-tolerant device identification — this one stays cross-tier: detection logic is invisible platform work but the *no-false-"new-device"-flag* outcome is `[Simple]`-visible; write it as `[Simple] + [Advanced]` and note the underlying fingerprinting is genuinely hard R&D per Sentinel's own INVEST-split note). `US-3.4` (guest network + QR sharing) should already be covered by Epic 1/7 — do not duplicate; cross-reference instead.

Give each story a `US-1.x` / `US-2.x` / `US-3.x` ID. One fully-worked example (Epic 1, follow this exact row format for every story in every task):

```html
<h3 id="epic-1-onboarding-setup">Epic 1 — Onboarding &amp; Setup</h3>
<div class="table-wrap"><table>
<thead><tr><th>ID</th><th>Story</th><th>Acceptance Criteria</th><th>Tier</th><th>Src</th><th>Pri</th><th>Pts</th></tr></thead>
<tbody>
<tr><td><code class="story-id">US-1.1</code></td><td>As a non-technical parent, I want to set up my router in under 10 minutes using only my phone, so that I don't need technical help.</td><td>App detects the router via QR/Bluetooth; guided wizard completes Wi-Fi, admin password, and basic security defaults in 6 or fewer screens; success confirmation shown.</td><td><span class="tag tag-tier">Simple</span></td><td><span class="tag tag-src">Sadd</span></td><td><span class="badge badge-p0">P0</span></td><td>8</td></tr>
</tbody>
</table></div>
```

- [ ] **Step 1: Verify current state** — `grep -c "epic-3-network-segmentation-zero-trust" docs/03-Sadd-Product-Backlog-User-Stories.html` → expect `0` before this task's edit.
- [ ] **Step 2: Apply the TOC and body edits** as described above.
- [ ] **Step 3: Verify** — `grep -c "epic-3-network-segmentation-zero-trust" docs/03-Sadd-Product-Backlog-User-Stories.html` → expect `2` (one TOC link, one heading id). Confirm every `<tr>` has exactly one Tier tag and one Src tag.
- [ ] **Step 4: Commit** — `git add docs/03-Sadd-Product-Backlog-User-Stories.html && git commit -m "docs: add Epics 1-3 (Onboarding, Core Threat Protection, Segmentation) to Sadd backlog v0.2"` (with the standard `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env vars from Task 1).

---

### Task 3: Epics 4–6 — Transparency & Explainability, Parental Controls & Content Filtering, VPN & Remote Access

**Files:** Modify `docs/03-Sadd-Product-Backlog-User-Stories.html`

**TOC insert:**
```html
<li><a href="#epic-4-transparency-explainability">Epic 4 — Transparency &amp; Explainability</a></li>
<li><a href="#epic-5-parental-controls-content-filtering">Epic 5 — Parental Controls &amp; Content Filtering</a></li>
<li><a href="#epic-6-vpn-remote-access">Epic 6 — VPN &amp; Remote Access</a></li>
</ul>
</li>
</ul>
</div>

  </nav>
</aside>
```

**Body content brief:**

- **Epic 4 — Transparency & Explainability:** Entirely new formal epic (`[Sentinel]` provenance, `[Simple]` tier for the core explainer, `[Advanced]` for log search/filter), built from Sentinel Epic 4 (`US-4.1` plain-English block explanation, `US-4.2` local log retention ≥30 days no forced cloud, `US-4.3` filterable logs `[Advanced]`, `US-4.4` one-tap "allow" override for false positives, `US-4.5` weekly plain-language "Network Health" summary). Adapt acceptance criteria to Sadd's plain-language voice (e.g., avoid "rule triggered" jargon in `[Simple]`-tier acceptance criteria — say what the user sees, not the underlying mechanism). All P0 except `US-4.3`/`US-4.5` which are P1.

- **Epic 5 — Parental Controls & Content Filtering:** Sadd's flagship — formalize §6.3.D (per-child profiles with age-based presets, named app blocking, screen-time scheduling with plain presets "School night/Weekend/Bedtime", pause-internet button, reward-time mechanic) as `[Simple]` P0 `[Sadd]` stories. Pull in from Sentinel Epic 5: `US-5.2` (SafeSearch enforcement across search/video platforms — `[Simple]` P0), `US-5.5` (assign rules to a person across multiple devices — `[Simple]` P1, matches Sadd's "personal device profile" persona need), Sentinel's Epic 10 `US-10.7` (symmetric allow/block scheduling — place it here, not in Epic 10, since it's a parental-control capability; `[Simple]` P0, `[Sadd] + [Sentinel]` since it resolves a gap in Sadd's own bedtime-schedule story).

- **Epic 6 — VPN & Remote Access:** Formalize Sadd's §6.3.C one-tap VPN (auto-provision WireGuard, automatic DDNS, family "invite" link, remote access covers home devices + cameras + IoT as one connection) as `[Simple]` P0 `[Sadd]`. Pull in from Sentinel Epic 6, gated `[Advanced]`: `US-6.2` (OpenVPN alternative), `US-6.3` (per-device VPN client routing through a third-party provider), `US-6.4` (site-to-site VPN — matches Sadd's own V2 mention for Persona 14/15), `US-6.6` (AmneziaWG censorship-resistant protocol, P2). Keep Sentinel's `US-6.5` throughput target (≥300 Mbps WireGuard on flagship tier) as `[Advanced]`-visible but P0-priority (it's a hardware/QA commitment, not a UI surface).

Row format is identical to Task 2's worked example (same table columns, same tag classes). IDs: `US-4.x`, `US-5.x`, `US-6.x`.

- [ ] **Step 1: Verify current state** — `grep -c "epic-6-vpn-remote-access" docs/03-Sadd-Product-Backlog-User-Stories.html` → expect `0`.
- [ ] **Step 2: Apply the TOC and body edits.**
- [ ] **Step 3: Verify** — same grep → expect `2`.
- [ ] **Step 4: Commit** — `"docs: add Epics 4-6 (Transparency, Parental Controls, VPN) to Sadd backlog v0.2"`.

---

### Task 4: Epics 7–9 — Wi-Fi Integration, Ad & Tracker Blocking, Reliability & Multi-WAN

**Files:** Modify `docs/03-Sadd-Product-Backlog-User-Stories.html`

**TOC insert:**
```html
<li><a href="#epic-7-wi-fi-integration">Epic 7 — Wi-Fi Integration</a></li>
<li><a href="#epic-8-ad-tracker-blocking">Epic 8 — Ad &amp; Tracker Blocking</a></li>
<li><a href="#epic-9-reliability-multi-wan">Epic 9 — Reliability &amp; Multi-WAN</a></li>
</ul>
</li>
</ul>
</div>

  </nav>
</aside>
```

**Body content brief:**

- **Epic 7 — Wi-Fi Integration:** Sadd already assumes integrated Wi-Fi (implicit throughout the product brief and the OpenWrt mapping doc) — formalize as one `[Simple]` P0 `[Sadd]` story ("router ships with working Wi-Fi out of the box, no separate AP purchase needed"). Pull in from Sentinel Epic 7: `US-7.2` (mesh-compatible satellite AP accessory, `[Advanced]` P1), `US-7.3` (QR-code guest Wi-Fi sharing — merge into Epic 1's onboarding or Epic 3's guest-zone story rather than duplicating; cross-reference), `US-7.4` (Wi-Fi walk-test/heatmap tool, `[Advanced]` P2). Carry over Sentinel's `US-7.1` risk flag verbatim as a callout (not a story row) — mainline OpenWrt/mac80211 driver maturity for Wi-Fi 7 silicon is still maturing; do not commit a launch date until a hardware/driver spike confirms a viable chipset. This risk flag also belongs in Section 9 (Open Risks) — add it there too in Task 8.

- **Epic 8 — Ad & Tracker Blocking:** Formalize Sadd's ad-block-by-default (§6.3.E) as `[Simple]` P0 `[Sadd]`. Pull in from Sentinel Epic 8: `US-8.2` (unlimited custom blocklist import, `[Advanced]` P1), `US-8.3` (one-tap "report broken site" → auto-whitelist, `[Simple]` P0 — this is a Simple-tier self-service flow even though the underlying blocklist mechanism is Advanced).

- **Epic 9 — Reliability & Multi-WAN:** Sadd's V2 brief only mentions multi-WAN failover in passing (§6.4) — formalize using Sentinel Epic 9 as the primary source, gated: `US-9.1` (automatic failover, `[Advanced]` P1 — most homes don't have a second WAN, so this isn't `[Simple]`-default, but the *toggle* to enable it should be simple once a second connection exists), `US-9.2` (load balancing, `[Advanced]` P2), `US-9.3` (stable WAN / no random disconnects / watchdog restart, `[Simple]` P0 — this is a baseline reliability expectation, not a power-user feature, `[Sadd] + [Sentinel]`), `US-9.4` (in-app plain-language WAN diagnostics — "why did my internet drop" — `[Simple]` P0, ties directly to Epic 4's transparency principle, cross-reference it).

- [ ] **Step 1: Verify current state** — `grep -c "epic-9-reliability-multi-wan"` → expect `0`.
- [ ] **Step 2: Apply the TOC and body edits.**
- [ ] **Step 3: Verify** — same grep → expect `2`.
- [ ] **Step 4: Commit** — `"docs: add Epics 7-9 (Wi-Fi, Ad Blocking, Reliability/Multi-WAN) to Sadd backlog v0.2"`.

---

### Task 5: Epics 10–12 — Mobile App & Dashboard, Privacy & Data Handling, Developer & Power-User Extensibility

**Files:** Modify `docs/03-Sadd-Product-Backlog-User-Stories.html`

**TOC insert:**
```html
<li><a href="#epic-10-mobile-app-dashboard">Epic 10 — Mobile App &amp; Dashboard</a></li>
<li><a href="#epic-11-privacy-data-handling">Epic 11 — Privacy &amp; Data Handling</a></li>
<li><a href="#epic-12-developer-power-user-extensibility">Epic 12 — Developer &amp; Power-User Extensibility</a></li>
</ul>
</li>
</ul>
</div>

  </nav>
</aside>
```

**Body content brief:**

- **Epic 10 — Mobile App & Dashboard:** Formalize Sadd's §6.3.B core hub (single app for local + remote management, home dashboard showing who's online/what's blocked/alerts, push notifications) as `[Simple]` P0 `[Sadd]`. Pull in from Sentinel Epic 10: `US-10.2` (rename/group devices, `[Simple]` P0), `US-10.6` (native tablet layout, `[Simple]` P1 — matches Sadd's own mobile-app-first identity, tablets are still consumer devices, not an Advanced-tier concern), `US-10.8` (home-screen widget, `[Simple]` P2). Note: symmetric scheduling (`US-10.7`) was already placed in Epic 5 — do not duplicate here, cross-reference.

- **Epic 11 — Privacy & Data Handling:** This epic directly answers Sadd's own open product question from `home-router-user-needs-analysis.md` §6.6 ("Data privacy stance: fully local-first with optional cloud vs. cloud-required") — state the resolution explicitly in the epic's intro text: *local-first is the answer, formalized here.* Pull in from Sentinel Epic 13: `US-13.1` (local-only traffic inspection by default, opt-in cloud sync with clear consent, `[Simple]` P0, `[Sadd] + [Sentinel]`), `US-13.2` (configurable local retention 7/30/90 days, cloud opt-in only, `[Simple]` P0), `US-13.3` (self-service account/data deletion within 30 days, `[Simple]` P1). This epic is cross-cutting — note in the epic intro that it constrains every other epic's cloud/telemetry design, not just its own stories.

- **Epic 12 — Developer & Power-User Extensibility:** Formalize Sadd's V2 API/webhook mention (§6.4, ties to Persona 1/4/10's "run own DNS/VPN or open-source firmware" need) plus Sentinel Epic 12, all gated `[Advanced]`/Developer-tier, `P2` unless noted: `US-12.1` (Docker container support with resource limits), `US-12.2` (SSH access, key-based auth only, disabled by default — cross-reference Epic 14's no-backdoor requirement), `US-12.3` (open-source firmware repo — `[Advanced]` but `P1`, this is a trust signal not just a power-user feature), `US-12.4` (public roadmap/changelog, `P1`), `US-12.5` (opkg/apk package manager access, documented "unsupported, at your own risk").

- [ ] **Step 1: Verify current state** — `grep -c "epic-12-developer-power-user-extensibility"` → expect `0`.
- [ ] **Step 2: Apply the TOC and body edits.**
- [ ] **Step 3: Verify** — same grep → expect `2`.
- [ ] **Step 4: Commit** — `"docs: add Epics 10-12 (Mobile App, Privacy, Developer Extensibility) to Sadd backlog v0.2"`.

---

### Task 6: Epics 13–15 — Fleet & Small-Business Mode, Trust/Disclosure & Vulnerability Management, Regulatory Compliance & Manufacturing

**Files:** Modify `docs/03-Sadd-Product-Backlog-User-Stories.html`

**TOC insert:**
```html
<li><a href="#epic-13-fleet-small-business-mode">Epic 13 — Fleet &amp; Small-Business Mode</a></li>
<li><a href="#epic-14-trust-disclosure-vulnerability-management">Epic 14 — Trust, Disclosure &amp; Vulnerability Management</a></li>
<li><a href="#epic-15-regulatory-compliance-manufacturing">Epic 15 — Regulatory Compliance &amp; Manufacturing</a></li>
</ul>
</li>
</ul>
</div>

  </nav>
</aside>
```

**Body content brief:**

- **Epic 13 — Fleet & Small-Business Mode:** State explicitly in the epic intro: *this entire epic is gated `[Business]` tier — it is not part of Sadd's default consumer experience and must never surface in Simple or Advanced Mode for a household user.* Ties to Persona 15. Pull in from Sentinel Epic 11: `US-11.1` (multi-box web console, `P2`), `US-11.2` (documented REST API with token auth, `P2`), `US-11.3` (compliance-friendly exportable reports, `P2`).

- **Epic 14 — Trust, Disclosure & Vulnerability Management:** New epic, `[Sentinel]` provenance. Pull in from Sentinel Epic 16 in full, all `P0` except `US-16.4`/`US-16.6` (`P1`): `US-16.1` (public CVE/advisory page), `US-16.2` (responsible-disclosure/bug-bounty policy), `US-16.3` (no shared/fixed SSH backdoor — cross-reference Epic 12's SSH story, this is the security *requirement*, Epic 12's is the *feature toggle*), `US-16.4` (incident-response playbook + push guidance during active industry-wide incidents), `US-16.5` (on-device vulnerability scan results, no transmission without opt-in — cross-reference Epic 11 Privacy), `US-16.6` (upstream OpenWrt security-advisory tracking SLA — cross-reference Epic 18). These are mostly invisible-to-Simple-Mode trust commitments — tag them `[Advanced]` where there's an actual settings surface (e.g. `US-16.3`'s SSH toggle) and `[Business]`/no-tier (public-page/process commitments, not in-app UI) where there isn't; note this explicitly per row rather than forcing every row into `[Simple]`.

- **Epic 15 — Regulatory Compliance & Manufacturing:** New epic, `[Sentinel]` provenance, scoped as business/legal work per the design spec. Pull in from Sentinel Epic 15: `US-15.1` (manufacturing-origin disclosure — this one has a real UI touchpoint, an in-app "About" screen disclosure, so tag it `[Simple]` even though the epic is otherwise business/legal), `US-15.2` (HBOM/SBOM maintained per release, no UI surface, tag with no tier / process-only), `US-15.3` (legal Covered-List clearance before hardware tooling — Sprint-0-style gate, process-only), `US-15.4` (plain-language supply-chain statement published with the Pricing Promise — cross-reference Epic 17).

- [ ] **Step 1: Verify current state** — `grep -c "epic-15-regulatory-compliance-manufacturing"` → expect `0`.
- [ ] **Step 2: Apply the TOC and body edits.**
- [ ] **Step 3: Verify** — same grep → expect `2`.
- [ ] **Step 4: Commit** — `"docs: add Epics 13-15 (Fleet/Business, Trust & Disclosure, Regulatory Compliance) to Sadd backlog v0.2"`.

---

### Task 7: Epics 16–18 — Beginner-First Education & Onboarding Content, Hardware & Pricing, OpenWrt Platform Foundation

**Files:** Modify `docs/03-Sadd-Product-Backlog-User-Stories.html`

**TOC insert:**
```html
<li><a href="#epic-16-beginner-first-education-onboarding-content">Epic 16 — Beginner-First Education &amp; Onboarding Content</a></li>
<li><a href="#epic-17-hardware-pricing">Epic 17 — Hardware &amp; Pricing</a></li>
<li><a href="#epic-18-openwrt-platform-foundation">Epic 18 — OpenWrt Platform Foundation</a></li>
</ul>
</li>
</ul>
</div>

  </nav>
</aside>
```

**Body content brief:**

- **Epic 16 — Beginner-First Education & Onboarding Content:** New epic, `[Sentinel]` provenance, but note in the intro this is *unusually well-aligned* with Sadd's founding mission (§6.1 positioning statement is essentially this epic already). Pull in from Sentinel Epic 17, all `[Simple]`: `US-17.1` (in-app plain-language glossary/primer, tap/tooltip-linked, `P0`), `US-17.2` (distinct "I'm new to this" vs. "I know networking" onboarding branch, `P0` — note this could be read as in tension with Sadd's "never require touching a settings menu" principle; resolve by framing both paths as still fully-guided, just different pacing/depth, not a gate that blocks simple users), `US-17.4` (short video walkthroughs embedded at point-of-use, `P1`), `US-17.5` (accessibility: local-web-UI-without-smartphone path, screen-reader support, WCAG 2.1 AA audit — `P1`, split into 2-3 sub-stories the way Sentinel's own INVEST audit did, since this bundles distinct workstreams), `US-17.6` (clear documentation that hardware tiers differ in throughput not security — place in Epic 17 instead, cross-reference here).

- **Epic 17 — Hardware & Pricing:** Formalize Sadd's own open question (§6.6, "Hardware tier: single router vs. mesh-first") as an explicit story requiring resolution before launch, `[Business]`/process, `P0`. Pull in from Sentinel Epic 14 + the pricing-trust stories originally grouped under Sentinel's Epic 13: `US-14.1` (simple 3-tier SKU lineup, plain-language names, `P0`), `US-14.2` ("which model do I need" quiz, `[Simple]` P1), `US-14.3` (no subscription required for core protection — `[Sadd] + [Sentinel]`, `P0`, this is Sadd's own §6.3.F promise, formalize it here), `US-13.4`-equivalent (public dated Pricing Promise page — free-forever vs. optional/paid, `P0`), `US-13.5`-equivalent (new paid tiers must be strictly additive, governance policy not engineering, `P0`). Also place Sentinel's `US-17.6` (tiers differ in speed not security) here as the natural home for that story.

- **Epic 18 — OpenWrt Platform Foundation:** Formalize what `sadd-openwrt-mapping.md` already assumes (the 🟢/🟡/🔴 native/agent/cloud legend, the on-router-agent-daemon concept) into explicit stories, `[Sadd] + [Sentinel]` provenance, process/no-tier (engineering foundation, not a user-facing surface) unless noted. Pull in from Sentinel Epic 18 in full: `US-18.1` (OpenWrt version/hardware-target lock, `P0`), `US-18.2` (GPL-boundary ADR, `P0`), `US-18.3` (sysupgrade-based fail-safe OTA, `P0`), `US-18.4` (LuCI-themed local web UI — this directly satisfies Sadd's own Epic 1 `US-1.5`/Epic 10 local-web-UI stories; cross-reference explicitly, tag `[Advanced]` since it IS the Advanced Mode web surface, `P1`), `US-18.5` (curated/tested opkg package manifest, `P0`), `US-18.6` (public "Built on OpenWrt" trust page, cross-reference Epic 14/17, `P1`). Also fold in the on-router-agent-daemon concept from `sadd-openwrt-mapping.md` as one additional `[NEW]` `P0` story: the custom agent daemon that translates simple app actions into UCI/firewall/dnsmasq changes, since this is Sadd-specific engineering not present in Sentinel's backlog at all.

- [ ] **Step 1: Verify current state** — `grep -c "epic-18-openwrt-platform-foundation"` → expect `0`.
- [ ] **Step 2: Apply the TOC and body edits.**
- [ ] **Step 3: Verify** — same grep → expect `2`. Also run: `grep -oE 'id="epic-[0-9]+-' docs/03-Sadd-Product-Backlog-User-Stories.html | sort -u | wc -l` → expect `18` (confirms all 18 epic sections now exist with no duplicate/missing IDs).
- [ ] **Step 4: Commit** — `"docs: add Epics 16-18 (Education, Hardware/Pricing, OpenWrt Foundation) to Sadd backlog v0.2"`.

---

### Task 8: Release Roadmap, DoR/DoD, Backlog Health Snapshot, Change Log

**Files:** Modify `docs/03-Sadd-Product-Backlog-User-Stories.html`

- [ ] **Step 1: Compute the actual backlog counts** (do this first — the Health Snapshot table must reflect real numbers, not estimates, mirroring the self-correction theme in Sentinel's own v6 revision note):

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -oE '<code class="story-id">US-[0-9]+\.[0-9]+</code>' docs/03-Sadd-Product-Backlog-User-Stories.html | sort -u | wc -l
grep -o 'badge-p0">P0' docs/03-Sadd-Product-Backlog-User-Stories.html | wc -l
grep -o 'badge-p1">P1' docs/03-Sadd-Product-Backlog-User-Stories.html | wc -l
grep -o 'badge-p2">P2' docs/03-Sadd-Product-Backlog-User-Stories.html | wc -l
```
Use these real counts in Step 3's Health Snapshot table — do not estimate.

- [ ] **Step 2: TOC insert** (use the TOC boundary; this is the LAST TOC edit — it also closes out the outer list):

```html
</ul>
</li>
<li><a href="#5-release-roadmap">5. Release Roadmap</a></li>
<li><a href="#6-definition-of-ready">6. Definition of Ready (DoR)</a></li>
<li><a href="#7-definition-of-done">7. Definition of Done (DoD)</a></li>
<li><a href="#8-backlog-health-snapshot">8. Backlog Health Snapshot</a></li>
<li><a href="#9-open-risks">9. Open Risks</a></li>
<li><a href="#10-change-log">10. Change Log</a></li>
</ul>
</div>

  </nav>
</aside>
```

- [ ] **Step 3: Body content** (use the body boundary; write these sections in full — this content IS literal, write it as given, filling in the real counts from Step 1):

```html
    <h2 id="5-release-roadmap">5. Release Roadmap</h2>
    <p>Roadmap phases follow Sadd's own MVP/V2 split from <code>home-router-user-needs-analysis.md</code> §6.3/§6.4, now expressed against the full epic list above.</p>
    <h3 id="mvp-release-10">MVP / Release 1.0 — "Simple, Safe, and Trusted"</h3>
    <p>All P0 stories from Epics 1–11 (onboarding through privacy) — Sadd's core promise: dead-simple setup, real prosumer-grade protection on by default, plain-English transparency, no subscription for core security. Plus the P0 platform-foundation work from Epic 18 (version lock, GPL boundary, OTA, package manifest) and the Epic 15 compliance gate if Sadd ships its own hardware.</p>
    <h3 id="release-11">Release 1.1 — "Power & Reliability"</h3>
    <p>Remaining P1 stories: Advanced Mode depth across Epics 2/3/6/9/10, Epic 16's video walkthroughs and accessibility audit, Epic 18's LuCI-based Advanced Mode web UI, Epic 14's incident-response playbook and upstream-tracking SLA.</p>
    <h3 id="release-20">Release 2.0 — "Scale & Extensibility"</h3>
    <p>Epic 13 (Fleet/Business tier) in full, Epic 12's remaining P2 developer stories, Epic 6's site-to-site VPN and AmneziaWG, Epic 9's load balancing.</p>
    <hr />

    <h2 id="6-definition-of-ready">6. Definition of Ready (DoR)</h2>
    <p>A story is ready for sprint planning when it has: a clear persona and benefit statement; acceptance criteria written in checklist or Given/When/Then form; a tier tag and a provenance tag; no open UX/design dependencies; estimated by the team, not just the PO.</p>

    <h2 id="7-definition-of-done">7. Definition of Done (DoD)</h2>
    <p>A story is done when: acceptance criteria pass in QA on all supported hardware tiers; a <strong>Simple-tier story reads in plain language with zero exposed jargon</strong> (ties to Epic 4's transparency principle — this is Sadd's non-negotiable bar, not a nice-to-have); Advanced/Business-tier stories are reachable only through their designated escape hatch, never surfaced by default; telemetry/logging respects Epic 11's local-first defaults; documentation published; no P0/P1 bugs open against the feature.</p>
    <hr />

    <h2 id="8-backlog-health-snapshot">8. Backlog Health Snapshot</h2>
    <div class="table-wrap"><table>
    <thead><tr><th>Metric</th><th>Value</th></tr></thead>
    <tbody>
    <tr><td>Total epics</td><td><strong>18</strong></td></tr>
    <tr><td>Total user stories</td><td><strong>[INSERT REAL COUNT FROM STEP 1]</strong></td></tr>
    <tr><td>P0 (MVP-blocking) stories</td><td><strong>[INSERT REAL COUNT]</strong></td></tr>
    <tr><td>P1 (fast-follow) stories</td><td><strong>[INSERT REAL COUNT]</strong></td></tr>
    <tr><td>P2 (roadmap) stories</td><td><strong>[INSERT REAL COUNT]</strong></td></tr>
    <tr><td>Personas</td><td><strong>16</strong> (15 from Sadd's original brief + 1 new, Compliance-Conscious Carl)</td></tr>
    <tr><td>Epics pulled from Sentinel (new to Sadd)</td><td>4 (Transparency &amp; Explainability, Trust/Disclosure, Regulatory Compliance, Beginner-First Education)</td></tr>
    <tr><td>Epics formalized from Sadd's existing brief</td><td>14</td></tr>
    </tbody>
    </table></div>
    <hr />

    <h2 id="9-open-risks">9. Open Risks</h2>
    <ul>
    <li><strong>Wi-Fi 7 driver maturity (Epic 7):</strong> mainline OpenWrt/mac80211 support for the newest Wi-Fi 7 silicon is still maturing — do not commit a launch date until a dedicated hardware/driver spike confirms a viable, well-supported chipset.</li>
    <li><strong>Hardware tier decision (Epic 17):</strong> single router vs. mesh-first design is still an open question from Sadd's original brief — most homes over ~1,500 sq ft need mesh per the user-needs analysis; resolve before committing to Epic 17's SKU ladder.</li>
    <li><strong>Epic 16's two-path onboarding vs. Sadd's "never require a settings menu" principle:</strong> confirm the beginner/expert branch in <code class="story-id">US-16.x</code> is framed as pacing, not a gate, so it doesn't contradict Sadd's core simplicity promise.</li>
    <li><strong>Accessibility scope (Epic 16):</strong> the WCAG 2.1 AA audit is a meaningful scope addition — confirm design/QA capacity before committing it to Release 1.1.</li>
    </ul>
    <hr />

    <h2 id="10-change-log">10. Change Log</h2>
    <div class="table-wrap"><table>
    <thead><tr><th>Version</th><th>Changes</th></tr></thead>
    <tbody>
    <tr><td>v1</td><td>Sadd's original product design package: 28-screen UI mockup, persona/needs research, OpenWrt engineering mapping. Tagged in git as the pre-merge baseline this document builds on.</td></tr>
    <tr><td>v0.2</td><td>Merge &amp; expansion pass. Formalized Sadd's existing MVP/V2 feature set into a full Epic → User Story → Acceptance Criteria structure for the first time; pulled in applicable material from a new Firewalla/"Sentinel" competitive research and backlog pass, tier-gated (Simple/Advanced/Business) so nothing bypasses Sadd's simple-by-default promise. Added 4 new epics (Transparency &amp; Explainability, Trust/Disclosure &amp; Vulnerability Management, Regulatory Compliance &amp; Manufacturing, Beginner-First Education) and 1 new persona (Compliance-Conscious Carl). Resolved Sadd's own open product question on data-privacy stance (local-first, formalized in Epic 11). Sadd's brand, name, and simple-first identity are unchanged.</td></tr>
    </tbody>
    </table></div>

  </main>
</div>

<button id="topbtn"
```

- [ ] **Step 4: Verify:**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -oE 'href="#[a-z0-9-]+"' docs/03-Sadd-Product-Backlog-User-Stories.html | sed 's/href="#//;s/"//' | sort -u > /tmp/toc_ids.txt
grep -oE 'id="[a-z0-9-]+"' docs/03-Sadd-Product-Backlog-User-Stories.html | sed 's/id="//;s/"//' | sort -u > /tmp/heading_ids.txt
comm -23 /tmp/toc_ids.txt /tmp/heading_ids.txt
```
Expected: no output (every TOC `href="#..."` has a matching heading `id="..."` somewhere in the document — a broken-anchor check). Also confirm no `[INSERT REAL COUNT` placeholder text remains: `grep -c "INSERT REAL COUNT" docs/03-Sadd-Product-Backlog-User-Stories.html` → expect `0`.

- [ ] **Step 5: Commit** — `"docs: add Roadmap, DoR/DoD, Health Snapshot, Open Risks, and Change Log to Sadd backlog v0.2"`.

---

### Task 9: Wire up docs/README.md, tag v1, verify, and push

**Files:**
- Modify: `docs/README.md`
- Git: tag, push

- [ ] **Step 1: Add a pointer in `docs/README.md`**

Read the current top of `docs/README.md` (the "Start here" table) and add one new row at the top of that table:

```markdown
| **`03-Sadd-Product-Backlog-User-Stories.html`** | The canonical requirements reference (v0.2) — full Epic → User Story → Acceptance Criteria backlog, merging this package's original brief with gated-in competitive research | Understand exactly what's in/out of scope and why, with priorities and points |
```
Add it as the first row of the existing table (before the `sadd-ui-mockups.html` row), so it's the new entry point.

- [ ] **Step 2: Verify the README change**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -c "03-Sadd-Product-Backlog-User-Stories.html" docs/README.md
```
Expected: `1`.

- [ ] **Step 3: Tag the pre-merge state as v1**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && git log --oneline -1 HEAD~9
```
(This should show the commit immediately before Task 1's scaffold commit — i.e., the last commit before this plan's work began. Confirm the SHA looks right — it should be the "feat: add Network and Settings tab screens" commit or whatever was HEAD when this plan started.)

```bash
GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git tag -a v1 <that-SHA> -m "v1: Sadd design package pre-merge baseline (28-screen UI mockup, mobile app prototype, original product brief)" && git push origin v1
```

- [ ] **Step 4: Commit and push the README update**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git add docs/README.md && GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: point README at the new v0.2 backlog as the canonical reference"
git push origin main
```

- [ ] **Step 5: Final full-document verification**

```bash
cd "c:\Users\hamzaz.SQU\Documents\projects\router" && grep -oE 'id="epic-[0-9]+-' docs/03-Sadd-Product-Backlog-User-Stories.html | sort -u | wc -l
grep -c "INSERT REAL COUNT" docs/03-Sadd-Product-Backlog-User-Stories.html
git tag -l v1
git log --oneline -1 origin/main
```
Expected: `18` epic sections, `0` leftover placeholders, `v1` tag listed, and `origin/main` matches local HEAD (confirms the push succeeded).

- [ ] **Step 6: Manual browser check** — open `docs/03-Sadd-Product-Backlog-User-Stories.html`, click through the sidebar TOC end-to-end (all 18 epics + sections 5–10), confirm active-section highlighting and search filtering both still work, and spot-check 3–4 Simple-tier stories for plain-language wording (no unexplained jargon).

---

## Self-review notes (from writing-plans skill)

**Spec coverage:** All sections named in the design spec (front matter/revision note, Product Vision, Personas incl. P6, 18 Epics with rationale/provenance, Backlog by Epic with tier+provenance tags, Release Roadmap using Sadd's MVP/V2 split, DoR/DoD, Backlog Health Snapshot computed not estimated, Change Log referencing the v1 tag, README pointer, git tag v1 pushed) map to a task above.

**Placeholder scan:** Task 1 and Task 8's literal content blocks are complete, no TBD/TODO. Tasks 2–7's content briefs are intentionally not literal final prose (per the design spec's approved "Authoring approach" exception) but every brief names exact source story IDs, exact merge/exclude decisions, and exact tier/provenance rules — no vague "add appropriate stories" language.

**Type/format consistency:** Every task uses the same table column order (ID / Story / Acceptance Criteria / Tier / Provenance / Priority / Points), the same tag CSS classes defined once in Task 1 (`tag-tier`, `tag-tier advanced`, `tag-tier business`, `tag-src`, `tag-src sentinel`, `tag-src new`), and the same `US-<epic>.<seq>` ID scheme throughout.
