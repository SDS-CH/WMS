# Phase 2 — Goods Reception (Inbound)

> First stock-creating process: ASN → receive → inspect → GRN, minting LPNs. Dual-channel.
> Functional spec: `../../docs/02_Goods_Reception.md`. Mock: `erp-gr-*.html`, `pwa-gr-*.html`.

## Objective
Receive goods against an ASN or blind, mint LPNs (with split + mixed-pallet models), inspect with partial accept/reject + dispositions, and produce GRNs and labels — all with full traceability and the unhappy paths.

## Consumes (cross-cutting)
CC-03 audit, CC-04 conservation+genealogy, CC-05 tracking flags, CC-07 reason codes (inspect/refuse/receipt), CC-08 scoping, CC-09 assignment.

## Planned sub-phase cards
| Card | Scope | Tier |
|---|---|---|
| P02-S01 | ASN management (CRUD, lines, derived `open/partial/closed` status, blind vs open) | M |
| P02-S02 | **Receive against ASN + blind** → mint LPNs, **LPN split** (per-each / per-pack), close-short, wrong-client guard | L |
| P02-S03 | **Mixed-pallet build** (aggregate LPN, post-hoc add lines, manifest label) + decomposition hand-off to Putaway | L |
| P02-S04 | **Inspect** — partial accept/reject (`inspectionSplit`), dispositions quarantine/hold/damaged, reason codes | L |
| P02-S05 | **GRN** (document/print, per-receipt) | M |
| P02-S06 | **Labels / reprint** (LPN + pallet, recovery by ASN/recent) — audit every reprint | M |
| P02-S07 | Edge cases: **refuse delivery at door** (no stock, ASN→refused), over-receipt approval, duplicate-receipt guard, damaged/short receive + write-off, expired-stock-blocked-at-receipt, temp-excursion/seal-broken reasons, cold-chain carrier warning | L |

> **Dev-card decomposition (2026-07-03):** the build cards live in the dev tree
> (`SDS-ERP-SOLUTION/WMSProject/cards/goods-reception/`), split **per screen functionality**
> (user-confirmed granularity), not 1:1 with the sub-phases above. Mapping so far:
> **P02-S01 (ASN)** → GR-FOUNDATION-BACKEND · GR-ASN-CRUD-BACKEND · GR-ASN-VOID-BACKEND ·
> GR-ASN-LIST-SCREEN · GR-ASN-EDITOR-SCREEN · GR-ASN-VOID-SCREEN; the **refuse-at-door row of
> P02-S07** → GR-REFUSAL-BACKEND · GR-REFUSAL-SCREEN (shared modal, reused by the Receive screen).
> **P02-S02 (Receive + splits + inline create)** → 09 GR-RECEIVE-CRUD-BACKEND · 10 GR-RECEIVE-
> CONFIRM-BACKEND · 13 SHELL · 14 LINES · 15 CONFIRM screens, + 12/17 GR-RECEIVE-QUICKCREATE-* ;
> **P02-S03 (Mixed pallet)** → 11 GR-PALLET-BACKEND · 16 GR-PALLET-SCREEN (decomposition = Section
> 03); the **over-receipt / duplicate-receipt / expired-blocked / wrong-client rows of P02-S07**
> are folded into 09/10/14. **P02-S04 (Inspect)** → 18 GR-INSPECT-BACKEND (worklist + lookups) ·
> 19 GR-INSPECT-DECIDE-BACKEND (the accept/reject/partial `inspectionSplit` orchestration) ·
> 20 GR-INSPECT-LIST-SCREEN · 21 GR-INSPECT-DECIDE-SCREEN (new role: Quality Inspector).
> **P02-S06 (Labels/reprint)** → 22 GR-LABELS-BACKEND (resolve/recent/by-ASN + the audited
> 'reprint' txn) · 23 GR-LABELS-SCREEN (⚠ gated on MD-BARCODE-FOUNDATION; print = Receiving
> Operator). **P02-S05 (GRN)** → 24 GR-GRN-BACKEND (list + immutable document payload + mark-sent)
> · 25 GR-GRN-SCREEN (printable document; GRN data itself is minted by card 10).
> **Decomposition COMPLETE — all sub-phases mapped to dev cards 01–25.**
> Progress truth = the cards' frontmatter + `cards/goods-reception/_progress.md` (`/progress-wms gr`).

## Depends on
Phase 0 (audit, conservation, tracking, reasons, scoping), Phase 1 (clients, products, packaging, suppliers, locations/staging).

## Key references
`../../docs/02_Goods_Reception.md`, `../../docs/BLOCKING_RULES.md`, `../../EDGE_CASE_TRACKER.md` (refuse/over/duplicate/damaged/expired rows), `../../docs/DATA_MODEL.md` (ASN, LPN, Pallet, GRN, Refusal).

## Open questions
Label printer integration (hardware/format) — mock prints Code-128 client-side; production needs a print service. Mixed-pallet line-reject was deferred in the mock.

## Estimation note
Receive + Inspect + Mixed-pallet are the L cards (split/genealogy/conservation + dual-channel). Edge-case card bundles many EDGE_CASE rows — could split per-risk if estimating granularly.
