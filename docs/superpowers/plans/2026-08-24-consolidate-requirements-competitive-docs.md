# Consolidate Requirements/Backlog and Competitive-Analysis Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge every requirements/user-story/backlog/plan document in `docs/` into `02-Product-Backlog-User-Stories.html`, and every competitive-analysis document into `01-Competitive-Analysis-Firewalla.html`, then delete the fully-merged source files.

**Architecture:** Both target files are plain multi-line HTML (headings with `id` attributes, `<table>` blocks) — no build step, no JSON-encoded content (unlike `sadd-website.html`). All insertions are done with the `Edit` tool anchored on existing heading/closing-tag text. Source content for the merge comes from: `docs/03-Sadd-Product-Backlog-User-Stories.html`, `docs/router-project-plan.docx`, `docs/router-security-app-backlog.xlsx`, `docs/router-srs-functional-spec.docx`, `docs/home-router-user-needs-analysis.md`, `docs/home-network-security-research.md` — all still readable from disk (docx/xlsx already extracted to the plain-text dumps listed below) until the final deletion task.

**Tech Stack:** Static HTML, no build tooling. Verification is by `grep` heading/row counts, not automated tests — this is a documentation-consolidation task, not application code.

**Pre-extracted source dumps** (already produced this session, still on disk, referenced by later tasks instead of re-parsing the binary files):
- `docs/router-project-plan.docx` → full text quoted inline in Task 8 below (127 lines, already captured)
- `docs/router-security-app-backlog.xlsx` → full text quoted inline in Tasks 4–7 and 9–10 below (636 lines, already captured across the Epics/User Stories/Tasks/NFR sheets)
- `docs/router-srs-functional-spec.docx` → full text quoted inline in Task 3 below (267 lines, already captured)

Because the full content of all three binary sources was already extracted and reviewed earlier in this session, this plan embeds the exact source text needed for each task directly in that task, rather than pointing at session-scoped scratchpad paths that wouldn't survive into a fresh session.

---

## Existing structure reference (both files, as of this plan)

**`02-Product-Backlog-User-Stories.html`:** §1 Product Vision, §2 Personas, §3 Epics (summary), §4 Product Backlog by Epic — Epic 1 Onboarding & Setup, Epic 2 Core Threat Protection, Epic 3 Network Segmentation & Zero Trust, Epic 4 Transparency & Explainability, Epic 5 Parental Controls & Content Filtering, Epic 6 VPN, Epic 7 Wi-Fi Integration, Epic 8 Ad & Tracker Blocking, Epic 9 Multi-WAN & Reliability, Epic 10 Mobile App & Dashboard, Epic 11 Fleet Management/MSP, Epic 12 Developer & Power-User Extensibility, Epic 13 Privacy & Data Handling, Epic 14 Hardware Lineup & Pricing, Epic 15 Regulatory Compliance, Epic 16 Trust/Disclosure/Vuln Mgmt, Epic 17 Beginner-First Education, Epic 18 OpenWrt Platform Foundation — §5 Release Roadmap, §6 DoR, §7 DoD, §8 Scrum Refinement Pass, §9 Open Risks & Questions, §10 Backlog Health Snapshot, §11 Change Log. Story IDs use the `US-N.M` (hyphenated) scheme.

**`01-Competitive-Analysis-Firewalla.html`:** §1 Executive Summary … §8 Adjacent Competitor Landscape (with subsections 8.5–8.9) … §9 Strategic Takeaways … §10 Documentation/Messaging Analysis … §11 Sources … §12 Change Log.

## ⚠️ Known technical-decision conflict — do not silently resolve

02's existing `US-18.3` specifies **sysupgrade-based** OTA with rollback, and `US-18.4` specifies the local web UI as **a themed LuCI overlay**. The engineering backlog being merged in (xlsx `US16.1`, SRS `FR-12`) specifies **RAUC-based A/B** OTA instead, and (xlsx `US18.4`, SRS §2, `router-architecture-recommendation.md`) specifies **excluding LuCI entirely** from the consumer product in favor of a custom daemon/API. These are direct contradictions on core architecture, not complementary detail. Task 7 and Task 9 must preserve 02's existing Epic 18 stories completely unmodified, add the new epic's conflicting stories alongside them, and Task 13 must add an explicit flagged entry in §9 Open Risks documenting the conflict as an unresolved product/engineering decision — never pick a side silently.

---

