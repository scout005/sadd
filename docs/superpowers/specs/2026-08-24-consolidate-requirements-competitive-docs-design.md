# Consolidate Requirements/Backlog and Competitive-Analysis Documents — Design

## Goal

The project has accumulated three overlapping-but-different product backlogs and one competitive-analysis document, plus several supporting research/architecture files, scattered across `docs/`. Collapse everything requirements/user-story/backlog/plan-related into a single `02-Product-Backlog-User-Stories.html`, and everything competitive-analysis-related into a single `01-Competitive-Analysis-Firewalla.html`. Delete the source files once their content is merged in; leave files that aren't themselves requirements/backlog/competitive-analysis documents untouched.

## Source inventory and disposition

| File | Content | Disposition |
|---|---|---|
| `02-Product-Backlog-User-Stories.html` | 94 stories, 18 epics, "Sentinel" codename, Personas, Roadmap, DoR/DoD, Scrum refinement, Risks, Health Snapshot, Change Log | **Base document — stays, gets extended** |
| `01-Competitive-Analysis-Firewalla.html` | Firewalla-specific deep competitive analysis, §8 Adjacent Competitor Landscape | **Base document — stays, gets extended** |
| `03-Sadd-Product-Backlog-User-Stories.html` | 92 stories, 18 epics, Sadd-adapted, tier-gated (Simple/Advanced/Business), 16 personas, provenance tags | Merge into 02, then delete |
| `router-project-plan.docx` | Goals/Objectives, Scope (MVP/v1.1/v1.2), Timeline & Milestones, Team, Risk Register, Governance, Success Criteria, Open Decisions | Merge into 02 (new "Project Plan & Roadmap" section), then delete |
| `router-security-app-backlog.xlsx` | 21 epics (E1–E21), 81 stories (`US1.1` scheme), 243 tasks, 24 NFRs, Release Plan, 10 confirmed product decisions | Merge into 02 (enrich existing epics 1–18, add new epics 19–25, add Task Breakdown + NFR sections), then delete |
| `router-srs-functional-spec.docx` | 17 FRs (FR-01–FR-17) with Inputs/Outputs/Preconditions/Behavior/Error-handling, Data Description, External Interfaces | Merge into 02 (enrich matching stories' acceptance criteria with behavior/error-handling detail), then delete |
| `home-router-user-needs-analysis.md` | Part 1: 15 personas. Parts 2–5: cross-persona feature matrix, real-world brand benchmarks (eero/Gryphon/ASUS/UniFi/TP-Link/Netgear), decision factors, symptom-to-feature mapping. Part 6: product concept/positioning/MVP feature set | **Split**: Part 1 + Part 6 → 02 (Personas, new Product Concept section); Parts 2–5 → 01 (new competitive-benchmark subsection under §8). Delete after. |
| `home-network-security-research.md` | Sourced survey stats (device counts, security-habit gaps, parental-control adoption), requested feature set with confirmed decisions | Merge into 02 as a condensed "Research & Evidence Base" appendix, then delete |
| `future-consideration-isp-centralized-management.md` | Explicitly "not part of the product backlog" — deferred architectural notes | **Untouched** |
| `router-architecture-recommendation.md` | Explicitly "not a backlog addition" — technical stack recommendation | **Untouched** |
| `sadd-openwrt-mapping.md` | Engineering handoff mapping UI screens to OpenWrt mechanisms | **Untouched** |
| `home-network-security-survey.md` | A survey instrument (questions to ask users), not requirements itself | **Untouched** |
| `sadd-design-directions.html`, `sadd-layout-directions.html`, `sadd-sitemap.html`, `sadd-ui-mockups.html` | UI design artifacts | **Untouched** |
| `docs/README.md` | Points to 03 as "the canonical requirements reference" | **Updated** to point at 01/02 instead, screen inventory/mapping references kept |

## Target structure: 02-Product-Backlog-User-Stories.html

Existing sections (§1 Vision, §2 Personas, §3 Epics summary, §4 Product Backlog by Epic 1–18, §5 Release Roadmap, §6 DoR, §7 DoD, §8 Scrum Refinement Pass, §9 Open Risks, §10 Backlog Health Snapshot, §11 Change Log) are preserved. Additions:

1. **§2 Personas** — merge in the 15 personas from the needs-analysis doc. Where a persona clearly overlaps an existing one (e.g. "Parents/Household Admins" vs 02's existing parent persona), merge the richer feature detail into the existing entry rather than duplicating; where distinct (Gamers, Roommates, Multi-Property Owners, Small Business, etc.), add as new entries.
2. **§4 Epics 1–18** — each story keeps its existing ID/text but gains, where a matching xlsx `US*.*` or SRS `FR-*` story covers the same ground: richer acceptance criteria, error/edge-case handling, and a provenance tag (`[Sentinel]` / `[Sadd]` / `[Engineering backlog]`). No wholesale rewrite of stories that have no matching source content.
3. **New Epics 19–25** (from xlsx E15–E21, renumbered to continue 02's sequence): On-Router Software Foundation, Firmware & OTA Update Pipeline, Remote Access Relay Infrastructure, Frontend Platform Foundation, Hardware & Manufacturing, Security Assurance & Privacy Compliance, Support & Diagnostics. Each gets its full story set (the ~27 xlsx stories with no 02 equivalent) formatted consistently with 02's existing epic sections.
4. **New §: Engineering Task Breakdown** — all 243 tasks from the xlsx Tasks sheet (Design/Build/Test triads per story), grouped by epic then story, in a collapsible/compact table so it doesn't dominate the document.
5. **New §: Non-Functional Requirements** — the 24 NFRs from the xlsx, grouped by category (Usability, Accessibility, Performance, Security, Compatibility, Reliability, Localization, Onboarding, Architecture).
6. **New §: Project Plan & Roadmap** — from `router-project-plan.docx`: Goals & Objectives, Scope (In/Out per release), Phased Timeline with Milestones, Team & Responsibilities, Risk Register, Governance/Ceremonies, Success Criteria, Open Decisions. Cross-referenced with (not duplicating) the existing §5 Release Roadmap — §5 stays as the story-to-release mapping, the new section carries the sprint/phase/milestone/team/risk detail §5 doesn't have.
7. **New §: Product Concept & Positioning** — from needs-analysis Part 6: positioning statement, two-tier Simple/Advanced model, MVP and V2 feature sets, competitive positioning summary (cross-referenced to the fuller version now living in 01).
8. **New §: Research & Evidence Base** — condensed key findings from `home-network-security-research.md` (device-count stats, security-habit gap stats, parental-control adoption stats, MFA/block-page decisions) as a short appendix, since several existing epics already implicitly rely on this evidence.
9. **Change Log** — new entry documenting this consolidation pass and what was merged in.

## Target structure: 01-Competitive-Analysis-Firewalla.html

Existing sections stay untouched. One addition:

- **§8 Adjacent Competitor Landscape** gains a new subsection (e.g. §8.10) covering the broader multi-vendor benchmark from needs-analysis Parts 2–5:
  - Cross-Persona Feature-to-Value Matrix
  - Real-World Brand Benchmarks: Performance & Coverage; Security & Control (ad block, named-app block, kids' scheduling, IoT isolation, VPN, threat protection) with the vendor comparison table; Remote Camera & IoT Access; Vendor Cloud-Account & Data Privacy
  - Decision Factors Beyond Features (cost/subscription fatigue, ISP-vs-retail, mesh economics, physical/environmental, accessibility)
  - Symptom-to-Feature Mapping
  - Competitive Positioning table (this product vs. eero/Gryphon/ASUS/UniFi)
- Change Log gets a new entry.

## Ambiguity resolutions (locked in via prior clarifying questions)

- **Reconciliation approach:** 02's 18-epic structure is the backbone; xlsx/SRS/03 content enriches existing stories and appends new epics rather than restructuring 02's numbering. (User-selected.)
- **Task granularity:** all 243 xlsx tasks are included verbatim in a new section, not summarized. (User-selected.)
- **Source file disposition:** every file whose content is fully merged in gets deleted afterward; files that are explicitly out-of-scope, explicitly "not a backlog addition," or not themselves requirements/backlog/competitive-analysis documents are left untouched. (User-selected.)

## Verification

- After merge: every epic 1–25 in 02 has at least one story; every one of the 243 tasks appears exactly once; every one of the 24 NFRs appears exactly once; the 15 needs-analysis personas are all represented (merged or added) in §2.
- 01's new subsection renders correctly (valid HTML, existing nav/search/TOC mechanisms in 01 still work with the new heading IDs).
- `git status` after deletions shows exactly the six merged-and-deleted source files removed, nothing else.
- `docs/README.md` no longer references `03-Sadd-Product-Backlog-User-Stories.html` as the canonical doc.
