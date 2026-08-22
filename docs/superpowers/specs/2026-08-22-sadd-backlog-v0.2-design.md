# Sadd Product Backlog & User Stories v0.2 — Design

**Status:** Approved
**Scope:** Phase 1 of 2. Produces a new requirements document only. Prototype updates (`sadd-website.html`, `sadd-mobile-app.html`) are explicitly out of scope for this phase and will be brainstormed separately once this document lands.

## Background

Two new reference documents were added to `docs/`:

- `01-Competitive-Analysis-Firewalla.html` — a deep competitive analysis of Firewalla, positioned around a different, larger, differently-branded product concept ("Sentinel").
- `02-Product-Backlog-User-Stories.html` — a 94-story, 18-epic product backlog for that same "Sentinel" concept, with a formal Epic → User Story → Acceptance Criteria → Priority → Points structure, a release roadmap, DoR/DoD, an INVEST-audit/refinement pass, and a backlog health snapshot.

The user wants these two documents used as **reference material** to update and enrich Sadd's own requirements — not to replace Sadd's brand or simple-first identity. Sadd is a consumer router product (mobile-app-first, teal/pill-button design system, "Simple Mode by default, Advanced Mode as an opt-in escape hatch") documented today primarily in `docs/home-router-user-needs-analysis.md` (15 personas, MVP + V2 feature set, a competitive table vs. eero/Gryphon/ASUS/UniFi) and `docs/sadd-openwrt-mapping.md` (confirms Sadd is already built on OpenWrt).

The fit turns out to be strong: Sadd already has a Simple/Advanced Mode split that maps naturally onto "gate Sentinel's enterprise-grade material behind Advanced Mode," and Sadd is already OpenWrt-based, so Sentinel's new OpenWrt Platform Foundation epic is directly relevant rather than a foreign import.

**Decisions already made with the user (do not re-litigate):**
- Merge into Sadd, don't rebrand to Sentinel.
- Pull in everything relevant from Sentinel's backlog, gated by tier (Simple / Advanced / Business), rather than dropping enterprise-shaped material entirely or requiring a story-by-story approval pass.
- Two-phase execution: this document (Phase 1) now; propagating changes into the HTML prototypes is a separate, later brainstorm (Phase 2).
- Versioning: current repo state gets `git tag v1` (no files moved, renamed, or deleted). The new document is versioned v0.2 in its own header and change log. "v1" and "v0.2" are the user's own explicit choice of labels, not a typo for "v2" — do not "fix" this.

## Deliverable

**New file:** `docs/03-Sadd-Product-Backlog-User-Stories.html`

Same reusable chrome as the two reference docs (fixed sidebar with brand block + doc-switcher link + search box + TOC, sticky topbar, progress bar, back-to-top button, mobile menu toggle, active-section scroll highlighting) — copy the `<style>` and `<script>` blocks structurally, but re-themed:

- Colors: Sadd's existing teal `#0D9488` / `#0F766E` / `#F0FDFA` (from `sadd-website.html`'s design tokens) replace Sentinel's `#1fb6a8` teal-on-dark-sidebar scheme. Sidebar itself can stay dark (it's a docs-chrome convention, not the product's own UI), but accent color, link color, and highlight states switch to Sadd's teal.
- Fonts: Baloo 2 (headings) + Nunito (body) via Google Fonts, replacing Inter/IBM Plex Mono — matches `docs/README.md`'s stated design system ("Baloo 2 (headings/labels) and Nunito (body text)").
- Branding text: "Sadd" throughout (title, sidebar brand block, kicker), not "Sentinel."
- Doc-switcher link: point to `docs/README.md` (the existing Sadd design package index) rather than cross-linking to the Sentinel docs — this new doc supersedes them as Sadd's own reference, though the Sentinel docs remain in `docs/` untouched as source material.

**Versioning mechanics:**
- `git tag v1` at the commit immediately before this work begins (current HEAD). Push the tag to `origin` alongside the tag creation, consistent with this project's standing practice of pushing all work to GitHub.
- The new doc's own header states "v0.2" and includes a Change Log section (mirroring the reference docs' own Section 11/12 pattern) explaining what changed and why, citing this merge.
- `docs/README.md` gets a short new line pointing at the new doc as the current canonical requirements reference (old files stay in place, untouched, just no longer the primary entry point).

## Content structure

### Front matter
Title, prepared-by, date, a revision note explaining v0.2's origin (merge of Sadd's original product brief with gated-in Sentinel research), Product Vision (adapted from Sadd's existing positioning statement in `home-router-user-needs-analysis.md` §6.1 — "simple by default, powerful underneath," not Sentinel's "give every household enterprise-grade... without a subscription" framing, though the no-subscription piece is shared and should carry over).

