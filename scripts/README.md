# WMS — Database Schema Scripts

SQL Server **2014** DDL for the WMS module, built **section by section** (not all at once),
**ahead of** the per-screen development cards. Each section gets its own script file; tables only —
**views and stored procedures are deliberately excluded** and will be added step-by-step during the
dev phase of each Master Data / operational screen (inside the build cards).

> Functional source of truth: `../docs/01_Master_Data.md`, `../docs/DATA_MODEL.md`, `../docs/GLOSSARY.md`.
> Persistence rules: `../delivery/00-common-rules/COMMON_DATABASE_RULES.md`.

## File index

| # | File | Section | Status | Tables |
|---|------|---------|--------|--------|
| 00 | `00_identity_roles_seed.sql` | **WMS role families + roles** — ⚠ runs against the **HOST IDENTITY DB** (Users/Roles/RoleFamilies/ERPModules), once per environment, NOT per agency | ✅ done | — |
| 01 | `01_master_data_schema.sql` | **Master Data** | ✅ done | 29 |
| 01 | `01_master_data_seed.sql` | Master Data reference/seed rows (UoM units, base reason domains) | ✅ done | — |
| 01 | `01_master_data_updates.sql` | **Structure updates** for already-provisioned DBs (see policy below) | ✅ done | — |
| 02 | `02_goods_reception_schema.sql` | Goods Reception (ASN, receipts, pallets, inspection, GRN, refusal) + shared core (LPN, txn ledger, attachments) | ✅ done | 16 |
| 02 | `02_goods_reception_seed.sql` | Goods-Reception reason domains (receipt / refuse / discrepancy) | ✅ done | — |
| 03 | `03_putaway_schema.sql` | Putaway — **no new tables** (operates on `wmslpn`/`wmspallet`/`wmstxn` from 02) | n/a | 0 |
| 04 | `04_stock_schema.sql` | Stock / LPN visibility — **no new tables** (SoH is derived from `wmslpn`, the locked Phase-0 decision; the visibility screens read 02's tables) | n/a | 0 |
| 05 | `05_stock_out_schema.sql` | Stock-Out (outbound orders + lines, live allocation/reservation, shipment = delivery-note snapshot, RTV) | ✅ done | 10 |
| 05 | `05_stock_out_seed.sql` | Stock-Out reason domain (`rtv` — the `dispatch` ad-hoc domain was seeded in 01) | ✅ done | — |
| 06 | `06_inventory_ops_schema.sql` | Inventory Ops — **the last table set** (physical inventory = the cross-section **freeze guard's data**, cycle counts incl. the F8 `pick-not-found` sheets, move, transfer, adjust/correct, repack, returns, disposal) | ✅ done | 18 |
| 06 | `06_inventory_ops_seed.sql` | Inventory-Ops reason domain (`dispose` — group keys = `wmsdisposal.method` values). Completes the reason-domain set. | ✅ done | — |
| 07 | `07_reports_schema.sql` | **Reports** — stored procedures ONLY, appended card-by-card, now COMPLETE for all 10 Phase-7 reports (`wmsrpt_soh`, `wmsrpt_txns`, `wmsrpt_expiry`, `wmsrpt_inbound`, `wmsrpt_outbound`, `wmsrpt_variance`, `wmsrpt_utilization`, `wmsrpt_trace_lots/_plates/_events`, `wmsrpt_stockcard`, `wmsrpt_statement`); reads the 01–06 tables (the txn ledger / attachments were created up-front in 02); no new tables | ✅ first-executed on dev 2026-07-06 (soh+txns verified live) — **re-run to deploy the remaining 10 procs** | 0 (12 SPs) |
| 08 | `08_pwa_foundation_schema.sql` | **PWA Foundation** — the scanner app's action/debug trail (`wmsactionlog`, append-only, idempotent batch ingest via the `(deviceid, entryid)` unique guard; read by the ERP's PWA Activity Log screen) | ⚠ authored 2026-07-06 — NOT yet executed on dev | 1 |
| 08 | `08_pwa_auth_config.sql` | **PWA token expirations** — ⚠ runs against the **HOST AUTH DB** (adds `PwaAccessTokenExpiration` / `PwaRefreshTokenExpiration` to `[dbo].[ERPGlobalConfigs]`, minutes, NULL→global fallback; seeds 1440/10080), once per environment, NOT per agency | ⚠ authored 2026-07-06 — NOT yet executed | — |

Run order is the numeric order, schema before seed (later sections FK back to Master Data).

> **Dev execution status — 2026-07-05: ALL scripts (00–06) are EXECUTED on the dev environment**
> (`00_identity_roles_seed.sql` on the host identity DB — 4 families · 20 roles; the section
> schemas + seeds on the dev agency DB). Every file stays idempotent/re-run-safe — after appending
> new roles or tables, simply re-run the touched file. A fresh environment (e.g. PROD) runs the
> numbered files in order from scratch.

## Privileges / roles policy (00_identity_roles_seed.sql)

Every WMS card with a user-facing surface declares a **"### 🔐 Privileges"** section (Role Family +
Role Name); the backend enforces it with `[Authorize(Roles = "...")]` on **mutating** endpoints
(reads stay `[Authorize]`), and the frontend hides menus/buttons via `data.roles` +
`SdsAccessChecker`. **Any card that introduces a NEW role must, in the same pass, append it to
`00_identity_roles_seed.sql`** (guarded insert; add the family too if new) — that file is the single
seeding source and is idempotent. Role registries live in each section's
`SDS-ERP-SOLUTION/WMSProject/cards/<section>/_progress.md` (Decisions). User↔role assignment is NOT
seeded — host admin (Users & Roles screen / groups).

## Structure-update policy (canonical files vs already-executed DBs)

The numbered schema files are **canonical**: when an already-shipped table changes, its `CREATE TABLE`
block is edited **in place**, so a fresh environment (e.g. PROD) gets the full current structure from
the numbered files alone. Because those CREATE blocks are `IF OBJECT_ID(...) IS NULL`-guarded, an
edited block **no-ops on a database that already executed the file** — so every such change is *also*
appended as a dated, guarded `ALTER` block to the companion **`*_updates.sql`** file
(`01_master_data_updates.sql` for Master Data). Run the updates file on existing dev DBs to catch up;
it is idempotent and no-ops on a freshly-provisioned DB. Constraint names are identical in both files.

## Conventions (hard constraints, all sections)

- Table names are **lower-case**, prefixed **`wms`** (e.g. `wmsclient`).
- Column names are **lower-case, no spaces**.
- Every table has **`id INT IDENTITY(1,1)` PRIMARY KEY** (auto-increment surrogate).
- Human/business ids (`C-…`, `S-…`, `LOC-…`, `P-…`, …) are a separate **`code`** business-key
  column (unique per scope) — never the PK.
- Audit columns on aggregate roots: `createdby / createdat / editby / edittime`
  (`createdby`/`editby` reference `[dbo].[Users].[Id]` logically — not FK-bound).

## SQL Server 2014 notes

- **No JSON / OPENJSON (2016+):** the mock dataset's nested arrays become **child tables** with FKs.
- **No temporal tables (2016+):** change history is the (later) `WmsTxn`-style ledger + audit columns.
- Quantities/weights `DECIMAL(18,3)` (never `FLOAT`); dates `DATETIME2`; enums = `VARCHAR` guarded by
  `CHECK`. Re-run safety via `IF OBJECT_ID(...) IS NULL` (2014-compatible; no `DROP … IF EXISTS`).

## Users — host-owned, not created here

The user master already exists as the host identity table **`[dbo].[Users]`**
(`Id, UserName, Email, Password, FirstName, LastName, IsActive, EditTime, Photo, IsBlocked`;
active = `IsActive = 1 AND (IsBlocked IS NULL OR IsBlocked = 0)`). The scripts **reference** it; they
do not recreate it. Because the shared Auth table must not be altered, WMS-specific user data lives in
WMS-owned tables: `wmsuserprofile` (WMS role + all-sites/all-clients flags, 1:1 → `Users.Id`) and the
scope link tables `wmsusersite` / `wmsuserclient`.

## Master Data (01) — table inventory

| Group | Tables | Master Data screen(s) |
|---|---|---|
| System / lookup | `wmssetting`, `wmsuom`, `wmsdefaultsitelevel` | sites (segregation toggle, default levels), uom |
| Taxonomy | `wmscategory`, `wmssubcategory` | categories (+ pickers on products, sites) |
| Parties | `wmsclient`, `wmssupplier`, `wmscarrier`, `wmsconsignee` | clients, partners, consignees |
| Sites & storage | `wmssite`, `wmsclientsite`, `wmssitelevel`, `wmsstoragearea`, `wmsareacategory`, `wmsareasubcategory`, `wmsareaclient`, `wmslocation`, `wmslocationpath` | sites, clients (operating sites), locations |
| Products & packaging | `wmsproduct`, `wmsproductpreferred`, `wmspackaging`, `wmspackaginglevel` | products, uom (shared templates), import (bulk) |
| Users & scope | `wmsuserprofile`, `wmsusersite`, `wmsuserclient` (+ host `[dbo].[Users]`) | users, clientmap |
| Reason codes | `wmsreasondomain`, `wmsreasongroup`, `wmsreason` | reasons |
| LPN config | `wmslpnconfig` | *(spec In-Scope; no mock screen yet — future settings screen)* |

PWA read-only lookups (`pwa-md-lookup-loc.html`, `pwa-md-lookup-prod.html`) query `wmslocation` /
`wmsproduct`; no new tables.

## How to run

```sql
USE [WMS];   -- select your WMS database first
-- then execute 01_master_data_schema.sql (re-runnable; non-destructive)
```

## Verification

`01_master_data_schema.sql` was adversarially reviewed across 5 lenses (completeness vs spec/model,
SQL-2014 compatibility, hard-constraint compliance, relational integrity, fidelity to the mock dataset)
plus a static structural check (29 tables · identity PK on each · no forward-reference FKs ·
composite-FK targets present · no views/procs/2016+ features). All scripts have since been executed
on the live dev SQL Server instance (2026-07-05) — see the dev execution status above.
