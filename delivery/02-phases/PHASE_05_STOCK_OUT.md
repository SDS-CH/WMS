# Phase 5 — Stock-Out (Outbound)

> The most complex process: orders → allocation (FEFO/FIFO) → pick/dispatch → delivery notes, with back-order/
> short-close, two fulfilment paths, ad-hoc dispatch, and RTV. Dual-channel.
> Functional spec: `../../docs/04_Stock_Out.md`. Mock: `erp-so-*.html`, `pwa-so-*.html`.

## Objective
Fulfil outbound requests: allocate the right lots/serials (FEFO), pick by scan, confirm dispatch (issue stock), and produce delivery notes — honouring per-client back-order policy, ship-to consignee, serial-on-issue, and role-gated express/ad-hoc paths.

## Consumes (cross-cutting)
CC-01 freeze-exclude, CC-03 audit, CC-04 conservation, CC-06 FEFO/FIFO + reservation, CC-07 reason, CC-08 scoping, CC-09 assignment, CC-10 role-gating (Express, Ad-hoc).

## Planned sub-phase cards
| Card | Scope | Tier |
|---|---|---|
| P05-S01 | **Outbound orders** (`erp-so-orders`) — CRUD, lines, **ship-to consignee** (required at save), `fullStockOut`, cancel order / cancel line (+ restore), release allocation, status flow, assignee dispatch (CC-09), order barcode label, header/line photo+note evidence | M–L |
| P05-S02 | **Allocation** engine surface (`erp-so-alloc`) — FEFO if expiry else FIFO, reservation-aware free qty, short-allocation (over-allocation blocked), manual override per LPN, **frozen stock-take exclusion surfaced as an explained short**, release/cancel mid-flight | L |
| P05-S03 | **Pick / Dispatch** (classic, `erp-so-dispatch`) — scan-confirm pick with **mis-pick location guard (audited override)**, serials-on-issue (**count + duplicate validated, F15**), short-pick, **damage-at-pick → quarantine peel (F8)**, **stock-not-found → auto count sheet (F8)**, **carrier + proof-of-load**, consignee+carrier re-assert (F21), **commit-time re-validation of every plate (C1)**, cold-chain carrier warning (F20), issue stock (per-LPN `dispatch` txn), **Delivery Note** | L |
| P05-S04 | **Express Fulfil** (`erp-so-fulfil`, one-pass allocate→pick→dispatch, same F8/F15/F20/F21/C1 guards) — **role-gated** | L |
| P05-S05 | **Back-order vs short-close** remainder handling + multi-shipment delivery notes (immutable `shipments[]`) + **Delivery-Note register/print** (`erp-so-note` — one note per shipment `DN-{order}-{seq}`, ordered-vs-shipped, serial appendix, outcome note, signature block, snapshot never re-derived) | M |
| P05-S06 | **Ad-hoc / emergency dispatch** (inline order, governance gate, role-gated, post-hoc approval) + **ERP approval-queue surfacing** of the `approval:'pending'` flag (mock carry-over — DDL carries `adhoc` + `approvalstatus` on the order) | L |
| P05-S07 | **Return-to-vendor / client (RTV)** — non-consignee outbound (`erp-so-rtv`): destination **supplier OR owning client**, available **or blocked** plates, mandatory `rtv`-domain reason, partial-qty lines, ship issues stock (`rtv` txn) + printable RTV note; PWA scan-confirm & ship. **Build must close 4 mock gaps:** no cancel/void path, no carrier capture, no C1-style re-validation at ship, and **open-RTV plates are invisible to the allocation reservation math** (an open RTV's plate can be concurrently reserved by a customer order — include open `wmsrtvline` rows in free-qty / `ordersReserving`). DDL pre-provisions the first three; the fourth is a build rule | M |
| P05-S08 | PWA pick/dispatch + ad-hoc + RTV parity | L |

## Depends on
Phase 0 (allocation, freeze, audit, conservation, reasons, scoping, roles), Phase 1 (consignees, carriers, clients incl. `allowBackorder`), Phase 4 (stock read model). Stock from Phases 2–3.

## Key references
`../../docs/04_Stock_Out.md` (the long build notes — two paths, remainder policy, consignee/carrier, de-allocation/cancel, ad-hoc), `../../docs/BLOCKING_RULES.md` (allocation row), `../../EDGE_CASE_TRACKER.md` (dispatch re-validation, damage-at-pick, serial count/dup), **`../../scripts/05_stock_out_schema.sql` + `05_stock_out_seed.sql`** (the section DDL — 10 tables + the `rtv` reason domain; the column/CHECK source of truth for every P05 backend card).

## Open questions
~~Partial-LPN reservation persistence (DATA_MODEL gap #4)~~ and ~~delivery-note immutability (snapshot vs re-derive)~~ — **both RESOLVED by `05_stock_out_schema.sql`**: reservations persist as `wmsallocation` rows (free qty = plate qty − live reservations of orders in allocated/picking/picked; rows removed on release/cancel/dispatch), and delivery notes are **immutable snapshot tables** (`wmsshipment` / `wmsshipmentline` / `wmsshipmentlineserial` — reprint never re-derives from order state). Still open: the full WMS role/right matrix for Express/Ad-hoc/Self-claim (build phase, with the cards' 🔐 Privileges sections).

## Estimation note
Several L cards; allocation (CC-06) is the riskiest engine — its interface was started in Phase 0 but matures here. Dual-channel doubles the pick/dispatch UI. Back-order/short-close + multi-shipment is fiddly state. This phase likely the largest single estimate.