### Task 1: Stage durable copies of the extracted source dumps

**Files:**
- Create: `docs/superpowers/plans/2026-08-24-source-extracts/plan-dump.txt`
- Create: `docs/superpowers/plans/2026-08-24-source-extracts/backlog-xlsx-dump.txt`
- Create: `docs/superpowers/plans/2026-08-24-source-extracts/srs-dump.txt`

- [ ] **Step 1:** Copy the three existing scratchpad extraction dumps into the new `docs/superpowers/plans/2026-08-24-source-extracts/` folder so the full source text survives independently of any session-scoped temp directory, in case this plan is picked up in a fresh session. Use whatever scratchpad dump files already exist in the current session's temp folder (produced via `python-docx`/`openpyxl` extraction of `router-project-plan.docx`, `router-security-app-backlog.xlsx`, and `router-srs-functional-spec.docx`). If no scratchpad dump exists (fresh session with no prior extraction), re-run the extraction: `python-docx` for the two `.docx` files (iterate `document.element.body` children, handling both `Paragraph` and `Table` blocks) and `openpyxl` for the `.xlsx` (iterate `workbook.sheetnames`, dump each sheet's rows pipe-separated), writing UTF-8 output.
- [ ] **Step 2:** Verify each file is non-empty and has the expected approximate line count (plan-dump.txt ~127 lines, backlog-xlsx-dump.txt ~636 lines, srs-dump.txt ~267 lines): `wc -l docs/superpowers/plans/2026-08-24-source-extracts/*.txt`
- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-08-24-source-extracts/
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: stage durable source-extract copies for backlog consolidation"
```

---

### Task 2: Merge personas into 02 §2

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (§2 Personas section)
- Read: `docs/home-router-user-needs-analysis.md` (Part 1, 15 personas) and `docs/03-Sadd-Product-Backlog-User-Stories.html` (existing persona section) for source text

- [ ] **Step 1:** Read 02's current §2 Personas section in full (`grep -n 'id="2-personas"' -A 60` or open the file around that heading) to see its existing persona cards/format and which personas already exist (likely including a parent/admin persona, a technical/advanced persona, etc.).
- [ ] **Step 2:** Read `docs/home-router-user-needs-analysis.md` lines 33–298 (Part 1, all 15 personas: Gamers, Parents/Household Admins, Kids/Teens, Remote Workers, Streamers, Smart Home Enthusiasts, Away-From-Home Users, Pet Owners, Non-Tech-Savvy/Seniors, Privacy/Security-Conscious, Large/Multi-Generational Households, Roommates, Renters, Multi-Property Owners, Small Business).
- [ ] **Step 3:** For each of the 15 personas, check whether an equivalent already exists in 02's §2. Where it does, use `Edit` to enrich the existing persona entry with any additional need/feature detail from the needs-analysis version that 02's version lacks (do not duplicate the persona card). Where no equivalent exists, append a new persona card immediately before the closing tag of the §2 section, matching 02's existing HTML structure exactly (same class names/tag structure as the surrounding cards).
- [ ] **Step 4:** Verify: `grep -c 'persona' docs/02-Product-Backlog-User-Stories.html` before/after to confirm the count grew appropriately, and visually confirm no duplicate persona names.
- [ ] **Step 5: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: merge 15 needs-analysis personas into 02 backlog"
```

---

### Task 3: Enrich Epics 1–9 acceptance criteria from the SRS and xlsx

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (Epic 1, 2, 3, 4, 5, 6, 7, 8, 9 story rows)

**FR/story-to-epic mapping to apply** (from the SRS dump, `docs/superpowers/plans/2026-08-24-source-extracts/srs-dump.txt`, and the xlsx User Stories sheet in `backlog-xlsx-dump.txt`):

