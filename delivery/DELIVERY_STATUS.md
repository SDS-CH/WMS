# WMS — Delivery / Specs Status (Phase 3)

> **Live status file for the post-mockup phase.** This is the successor to `../mockups/MOCKUP_STATUS.md`
> (which covered Phase 2 — mockups, now COMPLETE). **Do not lose this context.** It holds: where we are,
> the locked delivery sequence, the open decisions, and the **restart prompt for a new session** (bottom).
> **Last updated: 2026-07-03.**

---

## ▶ Where we are

- **DEVELOPMENT PHASE RUNNING (since 2026-06-23) — the build track has moved to the dev tree.** Three
  parallel teams (Master Data · Goods Reception · Reporting) build JIRA-style cards under
  `SDS-ERP-SOLUTION/WMSProject/cards/<section>/` (per-section `_progress.md` trackers; session-start
  briefing via the `/progress-wms <section>` skill). Locked-sequence deliverables 1–2 are produced
  (`WMS_Functional_Specification.docx` + `WMS_Man_Days_Estimation*.docx`, this folder); step 3 (build
  cards) is decomposing per section in the dev tree. **This file stays the SPEC-track status** (docs,
  phases, DDL scripts); per-card build progress lives in the dev-tree trackers, NOT here.
- **DB schema — section 02 (Goods Reception + shared operational core) DONE (2026-07-03):**
  `../scripts/02_goods_reception_schema.sql` (16 tables — ASN, receipts + draft serials, mixed pallets,
  inspection, GRN, refusal, plus the shared `wmslpn`/`wmstxn`/`wmsattachment` core) + companion seed
  (receipt/refuse/discrepancy reason domains). Verified twice field-by-field against the 5 ERP mockups +
  `data.js`; pre-execution fixes applied (incl. the `'reprint'` txn type P02-S06 requires). **Structure-
  update policy established:** canonical numbered files are edited in place (PROD runs fresh) AND every
  change to an already-shipped table is appended as a guarded ALTER to `../scripts/01_master_data_updates.sql`
  (dev DBs catch up); policy documented in `../scripts/README.md`. First entry:
  `wmsproduct.verificationstatus` ('verified'|'pending' — the Receive inline-creation policy).
- **Mockup phase (Phase 2): COMPLETE** — both channels (ERP + PWA), edge-case hardened, on the shared `data.js`. See `../mockups/MOCKUP_STATUS.md`.
- **Execution-layer framework: SCAFFOLDED** — `delivery/` (35 files): orchestrator, host-integration map, cross-cutting registry, 16 common-rule files, 9 phase files (each with its planned-card list), the sub-phase template + 1 fully-worked reference card (`P03-S01`).
- **Host stack confirmed — this is a BROWNFIELD integration:**
  - **Backend:** new `WMS` module inside the existing **ASP.NET Core 3.1** modular monolith (Ocelot gateway) at `D:\CODE\TLC\sds-erp-back` (reuses identity/roles, EF Core 3.1, `OperationResult`/`APICustomException`, AutoMapper, Kendo grids).
  - **ERP front:** new `projects/wms` in the existing **Angular 14** workspace at `D:\CODE\TLC\sds-erp-front` (NgRx, Swagger-generated client, Nebular/Kendo, auth guards).
  - **PWA:** new `projects/wms-scanner` (Angular, **greenfield** — no PWA tooling in host today).
  - **DB:** **SQL Server 2014** (hard constraint — arrays → child tables, hand-rolled audit ledger).
  - Full detail: `01-orchestrator/HOST_INTEGRATION_MAP.md`.