### Personas
Sadd's existing 15 personas (from `home-router-user-needs-analysis.md` Part 1), kept in their original voice/structure, **plus** Sentinel's Persona P6 (Compliance-Conscious Carl) added as persona #16 — relevant because of the new Regulatory Compliance epic, reworded slightly to fit Sadd's persona-writing style (Core Need → sub-bullets, not Sentinel's table-row format).

### Epics
18 epics, **renumbered E1–E18 for Sadd** (not a reuse of Sentinel's numbering, since scope and grouping differ). Each epic entry states its **competitive/product rationale** (mirroring the existing `03. Epics` table pattern from the Sentinel doc) and a one-line **provenance note** (built on Sadd's existing X / new from Sentinel research / synthesized for this merge):

1. Onboarding & Setup — Sadd's existing MVP onboarding + Sentinel additions: passkey auth, multi-user pairing, local-web-UI-as-escape-hatch.
2. Core Threat Protection (DPI/IDS/IPS) — Sadd's existing Security section, formalized with Sentinel's DPI/IDS/IPS breakdown; Simple Mode = defaults on, Advanced Mode = rule/threshold tuning.
3. Network Segmentation & Zero Trust — Sadd's existing Kids/Guest/Smart-Home zone presets (Simple) + Sentinel's full VLAN/microsegmentation/Zero-Trust allow-list material (Advanced) — Sadd's V2 section already named this as a target.
4. Transparency & Explainability — new formal epic for Sadd, built from Sentinel's "why was this blocked" epic, matched against Sadd's own stated differentiator language in its positioning.
5. Parental Controls & Content Filtering — Sadd's flagship epic, enriched with Sentinel's symmetric allow/block scheduling and SafeSearch specifics.
6. VPN & Remote Access — Sadd's one-tap VPN (Simple) + Sentinel's OpenVPN alternative, per-device VPN client routing, site-to-site, and AmneziaWG censorship-resistant protocol (Advanced/optional).
7. Wi-Fi Integration — Sadd's integrated-Wi-Fi assumption + Sentinel's mesh AP accessory and Wi-Fi 7 driver-maturity risk flag.
8. Ad & Tracker Blocking — Sadd's existing ad-block-by-default + Sentinel's custom blocklist import and whitelist-broken-site flow (Advanced).
9. Reliability & Multi-WAN — Sadd's V2 multi-WAN mention, formalized with Sentinel's failover/load-balancing/diagnostics/uptime-target stories.
10. Mobile App & Dashboard — Sadd's core hub + Sentinel's tablet layout, home-screen widget, and symmetric-scheduling UI.
11. Privacy & Data Handling — resolves Sadd's own open product question (§6.6, "data privacy stance") using Sentinel's local-first-default/retention-controls/account-deletion structure — a direct answer to a question Sadd's own brief left open.
12. Developer & Power-User Extensibility — Sadd's V2 API/webhook mention + Sentinel's Docker/SSH/open-firmware/opkg material, gated to Advanced/Developer tier.
13. Fleet & Small-Business Mode — Sadd's existing Persona 15 (Small Business/Home-Business Hybrid) + Sentinel's MSP-style console/API/compliance-report material, gated to an explicit optional "Business" tier — not part of the default consumer experience.
14. Trust, Disclosure & Vulnerability Management — new epic from Sentinel: public CVE/advisory page, disclosed responsible-disclosure policy, no shared/fixed SSH backdoor, incident-response playbook.
15. Regulatory Compliance & Manufacturing — new epic from Sentinel: manufacturing-origin disclosure, HBOM/SBOM, compliance statement — scoped as business/legal work with one real UI touchpoint (an "About" screen disclosure).
16. Beginner-First Education & Onboarding Content — new epic from Sentinel, strongly aligned with Sadd's core mission (glossary/primer, two-path "new to this / know networking" wizard branch, video walkthroughs, accessibility path).
17. Hardware & Pricing — Sadd's open question about hardware tiers + Sentinel's simple-SKU-ladder and "Pricing Promise"/no-retroactive-paywall commitment stories.
18. OpenWrt Platform Foundation — formalizes what `sadd-openwrt-mapping.md` already assumes, using Sentinel's version/target-lock, GPL-boundary, sysupgrade OTA, LuCI-based Advanced Mode web UI, and curated package manifest stories.

