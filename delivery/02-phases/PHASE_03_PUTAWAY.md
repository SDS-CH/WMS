# Phase 3 — Putaway

> Place received stock into storage via directed slotting, enforcing capacity/segregation/freeze. Dual-channel.
> Functional spec: `../../docs/03_Putaway.md`. Mock: `erp-pa-tasks.html`, `pwa-pa-putaway.html`.

## Objective
Move `to-putaway` LPNs (single and mixed-pallet) into bins with ranked-bin suggestion, capacity + segregation + freeze guards, partial putaway (split for remainder), and damage-found handling.

## Consumes (cross-cutting)
CC-01 freeze, CC-02 capacity+segregation, CC-03 audit, CC-04 conservation, CC-08 scoping, CC-09 assignment.

## Planned sub-phase cards
| Card | Scope | Tier |
|---|---|---|
| P03-S01 | **Single-LPN directed putaway** — ranked bins (home→consolidate→category→open), capacity/segregation/freeze, **partial putaway** (qty-to-place + child LPN), `putawayPlace` | L |
| P03-S02 | **Mixed-pallet decomposition** — scan pallet, place each line (operator-chosen order) → child LPNs, pallet closes when empty | L |
| P03-S03 | **Damage-found-at-putaway reject** (`putawayReject` → blocked child at QA), **overflow-park**, **resume / partial-progress** visibility (Completed tab, progress panels) | M |

> **Dev-card decomposition (2026-07-04):** the ERP page (erp-pa-tasks.html) is decomposed into 9
> per-functionality cards under `SDS-ERP-SOLUTION/WMSProject/cards/putaway/` — **P03-S01** →
> 01 PUT-WORKLIST-BACKEND · 02 PUT-SUGGEST-BACKEND (the ranked-bin engine, shared ICapacityService
> as flagged below) · 03 PUT-PLACE-BACKEND (place/split/park) · 06 PUT-TASKS-SCREEN ·
> 07 PUT-PLACE-SCREEN; **P03-S02** → 04 PUT-PALLET-BACKEND · 08 PUT-PALLET-SCREEN; **P03-S03** →
> 05 PUT-REJECT-BACKEND · 09 PUT-REJECT-SCREEN (park + progress folded into 03/01/06/07).
> NO new DDL needed (putaway runs on the 01/02 tables; 'putaway'/'park'/'status' already in the
> wmstxn CHECK). Freeze guard (CC-01) STUBBED behind IFreezeService until Inventory Ops' schema.
> New role: family `WMS - Putaway` / `Putaway Operator`. PWA putaway = still to decompose.
> Progress truth = the cards' frontmatter + `cards/putaway/_progress.md` (`/progress-wms putaway`).

## Depends on
Phase 0 (freeze, capacity, audit, conservation, scoping), Phase 1 (locations + areas + capacity, products + preferred storage), Phase 2 (LPNs to put away).

## Key references
`../../docs/03_Putaway.md`, `../../docs/BLOCKING_RULES.md` (capacity/freeze rows), `../../EDGE_CASE_TRACKER.md`, mock test findings #3/#4/#5/#7 (`../../mockups/MOCKUP_STATUS.md`).

## Open questions
None major — the mock resolved partial putaway, decompose order, progress visibility, and damage-reject. Ensure the build uses the **shared** `ICapacityService` (mock `erp-pa-tasks` had a local impl — flagged carry-over).

## Estimation note
Both placement cards are L (ranked-bin logic + conservation + dual-channel). S03 bundles three resolved enhancements; M. This phase is the cleanest showcase of consuming the Phase-0 kernel — see the worked card in `../01-orchestrator/SUBPHASE_TEMPLATE.md`.