- **DB SCHEMA AUTHORING STARTED (2026-06-23) — section by section, ahead of the cards.** A new
  `../scripts/` directory holds per-section SQL Server 2014 DDL (tables only; **no views/procs** — those
  come per-screen in the dev cards). **Master Data is DONE: `../scripts/01_master_data_schema.sql`
  (29 `wms*` tables)**, adversarially reviewed (5 lenses) + statically validated. Conventions: lower-case
  `wms`-prefixed tables, lower-case columns, `id INT IDENTITY(1,1)` PK on every table, business ids kept
  as a separate `code` column. **The host `[dbo].[Users]` is referenced, NOT recreated** (WMS adds
  `wmsuserprofile` + `wmsusersite`/`wmsuserclient` for role/scope). Index + next sections:
  `../scripts/README.md`. Next: decompose the Master Data cards (sequence step 3), then script section 02+.

---

## ▶ The goal & delivery sequence (LOCKED)

> **We finish the client doc → then the technical doc → then finalize the cards.** In order:

### 1. Client documentation — *first deliverable*
A **Word document (.docx) "specs with print screens"** that presents **every functionality** to the client.
- Organized by **section** (Master Data · Goods Reception · Putaway · Stock-Out · Inventory Operations · Reports) and **channel** (ERP screens + PWA scanner screens).
- For each screen/feature: a **screenshot** of the mockup + a short description of what it does and how to use it.
- Source = the mockups (`../mockups/*.html`); served locally and screenshotted. Built with the **docx skill**.
- ⚠ Known caveat: the preview screenshotter has been intermittently flaky in this project — capture may take iteration (re-attempt / fallback).

### 2. Technical documentation + cost estimation — *second deliverable*
A **Man/Days estimation** as a **simple doc, by page name and functionality** (one line per screen/feature with its effort) — the first-cut estimate. Method + tiers: `01-orchestrator/ESTIMATION_GUIDE.md`; calibrate against `../docs/BUILD_LOG.md`.

### 3. Finalize the build cards — *third deliverable*
- **Decompose Phase 0 + Phase 1 into full build cards** (the phase files already list the planned cards) — **this proves the velocity and unblocks everything.**
- **Generate `COST_MODEL.xlsx`** from those cards once tiers are calibrated against `../docs/BUILD_LOG.md` (the detailed bottom-up estimate, successor to the simple page-level one).
- **Fan out the remaining phases' cards** in dependency order (`01-orchestrator/PHASE_DEPENDENCY_MATRIX.md`).

---

## ▶ Confirmed client requirements (locked — must be built)

1. **Client–area segregation = ON.** Different clients' stock must **not** share a warehouse location. The build delivers the `clientAreaSegregation` system toggle + a per-Area `owningClients` set — **an Area may be reserved for one OR more clients** (empty = shared), configured via a **multi-select** on the Sites screen — and **server-side enforcement on every bin-write** (putaway · move · transfer-receive · returns-restock) via `ICapacityService.SegregationOk` (CC-02). Each client gets a **dedicated Storage Area** (mock seed: Areas D/E/F = Technip/Schlumberger/Yinson, B = Globex; Area A + Soyo Area C deliberately shared). The product/greenfield default stays OFF — this is a per-deployment config, **confirmed ON for this client**. *(Recorded across: `01-orchestrator/CROSS_CUTTING_CONCERNS.md` CC-02 · `02-phases/PHASE_01_MASTER_DATA.md` P01-S02 · `02-phases/PHASE_00_FOUNDATION.md` P00-S06 · `../docs/01_Master_Data.md` · `../docs/GLOSSARY.md` · `../docs/DATA_MODEL.md` · `../CLAUDE.md`.)*

---

## ▶ Open decisions (don't lose — flagged across the framework)

Recorded with recommendations in `01-orchestrator/HOST_INTEGRATION_MAP.md` §E. #1–#3 shape every Phase-0 card; #4–#5 affect the PWA cards.