| SRS FR (source) | xlsx stories (source) | 02 target epic |
|---|---|---|
| FR-01 First-Run Guided Setup | US1.1–1.4, US14.1–14.2, US14.5 | Epic 1 — Onboarding & Setup |
| FR-02 MFA Enrollment & Verification | US1.2, US3.1–3.4 | Epic 1 — Onboarding & Setup |
| FR-03 Cloud Account Link & Multi-Router | US14.3–14.4, US14.6 | Epic 1 — Onboarding & Setup |
| FR-06 Site & Category Blocking | US5.1, US5.3 | Epic 5 — Parental Controls & Content Filtering |
| FR-07 Block Page | US5.2, US5.7 | Epic 5 — Parental Controls & Content Filtering |
| FR-08 Parental Profiles/Time Limits/Pause | US8.1–8.4, US8.5–8.6 | Epic 5 — Parental Controls & Content Filtering |
| FR-09 Per-App Blocking | US5.5–5.6 | Epic 5 — Parental Controls & Content Filtering |
| FR-10 Ad Blocking | US6.1–6.2 | Epic 8 — Ad & Tracker Blocking |
| FR-14 Remote Session | US7.1–7.7, US17.1–17.3 | Epic 6 — VPN (Server & Client) |
| (Guest network) | US9.1–9.2 | Epic 7 — Wi-Fi Integration |
| (Device registry) FR-05 | US4.1–4.5 | Epic 3 — Network Segmentation & Zero Trust (device visibility/isolation stories) or Epic 9/10 if 02's Epic 3 is firewall-zone-only — check 02's existing Epic 3 scope first and place device-list stories in Epic 10 (Mobile App & Dashboard) instead if Epic 3 is strictly segmentation |
| (Security status) FR-04 | US2.1–2.4 | Epic 4 — Transparency & Explainability |
| (Alerts) FR-15 | US10.1–10.2 | Epic 9 — Multi-WAN & Reliability, or Epic 10 if 02 groups notifications under dashboard — check existing epic scopes first |

- [ ] **Step 1:** Read each target epic's current stories in 02 (Epics 1, 3, 4, 5, 6, 7, 8, 9) to see current wording, ID numbering (next free `US-N.M` per epic), and existing acceptance-criteria depth.
- [ ] **Step 2:** For each SRS FR / xlsx story in the mapping table whose subject matter is **already covered** by an existing 02 story in that epic, use `Edit` to extend that story's Acceptance Criteria cell with the additional behavior/error-handling bullets from the SRS (Inputs/Outputs/Preconditions/Behavior/Error-handling table) that 02's version doesn't already state, and append a `<br><em>[Engineering backlog: FR-xx / USn.n]</em>` provenance note at the end of the cell. Do not remove or reword 02's existing acceptance criteria — only append.
- [ ] **Step 3:** For each SRS FR / xlsx story whose subject matter has **no existing 02 story** in that epic, add a new `<tr>` row at the end of that epic's table using 02's exact row format (`<code class="story-id">US-N.M</code>` with the next free number in that epic, story text adapted from the xlsx "As a ... I want ... so that ..." format, acceptance criteria from the xlsx bullets, a `<span class="badge badge-pN">` priority badge mapped from the xlsx MoSCoW column — Must→P0, Should→P1, Could→P2 — and points from the xlsx Story Points column), tagged `<em>[Engineering backlog]</em>`.
- [ ] **Step 4:** Verify: for each of the 9 epics touched, `grep -c '<tr>' ` before/after to confirm row counts only grew, never shrank, and spot-check 2–3 modified rows render as valid HTML (matching `<td>` open/close counts).
- [ ] **Step 5: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: enrich epics 1-9 with SRS/engineering-backlog acceptance criteria"
```

---

### Task 4: Enrich Epics 10–18 acceptance criteria from the SRS and xlsx

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (Epic 10 through Epic 18 story rows)

**Additional mapping:**

| SRS FR / xlsx source | 02 target epic |
|---|---|
| FR-11 Offline Operation (US13.3, US15.3) | Epic 18 — OpenWrt Platform Foundation (add alongside existing US-18.x, do not touch US-18.3/US-18.4 per the conflict note above) |
| FR-13 Physical Recovery (US13.4, US19.3) | Epic 14 — Hardware Lineup & Pricing |
| FR-17 Support & Self-Help (US21.1) | Epic 10 — Mobile App & Dashboard, self-help subsection |
| xlsx US20.1–20.3 (external audit, privacy compliance, disclosure SLA) | Epic 16 — Trust, Disclosure & Vulnerability Management |
| xlsx US19.4 (regulatory certification) | Epic 15 — Regulatory Compliance & Domestic Manufacturing |
| xlsx US18.1–18.3 (mobile/web framework, unified API client) | Epic 12 — Developer & Power-User Extensibility |

- [ ] **Step 1:** Same process as Task 3 Step 1, for Epics 10, 12, 14, 15, 16, 18.
- [ ] **Step 2:** Same enrich-existing-or-append-new process as Task 3 Steps 2–3, applying the mapping table above. For Epic 18 specifically: append `US-18.7` (offline daemon degradation, from FR-11/US15.3) as a new story; do NOT edit `US-18.3` or `US-18.4`.
- [ ] **Step 3:** Verify with the same row-count grep check as Task 3 Step 4.
- [ ] **Step 4: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: enrich epics 10-18 with SRS/engineering-backlog acceptance criteria"
```

