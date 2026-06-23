# Phase 1 — Master Data

> Everything else references these entities. Mostly the **CRUD recipe** (`../00-common-rules/COMMON_CRUD_RULES.md`)
> → mostly tier S/M and highly parallelizable once Phase 0's base classes exist.
> Functional spec: `../../docs/01_Master_Data.md`. Mock: `erp-md-*.html`, `pwa-md-lookup-*.html`.

## Objective
Deliver the master data the operational processes depend on: clients, sites (+ addressing levels + storage areas), locations, products (+ tracking flags + preferred storage), categories, UoM, packaging, partners, consignees, reason codes, users (+ WMS roles/scope), and import.

## Consumes (cross-cutting)
CC-05 (tracking flags on Product), CC-07 (reason domains), CC-08 (scoping), CC-09 (assignment filter where a master is a work-item — minimal here).

## Planned sub-phase cards
| Card | Scope | Notes | Tier |
|---|---|---|---|
| P01-S01 | Clients (+ `allowBackorder`), Suppliers, Carriers, Consignees | CRUD recipe | S–M |
| P01-S02 | Sites (+ `levels[]` addressing, `areas[]` storage areas), Locations (+ capacity, area) | areas/levels are child tables; feeds CC-02; **incl. the `clientAreaSegregation` toggle + per-area `owningClients[]` multi-select (one OR more clients per area) — client-confirmed ON** | M |
| P01-S03 | Products (+ `track` flags, category/subcat, weight, **preferred storage** per site), Categories, UoM | tracking flags drive CC-05 everywhere | M |
| P01-S04 | Packaging (shared templates + product packaging w/ per-level barcodes) | nested levels → child table; clone provenance (DATA_MODEL gap #5) | M |
| P01-S05 | Reason codes (`DB.reasonDomains` — status/adjust/correct/return/dispose/refuse/rtv/receipt/dispatch) | drives CC-07; generic editor | S |
| P01-S06 | Users + WMS role/right assignment + **client/site scope** mapping; client–user map | ties to CC-08/CC-10 (Phase 0) | M |
| P01-S07 | PWA lookups (location, product) — read-only | reuse generated client | S |
| P01-S08 | Bulk **import** (master data) | mock `erp-md-import` is stubbed; scope CSV import | M |

> **📌 Client-confirmed (CC-02):** client–area segregation runs **ON** for this client — different clients' stock must not share a location. **P01-S02 must deliver the `clientAreaSegregation` system toggle + the per-Area `owningClients[]` multi-select editor (Sites screen — one OR more clients per area, empty = shared)**, and each client gets a dedicated Area (mock seed: Areas D/E/F = Technip/Schlumberger/Yinson, B = Globex; A + Soyo-C shared). The enforcement itself is CC-02 (Phase 0 `ICapacityService.SegregationOk`), consumed by Putaway/Move/Transfer-receive/Returns-restock.

## Database schema (DDL) — DONE ahead of the cards (2026-06-23)
All Master Data tables are scripted in **`../../scripts/01_master_data_schema.sql`** (SQL Server 2014,
tables only — **no views/procs**; those are authored per-screen inside each card). 29 `wms*` tables;
lower-case names/columns; `id INT IDENTITY(1,1)` PK on every table; business ids as a separate `code`
column. The host **`[dbo].[Users]` is referenced, not recreated** (WMS adds `wmsuserprofile` +
`wmsusersite`/`wmsuserclient`). See `../../scripts/README.md`. Card → tables it touches:

| Card | Tables |
|---|---|
| P01-S01 | `wmsclient`, `wmsclientsite`, `wmssupplier`, `wmscarrier`, `wmsconsignee` |
| P01-S02 | `wmssite`, `wmssitelevel`, `wmsstoragearea`, `wmsareacategory`, `wmsareasubcategory`, `wmsareaclient`, `wmslocation`, `wmslocationpath`, `wmssetting` (segregation toggle), `wmsdefaultsitelevel` |
| P01-S03 | `wmsproduct`, `wmsproductpreferred`, `wmscategory`, `wmssubcategory`, `wmsuom` |
| P01-S04 | `wmspackaging`, `wmspackaginglevel` |
| P01-S05 | `wmsreasondomain`, `wmsreasongroup`, `wmsreason` |
| P01-S06 | `wmsuserprofile`, `wmsusersite`, `wmsuserclient` (+ host `[dbo].[Users]`) |
| P01-S07 | *(read-only over `wmslocation` / `wmsproduct` — no new tables)* |
| P01-S08 | *(bulk-loads `wmsproduct` / `wmslocation` — no new tables)* |
| *(unassigned)* | `wmslpnconfig` — LPN/SSCC numbering+label config (spec In-Scope; no mock screen yet — fold into P01-S02 settings or a dedicated settings card) |

> The composite FKs on `wmslocation` (area must match site) and `wmsproductpreferred` (chosen
> location/area must match site) back the **CC-02 client–area segregation** requirement at the schema level;
> the cross-client/bin-write enforcement itself still lives in `ICapacityService.SegregationOk` (Phase 0).

## Depends on
Phase 0 (skeleton, scoping, CRUD base, reason framework).

## Key references
`COMMON_CRUD_RULES.md`, `../../docs/DATA_MODEL.md` (entity fields), `../../docs/GLOSSARY.md` (Zone vs Area — do not conflate).

## Open questions
Which masters are WMS-owned vs shared with the host ERP (products/suppliers may already exist in `Common/GDB` — reconcile to avoid duplication). Import file formats & validation depth.

## Estimation note
Bulk of cards are S/M via the generic base service. Watch: Products (tracking-flag conditional UI/validation), Sites/Locations (areas + levels + capacity child tables), Packaging (nested levels), Users (scoping touches the shared Auth model). Highly parallel — staff several at once after Phase 0.