1. **Schema authoring:** EF migrations vs DBA SQL scripts → *rec was EF migrations.* **▶ DIRECTION TAKEN (2026-06-23): hand-authored DBA SQL scripts** in `../scripts/` (per-section DDL, tables only; views/procs per-card). If the build later prefers EF migrations, generate them from these scripts and ADR it.
2. **Tenant/site scoping:** extend host `User`/`UserClaim` vs WMS-side scope table → *rec: WMS-side.* **▶ DIRECTION TAKEN (2026-06-23): WMS-side** — host `[dbo].[Users]` is untouched; WMS adds `wmsuserprofile` (role + all-sites/all-clients flags) + `wmsusersite`/`wmsuserclient` scope tables.
3. **Runtime:** stay on .NET Core 3.1 vs upgrade WMS module → *rec: stay (ADR the EOL risk).*
4. **PWA placement:** `projects/wms-scanner` in workspace vs separate repo → *rec: same workspace.*
5. **PWA offline:** hard v1 requirement vs online-only → *biggest cost swing; confirm with client.*

---

## ▶ Key files

| For… | Read |
|---|---|
| Entry point / index | `01-orchestrator/PROJECT_ORCHESTRATOR.md` |
| Host conventions (where WMS plugs in) | `01-orchestrator/HOST_INTEGRATION_MAP.md` |
| Cross-cutting registry (freeze, capacity, audit, scope…) | `01-orchestrator/CROSS_CUTTING_CONCERNS.md` |
| Estimation method & tiers | `01-orchestrator/ESTIMATION_GUIDE.md` |
| Phase files + planned cards | `02-phases/PHASE_00..08_*.md` |
| The build-card template + worked card | `01-orchestrator/SUBPHASE_TEMPLATE.md` · `02-phases/sub-phases/P03-S01_single-lpn-putaway.md` |
| Functional source of truth | `../docs/` (00–06, GLOSSARY, DATA_MODEL, BLOCKING_RULES) |
| UX reference (the mockups) | `../mockups/` + `../mockups/MOCKUP_STATUS.md` |
| Mock build history (estimation reference class) | `../docs/BUILD_LOG.md` |
| **DB schema (SQL Server 2014 DDL, per section)** | `../scripts/README.md` · `../scripts/01_master_data_schema.sql` |

---

## ▶ Restart prompt for a new session

> Paste this into a fresh session to resume with full context.

```
We're on the WMS 3PL project. The mockup phase (Phase 2) is complete and the delivery/specs
framework is scaffolded. Before doing anything, read these for context:
  1. delivery/DELIVERY_STATUS.md   (current state, the LOCKED sequence, open decisions, this prompt)
  2. delivery/01-orchestrator/PROJECT_ORCHESTRATOR.md
  3. mockups/MOCKUP_STATUS.md       (what the mockups cover)
  4. CLAUDE.md + docs/GLOSSARY.md   (vocabulary & rules)

We are in Phase 3 (specs delivery). The LOCKED sequence is:
  (1) CLIENT DOCUMENTATION  →  (2) TECHNICAL DOC + Man/Days estimation  →  (3) finalize build cards.

START WITH DELIVERABLE 1 — the CLIENT DOCUMENTATION:
Generate a Word document (.docx) — a "functional specs with print screens" guide for the client —
that presents EVERY WMS functionality. Organize it by section (Master Data, Goods Reception,
Putaway, Stock-Out, Inventory Operations, Reports) and cover BOTH channels (ERP screens + PWA
scanner screens). For each screen/feature: a screenshot of the mockup + a short description of what
it does and how to use it. Source = the mockups in mockups/*.html (serve locally, screenshot each
screen). Use the docx skill. Note: the preview screenshotter has been intermittently flaky here —
re-attempt or fall back if it stalls.

FIRST, propose the document's table of contents (the screens to include, in order, per section and
channel) and confirm it with me BEFORE capturing all screenshots and assembling the full document.
Do NOT write any application code — we are producing documentation, not implementing features.
```

---
*Functional truth = `../docs/`. UX truth = `../mockups/`. This file = live delivery status + restart prompt.*