### Backlog by epic
Same story format as the Sentinel doc (`US-#.#` ID, story text in "As a [persona], I want..., so that..." form, Acceptance Criteria, Priority badge P0/P1/P2, Fibonacci points), with two additions on every row:

- **Tier tag**: `[Simple]`, `[Advanced]`, or `[Business]` — which layer of Sadd's interface this lives in. Simple Mode stories must read in plain language with no exposed jargon, matching Sadd's existing voice.
- **Provenance tag**: `[Sadd]` (already implied/stated in Sadd's existing docs, now formalized), `[Sentinel]` (pulled in from the new reference backlog, tier-gated), or `[NEW]` (synthesized during this merge — genuinely new, not sourced from either existing doc).

Not every Sentinel story needs a 1:1 pull-in — some are near-duplicates of existing Sadd concepts (e.g. Sentinel's device quarantine story vs. Sadd's IoT auto-isolation) and should be merged into one Sadd story citing both provenances, not duplicated as two rows.

### Release roadmap, DoR/DoD, backlog health snapshot, change log
Same structural sections as the Sentinel doc (Release Roadmap, Definition of Ready, Definition of Done, a recounted Backlog Health Snapshot table, a Change Log), adapted:
- Roadmap phases should reflect Sadd's own MVP/V2 split (already defined in `home-router-user-needs-analysis.md` §6.3/§6.4) rather than inventing a new roadmap from scratch — Sentinel's Sprint-0-style compliance gate is worth keeping (manufacturing/HBOM/SBOM sign-off before hardware tooling), since it applies equally to Sadd if it ships physical hardware.
- Change Log's first entry describes this as v0.2, explicitly built from Sadd's original product brief plus gated-in Sentinel research, and references the `v1` git tag as the prior state.

## Authoring approach (why this isn't a literal, fully-pre-written plan)

Given the likely size (Sentinel's own backlog alone is 94 stories across 18 epics; Sadd's merge will be smaller in places — Business/Fleet, Compliance — and larger in others — Onboarding, Parental Controls, Education — but comparably sized overall), hand-writing every story's exact final text inside the implementation plan isn't practical the way exact HTML was hand-written for the mobile app's fixed set of 12 screens.

Instead, the implementation plan (next step, via `writing-plans`) will break this into tasks **by epic-group**, where each task carries:
- A content brief: which epic(s), which source material from which doc (cite section/epic numbers in both reference docs and in `home-router-user-needs-analysis.md`), the tier/provenance-tagging rule, and the exact HTML row/section format with one fully-worked example story.
- The implementer subagent drafts the actual story text/acceptance-criteria within that brief.
- Spec-compliance review checks: every epic in the brief is present, every story has both tags, no Sentinel material outside the agreed gating scheme leaked in unscoped, no contradictions with Sadd's existing simple-first voice in Simple-tier stories, no near-duplicate stories left unmerged.
- Code-quality review checks: valid HTML, consistent styling/theming with the rest of the doc, internal cross-references resolve, prose quality/consistency.

This mirrors how the mobile app's screens were built and reviewed (implementer → spec reviewer → quality reviewer per task), just with a content brief standing in for literal pre-written HTML given the volume of prose involved.

## Out of scope for this phase

- Any change to `sadd-website.html` or `sadd-mobile-app.html` (Phase 2, separate brainstorm).
- Deleting, moving, or rewriting any existing file in `docs/` — everything currently there stays exactly as-is.
- A full rebrand to "Sentinel" — explicitly rejected by the user.
- Story-by-story sign-off on which Sentinel material is in/out — the user chose the blanket "pull in everything relevant, gate by tier" rule; per-epic tier/provenance decisions above implement that rule and are not open for re-litigation mid-implementation, though genuinely ambiguous individual stories can be flagged to the user during implementation if they don't fit any tier cleanly.

## Testing / verification

No test suite (this is a static documentation artifact). Verification mirrors the pattern used for the two reference docs and Sadd's prototypes:
- Every `id` referenced by a sidebar TOC `href="#..."` must exist as a real heading `id` in the document body (grep-based cross-check).
- The document must be valid enough HTML to render correctly (no unclosed major structural tags) — spot-checked, not machine-parsed, since this is prose HTML, not a JS-parseable `<script>` object like the mobile app.
- A final read-through pass (by the code-quality reviewer on the last task) confirms Simple-tier stories are genuinely jargon-free and Advanced/Business-tier stories are clearly gated, not accidentally surfaced as default-experience requirements.
- `docs/README.md` correctly links to the new doc.
- `git tag v1` exists and is pushed; the new doc and README update are committed and pushed to `main`.
