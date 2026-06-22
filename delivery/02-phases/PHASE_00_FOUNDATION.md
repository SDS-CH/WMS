# Phase 0 — Foundation / Kernel

> **Builds the cross-cutting kernel once, so no later phase is reopened to retrofit it.** Mostly enabling
> work (interfaces + plumbing), not user features. **Its interfaces must be frozen before any process phase fans out.**
> Consumes nothing; **produces** CC-01…CC-12 (`../01-orchestrator/CROSS_CUTTING_CONCERNS.md`).

## Objective
Stand up the WMS module inside the host (backend + ERP + PWA shells), the SQL 2014 schema foundation, and the shared services every process consumes.

## In scope
Module skeleton & wiring · DB foundation & audit ledger · tenant/site scoping · the cross-cutting services · the assignment + tracking-flag plumbing · the PWA shell & scan engine.

## Out of scope
Any process feature (those are Phases 2–6). Master-data CRUD (Phase 1).

## Planned sub-phase cards
| Card | Scope | Produces | Tier |
|---|---|---|---|
| P00-S01 | Backend module skeleton (7 projects), DI `ContainerExtension`, gateway route, **Swagger publish pipeline**; Angular `projects/wms` + `projects/wms-scanner` shells, routing, `@wms/*` alias | the slice rails | M |
| P00-S02 | `WmsDbContext`, base entity/audit-field convention, **migration strategy (decision #1)**, **`WmsTxn` audit table**, seed/fixtures from `data.js` | DB foundation, CC-03 store | L |
| P00-S03 | **`ITenantScopeService`** (client+site filter+assert) + WMS role/claim integration (decision #2) | CC-08, CC-10 | L |
| P00-S04 | **`IStockLedgerService.LogTxn`** (append-only, in-transaction) | CC-03 | M |
| P00-S05 | **`IFreezeService`** (`IsLocationFrozen`/`FrozenTakeFor`) | CC-01 | M |
| P00-S06 | **`ICapacityService`** (capacity + segregation, single source of truth — **segregation is client-confirmed ON; enforce `SegregationOk` server-side on every bin-write**) | CC-02 | M |
| P00-S07 | **`IAllocationService`** interface + FEFO/FIFO + reservation-aware availability core | CC-06 | L |
| P00-S08 | **`IReasonService`** + approval / maker-checker framework (`sameActor`) | CC-07 | M |
| P00-S09 | **Assignment facet** (`assignee` + My-tasks/claim) + **tracking-flag** DTO plumbing | CC-09, CC-05 | M |
| P00-S10 | PWA shell: scan engine (BarcodeDetector + ZXing + manual + list), service worker, **offline strategy (decision #5)**, shared models/client | PWA rails | L |

## Depends on
Host access; **integration decisions #1–#5** resolved (`../01-orchestrator/HOST_INTEGRATION_MAP.md` §E) — these gate S02/S03/S10.

## Key references
`CROSS_CUTTING_CONCERNS.md`, `HOST_INTEGRATION_MAP.md`, `COMMON_BACKEND/DATABASE/SECURITY_RULES.md`, `../../docs/DATA_MODEL.md`, `../../docs/BLOCKING_RULES.md`.

## Open questions
Decisions #1–#5. Plus: `@ngrx/entity` adoption; optimistic-concurrency token on `WmsLpn`; FluentValidation yes/no.

## Estimation note
Highest-leverage phase: estimate carefully, amortize across the project (it's enabling, not per-feature). The CC services are the riskiest contracts — freeze them early; expect some churn as the first consumers (Phase 2/3) exercise them.