---

### Task 5: Add new Epics 19–21 (On-Router Software, Firmware/OTA, Remote Relay)

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (insert after the closing `</table></div>` of Epic 18, before `<h2 id="5-release-roadmap-suggested">`)

**Source stories** (from `backlog-xlsx-dump.txt`, User Stories sheet):
- Epic 19 — On-Router Software Foundation: `US15.1` Custom OpenWrt build pipeline, `US15.2` On-device daemon with unified local API, `US15.3` Daemon degrades gracefully offline (cross-reference: also touched in Task 4 for Epic 18 — link, don't duplicate the full row, just cross-reference by ID)
- Epic 20 — Firmware & OTA Update Pipeline: `US16.1` RAUC A/B integration, `US16.2` Cloud OTA update server, `US16.3` Staged/canary rollout control
- Epic 21 — Remote Access Relay Infrastructure: `US17.1` Headscale vs. custom WireGuard spike, `US17.2` Outbound-only WireGuard tunnel client, `US17.3` ACL-based access scope enforcement

- [ ] **Step 1:** Using 02's exact epic-section HTML format (copy the structure of Epic 18: `<h3 id="epic-N-...">`, `<div class="table-wrap"><table><thead>...</thead><tbody>` with `ID/Story/Acceptance Criteria/Priority/Points` columns), author Epic 19 with its 3 stories as `US-19.1`–`US-19.3`, sourcing story text and acceptance criteria directly from the xlsx dump rows for `US15.1`–`US15.3` (lines 289–299 of `backlog-xlsx-dump.txt`). Tag each with `<em>[Engineering backlog]</em>`. Insert immediately after Epic 18's closing `</table></div>`.
- [ ] **Step 2:** Add an explicit note at the top of Epic 20 (before its table) referencing the OTA-mechanism conflict: `<p class="note"><strong>Note:</strong> this epic specifies RAUC-based A/B updates (from the engineering backlog), which differs from <code class="story-id">US-18.3</code>'s sysupgrade-based approach — flagged as an unresolved technical decision in §9 Open Risks, not resolved by this merge.</p>`. Then author Epic 20 with `US-20.1`–`US-20.3` from xlsx `US16.1`–`US16.3` (lines 300–309).
- [ ] **Step 3:** Author Epic 21 with `US-21.1`–`US-21.3` from xlsx `US17.1`–`US17.3` (lines 310–318).
- [ ] **Step 4:** Verify: `grep -c 'epic-19\|epic-20\|epic-21' docs/02-Product-Backlog-User-Stories.html` shows 3 new `<h3>` anchors, and each new table has exactly 3 `<tr>` rows in `<tbody>`.
- [ ] **Step 5: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add epics 19-21 (on-router software, OTA pipeline, remote relay) to 02 backlog"
```

---

### Task 6: Add new Epics 22–25 (Frontend Platform, Hardware, Security Assurance, Support)

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (insert after Epic 21's closing `</table></div>`)

**Source stories** (from `backlog-xlsx-dump.txt`):
- Epic 22 — Frontend Platform Foundation: `US18.1` Mobile app framework, `US18.2` Web dashboard framework, `US18.3` Unified API client, `US18.4` Exclude LuCI from consumer product (lines 319–330)
- Epic 23 — Hardware & Manufacturing: `US19.1`–`US19.5` (Hardware platform spike, factory credential provisioning, physical recovery button spec, regulatory certification, pilot production run) (lines 331–345)
- Epic 24 — Security Assurance & Privacy Compliance: `US20.1`–`US20.3` (external audit, privacy compliance, vulnerability disclosure/patch SLA) (lines 346–354)
- Epic 25 — Support & Diagnostics: `US21.1`–`US21.3` (in-app self-help, consent-based remote diagnostics, diagnostic report export) (lines 355–362)

- [ ] **Step 1:** Author Epic 22 as `US-22.1`–`US-22.4`, same format as Task 5 Step 1. On `US-22.4` (Exclude LuCI), add the same conflict cross-reference note as Task 5 Step 2, pointing at `US-18.4`'s LuCI-overlay approach: `<p class="note"><strong>Note:</strong> this story specifies excluding LuCI entirely, which directly conflicts with <code class="story-id">US-18.4</code>'s LuCI-overlay approach — see §9 Open Risks.</p>`.
- [ ] **Step 2:** Author Epic 23 as `US-23.1`–`US-23.5` from `US19.1`–`US19.5`.
- [ ] **Step 3:** Author Epic 24 as `US-24.1`–`US-24.3` from `US20.1`–`US20.3`. Note: xlsx `US20.1`–`US20.3` overlaps with 02's existing Epic 16 (Trust, Disclosure & Vulnerability Management) touched in Task 4 — if Task 4 already added this content to Epic 16, skip re-adding here and instead add a one-line cross-reference (`<p>See Epic 16 for external audit, privacy compliance, and disclosure-SLA stories.</p>`) so the same story doesn't appear twice.
- [ ] **Step 4:** Author Epic 25 as `US-25.1`–`US-25.3` from `US21.1`–`US21.3`. Same de-dup check against Epic 10's self-help story from Task 4.
- [ ] **Step 5:** Verify: `grep -c 'epic-22\|epic-23\|epic-24\|epic-25' docs/02-Product-Backlog-User-Stories.html`, and grep the full file for `US-24.1` / `US20.1` content and `US-16.` Epic-16 content to confirm no verbatim duplicate story text exists in two places.
- [ ] **Step 6: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add epics 22-25 (frontend platform, hardware, security assurance, support) to 02 backlog"
```

---

### Task 7: Add the Engineering Task Breakdown section (243 tasks)

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (new `<h2>` section inserted before `<h2 id="5-release-roadmap-suggested">`, i.e. immediately after the new Epic 25 content from Task 6)

- [ ] **Step 1:** Add heading `<h2 id="4a-engineering-task-breakdown">4a. Engineering Task Breakdown</h2>` with an intro paragraph: `<p>Design/Build/Test task triads per story, from the engineering backlog spreadsheet (<code>router-security-app-backlog.xlsx</code>, now merged into this document). Grouped by epic for cross-reference with §4 above; story IDs here use the source spreadsheet's unhyphenated <code>USn.n</code> scheme, not this document's <code>US-n.n</code> scheme, to preserve traceability to the original task list.</p>`.
- [ ] **Step 2:** For each of the 21 source epics (E1–E21), add an `<h4>` subheading and a `<table>` with columns Task ID / Story ID / Role / Description, populated from the full Tasks sheet in `backlog-xlsx-dump.txt` (lines 364–608, all 243 rows, `T1`–`T243`). Use a compact single-`<td>`-per-column row format (no need for badges/points here, this is a pure task list).
- [ ] **Step 3:** Verify: `grep -c '<td>T' docs/02-Product-Backlog-User-Stories.html` (or equivalent task-ID pattern) equals 243.
- [ ] **Step 4: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add full 243-task engineering breakdown to 02 backlog"
```

---

### Task 8: Add Non-Functional Requirements section (24 NFRs)

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (new `<h2>` after the Task Breakdown section from Task 7)

**Source:** `backlog-xlsx-dump.txt` lines 610–635 (Non-Functional Requirements sheet, `Category | Requirement`, 24 rows across Usability, Accessibility, Performance, Security, Compatibility, Reliability, Localization, Onboarding, Architecture).

- [ ] **Step 1:** Add `<h2 id="4b-non-functional-requirements">4b. Non-Functional Requirements</h2>` with a table grouped by Category (group the 24 rows under `<h4>` category headings: Usability, Accessibility, Performance, Security, Compatibility, Reliability, Localization, Onboarding, Architecture), one `<ul>` of requirement bullets per category, using the exact requirement text from the dump.
- [ ] **Step 2:** Verify: manually count 24 `<li>` requirement bullets across all categories.
- [ ] **Step 3: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add 24 non-functional requirements section to 02 backlog"
```

---

### Task 9: Add Project Plan & Roadmap section

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (new `<h2>` after the NFR section from Task 8)

**Source:** `plan-dump.txt` (full content quoted in this plan's chat history / the source-extracts copy) — Executive Summary, Goal & Objectives (O1–O6), Scope (In-scope MVP / In-scope post-launch v1.1 & v1.2 / Explicitly out of scope), Key Deliverables table, Phased Timeline table + Milestones table, Team & Responsibilities table, Risk Register table (8 risks), Dependencies/Assumptions/Constraints, Governance/Ceremonies/Reporting, Success Criteria, Open Decisions table.

- [ ] **Step 1:** Add `<h2 id="4c-project-plan-roadmap">4c. Project Plan &amp; Roadmap</h2>` with an intro note: `<p>From the project plan document (v1.0, 20 July 2026), now merged into this backlog. Cross-references §5 Release Roadmap below rather than duplicating its story-to-release mapping — this section carries the sprint/phase/milestone/team/risk detail §5 doesn't.</p>`.
- [ ] **Step 2:** Add subsections in order, each as `<h3>` + prose/table matching the source structure: 4c.1 Executive Summary (prose), 4c.2 Goal & Objectives (O1–O6 as a `<ul>`), 4c.3 Scope (three `<h4>` blocks: In Scope — MVP, In Scope — Post-Launch, Explicitly Out of Scope, each a `<ul>`), 4c.4 Key Deliverables (table), 4c.5 Phased Timeline & Milestones (two tables), 4c.6 Team & Responsibilities (table), 4c.7 Risk Register (table, all 8 risks with Likelihood/Impact/Mitigation columns), 4c.8 Dependencies, Assumptions & Constraints (three `<ul>` blocks), 4c.9 Governance, Ceremonies & Reporting (`<ul>`), 4c.10 Success Criteria (`<ul>`), 4c.11 Open Decisions (table, all 4 rows).
- [ ] **Step 3:** In 4c.7 Risk Register, ensure the "Chipset vendor bootloader locking blocks OpenWrt" and hardware-critical-path risks are present verbatim — these are the ones that best explain why Epic 23 (Hardware & Manufacturing) exists.
- [ ] **Step 4:** Verify: `grep -c 'id="4c' docs/02-Product-Backlog-User-Stories.html` shows all 11 subsection anchors present.
- [ ] **Step 5: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add project plan & roadmap section to 02 backlog"
```

---

### Task 10: Add Product Concept & Positioning section

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (new `<h2>` after the Project Plan section from Task 9)

**Source:** `docs/home-router-user-needs-analysis.md` Part 6 (lines 457–546): 6.1 Positioning Statement, 6.2 Two-Tier Interface Model (table), 6.3 MVP Feature Set, 6.4 V2/Advanced Feature Set, 6.5 Competitive Positioning (table — note the fuller version of this table now lives in 01, so here keep only a short summary + `<p>Full competitive comparison in <a href="01-Competitive-Analysis-Firewalla.html">01-Competitive-Analysis-Firewalla.html</a> §8.10.</p>`), 6.6 Open Product Questions.

- [ ] **Step 1:** Add `<h2 id="4d-product-concept-positioning">4d. Product Concept &amp; Positioning</h2>` and author 6.1–6.4 and 6.6 as `<h3>` subsections with matching content, and 6.5 as the short summary + cross-link described above (not the full table — that's Task 12's job in 01).
- [ ] **Step 2:** Verify the cross-link target anchor (`#810-...` or similar, set in Task 12) is created before this task's commit finalizes, or use a plain page-level link (`01-Competitive-Analysis-Firewalla.html`) if the exact anchor isn't finalized yet.
- [ ] **Step 3: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add product concept & positioning section to 02 backlog"
```

---

### Task 11: Add Research & Evidence Base appendix

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (new `<h2>` after the Product Concept section from Task 10, before §5 Release Roadmap)

**Source:** `docs/home-network-security-research.md` — condense (do not reproduce in full): §1 device counts (6.2 smart-home devices/household average, 21 total connected devices average, 59% multi-router households), §2 the core security gap stats (47%/81%/69%/84%/85%/69%/79%/73%), §4 parental-control adoption stats (51%/47%/43%/38%/35%, 69%/64%/32% concern breakdown, 89% kids comfortable telling a parent), §5 confirmed decisions (MFA default = SMS/push, block page = no self-serve unblock) with their design-implication rationale, and the source citations list at the bottom of that file.

- [ ] **Step 1:** Add `<h2 id="4e-research-evidence-base">4e. Research &amp; Evidence Base</h2>` with intro: `<p>Condensed from the market/user research reference (now merged into this document). Several epics above rely on this evidence — this section makes the sourcing explicit.</p>`.
- [ ] **Step 2:** Add three `<h3>` subsections (Device Landscape, The Core Security Gap, Parental Control Adoption & Concerns) each with the key stats as a `<ul>`, plus a `<h3>Confirmed Product Decisions</h3>` listing the MFA-default and block-page decisions with their one-line rationale, plus a closing `<h3>Sources</h3>` with the citation list verbatim from the source file's bottom section.
- [ ] **Step 3: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add research & evidence base appendix to 02 backlog"
```

---

### Task 12: Flag the OTA/LuCI conflict in §9 Open Risks, and update 02's Change Log

**Files:**
- Modify: `docs/02-Product-Backlog-User-Stories.html` (§9 Open Risks & Questions, §11 Change Log)

- [ ] **Step 1:** In §9 Open Risks & Questions, add a new entry (matching the section's existing format) stating: two unresolved architecture conflicts were surfaced by this consolidation and require an explicit product/engineering decision, not resolved by the merge: (a) OTA mechanism — `US-18.3` sysupgrade-based vs. `US-20.1` RAUC A/B-based; (b) local web UI — `US-18.4` LuCI-overlay vs. `US-22.4` LuCI-excluded/custom-daemon. Recommend engineering leadership pick one side of each explicitly before Sprint 1 of the relevant epic.
- [ ] **Step 2:** In §11 Change Log, add a new entry (following the existing entries' format/dating convention) describing this consolidation pass: source documents merged in (list all six), new epics 19–25 added, Engineering Task Breakdown / NFR / Project Plan / Product Concept / Research Evidence sections added, personas merged, and the two flagged architecture conflicts.
- [ ] **Step 3: Commit**

```bash
git add docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: flag OTA/LuCI architecture conflicts and update 02 change log"
```

---

### Task 13: Add the competitive-benchmark subsection to 01

**Files:**
- Modify: `docs/01-Competitive-Analysis-Firewalla.html` (new `<h2>` after existing §8.9, before `<h2 id="9-strategic-takeaways-for-our-product">`)

**Source:** `docs/home-router-user-needs-analysis.md` Parts 2–5 (lines 299–453): Part 2 Cross-Persona Feature-to-Value Matrix (table), Part 3 Real-World Brand Benchmarks (3.1 Performance & Coverage table, 3.2 Security & Control — Ad Blocking / App-Specific Blocking / Screen Time / IoT Isolation / VPN / Threat Protection prose + the Security & Control Brand Comparison table, 3.3 Remote Camera & IoT Access Brand Examples prose, 3.4 Vendor Cloud-Account & Data Privacy Comparison table), Part 4 Decision Factors Beyond Features (4.1–4.5, prose with sub-bullets), Part 5 Symptom-to-Feature Mapping (bullet list). Plus Part 6.5 Competitive Positioning table (lines 528–539) — this is the full version; Task 10's 02 section only summarizes and links here.

- [ ] **Step 1:** Add `<h2 id="810-broader-competitor-landscape-benchmark">8.10 Broader Competitor Landscape Benchmark</h2>` with intro: `<p>Merged from the home-router user-needs analysis reference. Where §§1–9 above focus specifically on Firewalla, this section benchmarks the wider consumer/prosumer router market (eero, Gryphon, ASUS, TP-Link, NETGEAR, Ubiquiti UniFi) across the same feature categories.</p>`.
- [ ] **Step 2:** Add `<h3>8.10.1 Cross-Persona Feature-to-Value Matrix</h3>` with the Part 2 table verbatim.
- [ ] **Step 3:** Add `<h3>8.10.2 Real-World Brand Benchmarks</h3>` with `<h4>` subheadings for Performance & Coverage, Security & Control (including all six prose subsections — Ad Blocking, App-Specific Blocking, Screen Time/Scheduling, IoT Isolation, VPN, Threat Protection — and the comparison table), Remote Camera & IoT Access, and Vendor Cloud-Account & Data Privacy, each with its source table/prose verbatim.
- [ ] **Step 4:** Add `<h3>8.10.3 Decision Factors Beyond Features</h3>` with the 4.1–4.5 subsections as `<h4>` blocks with their bullet content.
- [ ] **Step 5:** Add `<h3>8.10.4 Symptom-to-Feature Mapping</h3>` with the Part 5 bullet list verbatim.
- [ ] **Step 6:** Add `<h3 id="810-5-competitive-positioning">8.10.5 Competitive Positioning</h3>` with the Part 6.5 table verbatim (this product vs. eero/Gryphon/ASUS/UniFi).
- [ ] **Step 7:** Go back to `docs/02-Product-Backlog-User-Stories.html` §4d (added in Task 10) and confirm/fix its cross-link now points to `01-Competitive-Analysis-Firewalla.html#810-5-competitive-positioning`.
- [ ] **Step 8:** Verify: `grep -c 'id="810' docs/01-Competitive-Analysis-Firewalla.html` shows all 6 new anchors.
- [ ] **Step 9: Commit**

```bash
git add docs/01-Competitive-Analysis-Firewalla.html docs/02-Product-Backlog-User-Stories.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: add broader competitor-landscape benchmark (§8.10) to 01, fix 02 cross-link"
```

---

### Task 14: Update 01's Change Log

**Files:**
- Modify: `docs/01-Competitive-Analysis-Firewalla.html` (§12 Change Log)

- [ ] **Step 1:** Add a new Change Log entry documenting: source merged in (`home-router-user-needs-analysis.md` Parts 2–6), new §8.10 with 6 subsections, and that the source file is being deleted as a result (Task 15).
- [ ] **Step 2: Commit**

```bash
git add docs/01-Competitive-Analysis-Firewalla.html
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: update 01 change log for competitor-landscape merge"
```

---

### Task 15: Update README.md, delete merged source files, final verification

**Files:**
- Modify: `docs/README.md`
- Delete: `docs/03-Sadd-Product-Backlog-User-Stories.html`, `docs/router-project-plan.docx`, `docs/router-security-app-backlog.xlsx`, `docs/router-srs-functional-spec.docx`, `docs/home-router-user-needs-analysis.md`, `docs/home-network-security-research.md`
- Delete: `docs/superpowers/plans/2026-08-24-source-extracts/` (staging copies from Task 1, no longer needed once merge is verified complete)

- [ ] **Step 1:** In `docs/README.md`, replace the "Start here" table row currently pointing at `03-Sadd-Product-Backlog-User-Stories.html` as "the canonical requirements reference" with two rows pointing at `01-Competitive-Analysis-Firewalla.html` and `02-Product-Backlog-User-Stories.html` as the canonical competitive-analysis and requirements/backlog documents respectively. Remove the `home-router-user-needs-analysis.md` row (file being deleted) and adjust its "why open this" content into a note that persona/positioning/competitive-benchmark content now lives in 01/02.
- [ ] **Step 2:** Confirm every task in this plan (2–14) is marked complete, then delete the six source files:

```bash
git rm docs/03-Sadd-Product-Backlog-User-Stories.html docs/router-project-plan.docx docs/router-security-app-backlog.xlsx docs/router-srs-functional-spec.docx docs/home-router-user-needs-analysis.md docs/home-network-security-research.md
git rm -r docs/superpowers/plans/2026-08-24-source-extracts/
```

- [ ] **Step 3:** Run final verification: `git status` shows only the six deletions, the extracts-folder deletion, and the README.md modification as pending; grep both target files for zero remaining references to any deleted filename (`grep -rn '03-Sadd-Product-Backlog\|router-project-plan.docx\|router-security-app-backlog.xlsx\|router-srs-functional-spec.docx\|home-router-user-needs-analysis.md\|home-network-security-research.md' docs/01-Competitive-Analysis-Firewalla.html docs/02-Product-Backlog-User-Stories.html docs/README.md` — any hits should only be in Change Log entries documenting the historical merge, not live "see this file" pointers).
- [ ] **Step 4: Commit**

```bash
git add docs/README.md
GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com" git commit -m "docs: delete merged source documents, update README to point at 01/02 as canonical docs"
```

---

## Self-review notes

- **Spec coverage:** every element of the design spec's "Target structure" sections for both 01 and 02 maps to a task above (personas → Task 2; epic enrichment → Tasks 3–4; new epics → Tasks 5–6; task breakdown → Task 7; NFRs → Task 8; project plan → Task 9; product concept → Task 10; research appendix → Task 11; conflict flagging + change log → Task 12; competitive benchmark → Task 13; 01 change log → Task 14; README + deletion → Task 15).
- **De-duplication:** Task 6 Steps 3–4 explicitly guard against Epic 24/25 duplicating content already placed in Epics 16/10 by Task 4.
- **Conflict handling:** the OTA/LuCI architecture conflict is called out at the plan level, at both insertion points (Tasks 5, 6), and formally logged (Task 12) — never silently resolved.
