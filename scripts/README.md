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
| 01 | `01_master_data_schema.sql` | **Master Data** | ✅ done | 29 |
| 02 | `02_goods_reception_schema.sql` | Goods Reception (ASN, GRN, receipts) | ⬜ planned | — |
| 03 | `03_putaway_schema.sql` | Putaway (tasks, pallets) | ⬜ planned | — |
| 04 | `04_stock_schema.sql` | Stock / LPN visibility | ⬜ planned | — |
| 05 | `05_stock_out_schema.sql` | Stock-Out (orders, allocation, shipments, RTV) | ⬜ planned | — |
| 06 | `06_inventory_ops_schema.sql` | Inventory Ops (move, transfer, count, physical, repack, returns, adjust, disposal) | ⬜ planned | — |
| 07 | `07_audit_reports_schema.sql` | Transaction ledger / attachments (Reports read these) | ⬜ planned | — |

Run order is the numeric order (later sections FK back to Master Data).

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
composite-FK targets present · no views/procs/2016+ features). It has **not** yet been executed against
a live SQL Server 2014 instance — run it once on the target DB to confirm.
