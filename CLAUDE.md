# CLAUDE.md — WMS (3PL) Mockup Project

Guidance for future sessions. The **repo is the source of truth**; `docs/` is the functional
spec and `mockups/` is the agreed UX reference. Read `mockups/MOCKUP_STATUS.md` for live build
state and `docs/GLOSSARY.md` for locked vocabulary before starting.

## What this is
A Warehouse Management System for **client-owned stock in a 3PL warehouse** — an **ERP module**
(back-office) plus a **PWA scanning app** (warehouse floor). Goods belong to clients, never to the
operator's balance sheet; the system tracks traceability, location, and accountability per client.
**Current phase: click-through HTML mockups** (Phase 2). Spec → mockups → tech implementation.

## Vocabulary (locked — do not conflate)
- **Zone** = an **addressing-path level** only (one entry in `site.levels`, e.g.
  `Floor→Zone→Aisle→Rack→Bin`). Pure addressing. Never used for slotting or ownership.
- **Storage Area** / **Area** = a **managed, per-site logical grouping** for slotting +
  segregation, **decoupled from the addressing path**. Carries category affinity + optional
  owning client. Each storage bin is assigned to one Area (`location.area` → `site.areas[].code`).
- **Location** = a physical spot (bin / wait-put staging / dispatch / quarantine), identified by a
  permanent scannable **System ID** (`LOC-…`) + a derived **structured code** + optional **userRef**.
- **LPN** = the handling unit (license plate / SSCC) moved through receive → putaway → pick.
- **FEFO** = First-Expiry-First-Out; outbound allocation order, driven by lot expiry.
- Tracking flags per product: `product.track.{lot, expiry, serial}` (default: **lot + expiry ON, serial OFF** — most SKUs aren't serialised; enable serial only for serialised goods). **Expiry ⇒ lot.** The flag lives on
  the product and **drives show/hide of every Lot/Expiry/Serial field + column on every screen** (lists render a muted
  `n/a` for an untracked attribute; detail/forms omit it). Helpers: `tracksLot/tracksExpiry/tracksSerial(id)`,
  `trackingSummary(id)`. Four labelled test products exercise the combinations — `P-TCA` (none, the ~90% case) ·
  `P-TCB` (lot) · `P-TCC` (lot+expiry) · `P-TCD` (all) — each with a full ASN/putaway/stock/outbound chain and a
  `testCase` tag surfaced as a grid badge (`testCaseNote(id)` / `docCaseNote(lines)`). Serials are **scanned off the unit, not auto-generated** (auto-gen is a demo shortcut only).
- **Consignee** = a client's **ship-to / delivery point** (`DB.consignees`, client-scoped). An outbound order ships to a consignee (`order.shipTo`), **NOT** to the owning client — *client = stock owner; consignee = destination.* **Supplier** / **Carrier** = global trading-partner masters (ASN inbound source / dispatch outbound mover).

## Tech & hard rules
- **Plain HTML + one shared CSS (`mockups/assets/wireframe.css`) + vanilla JS. NO build step.**
  Opens via `file://`. No frameworks, no bundler, no npm.
- **Every HTML file MUST sit beside `mockups/assets/`** (i.e. directly in `mockups/`), or the
  relative `assets/…` CSS/JS links won't load.
- **Shell-injection gotcha (critical):** `erp-shell.js` / `pwa-shell.js` rebuild `document.body`
  from the **innerHTML of `#page-content` ONLY**. Anything outside `#page-content` — modals,
  overlays, **and screen-local `<style>` blocks** — is **discarded**. RULE: ALL markup **and**
  every screen-local `<style>` must live **INSIDE** `#page-content`.
- Screen scripts load `assets/data.js` then the shell (`assets/erp-shell.js` or
  `assets/pwa-shell.js`), then the screen's own `<script>`.

## How screens are wired
- **Nav lives only in `erp-shell.js`** (`SECTIONS` array → topbar + iconed expandable sidebar).
  Stock-Out nav entries: `erp-so-orders.html`, `erp-so-alloc.html`, `erp-so-dispatch.html`,
  `erp-so-fulfil.html` (Express), `erp-so-note.html`. PWA chrome comes from `pwa-shell.js`.
- A screen sets `data-erp-active`, `data-erp-title`, `data-erp-crumb` on `<body>`; the shell reads
  these. `data-erp-active` must match the nav child id (e.g. `so-orders`) to highlight the item.
- **`mockups/assets/data.js` is the single linked mock dataset.** IDs cross-reference across
  screens (an LPN received in GR appears as a Putaway task, then as stock, then gets picked).
  Helpers: `dbName(coll,id)`, `prodName(id)`, `catName/subCatName(id)`, `unitWeight(id)`,
  `siteAreas(siteId)`, `areaInfo(siteId,code)`, `statusBadge(status)`, `asnTotals/asnStatus(a)`,
  `consigneesFor(clientId)`/`consigneeName(id)`, `isLocFrozen/frozenTakeFor(locId)`, `binCapacityForAdd/binSegregationOk(...)`.
  ID prefixes: `C-`/`S-`/`LOC-`/`P-`/`LPN-`/`ASN-`/`OUT-`/`U-`/`CAT-`/`SUB-`/`PKG-`/`SUP-`/`CAR-`/`CNE-`.
- File naming: `erp-<section>-<screen>.html`, `pwa-<section>-<screen>.html`. Section codes:
  `md` master data, `gr` goods reception, `pa` putaway, `so` stock-out, `inv` inventory, `rpt` reports.
- **8 reusable patterns (build once, clone):** list+form · document-list (title+actions, tabs,
  filter grid, toolbar, grouped funnel table) · dashboard · report · scan-flow (PWA) · lookup
  (PWA) · document/print · wizard. Reference screens: `erp-gr-asn.html` (document-list + create/
  edit), `erp-pa-tasks.html` (list↔detail with algorithm), `erp-gr-grn.html` (document/print).

## Build strategy
- **Finish ALL ERP sections first, then sweep the PWA screens as a batch.**
- **ALL ERP sections COMPLETE** — Master Data, Goods Reception, Putaway, Stock-Out, Inventory Ops, Reports —
  **plus a pre-PWA global review + hardening pass (2026-06-17).** **▶ PWA sweep COMPLETE (2026-06-19) — all 16 PWA
  screens built & verified; both channels finished, so the mockup phase (Phase 2) is done.** See `mockups/MOCKUP_STATUS.md` for the full log.
- **Pre-PWA hardening added (v1):** Suppliers & Carriers master (`erp-md-partners.html`) + Consignees/ship-to
  (`erp-md-consignees.html`); **ship-to consignee on outbound** (order ships to a consignee, not the client) +
  carrier on dispatch/note; **order + line cancellation** (`cancelled`) and **de-allocation** (release → open);
  **found/missing** count & physical lines. Anchors touched: `data.js`, `erp-shell.js`, `wireframe.css`.
- **Locked enforcement rules (mock + mandatory in coding):** (1) physical-inventory **freeze is enforced
  cross-screen** — Putaway/Move/Transfer-ship/Allocation refuse a `frozen`-scope location (`isLocFrozen`);
  (2) **every bin-write runs shared capacity + segregation** (`binCapacityForAdd`/`binSegregationOk`): Putaway,
  Move, Transfer-receive, Returns direct-restock; (3) **serials required on every issue path** (classic Dispatch
  + Express Fulfil). Seed stock-takes start `open` so demos aren't smothered.
- Stock movements (intra-site + inter-site) are in v1. Capacity + client–area segregation
  enforcement are in v1. **Client–area segregation is a CONFIRMED requirement for this client (no mixing
  different clients in one location): the seed ships it ON (`settings.clientAreaSegregation:true`) with a
  dedicated Storage Area per client (D/E/F = Technip/Schlumberger/Yinson, B = Globex; A + Soyo-C shared).
  The product/greenfield default stays OFF — per-deployment config, not a code default.** Client portal &
  billing are OUT of v1.
- **Outbound: two fulfilment paths, offered per action** — the Orders list shows **both** `Allocate ›`
  (classic: separate Allocate/Pick/Dispatch screens) and `Express fulfil ›` (one-pass `erp-so-fulfil.html`)
  on every open/`partial` order. **Express Fulfil is to be role-gated in the coding phase** (separate-team
  sites won't grant the right → only Allocate shows); shown to all in the mock. Serials + short/blocked
  stock always pause for review. *(The old `site.fulfilmentMode`/`modeOverride` setting was removed.)*
- **Outbound remainder handling** (`client.allowBackorder`): a short shipment either **back-orders**
  the remainder (order → `partial`, re-allocates the remaining qty, multiple delivery notes) or
  **short-closes** it (`dispatched` + `shortClosed`, remainder cancelled). Cumulative `line.shipped`
  + immutable `order.shipments[]` (one Delivery Note each). Allocation/Express run on `lineRemaining`.

## Working method
- **Edit files in place.** Validate JS/structure by running `node` (e.g. syntax-check, or eval the
  data helpers); there is no app server. The user reviews diffs.
- **Commit per screen.**
- Keep `data.js` cross-references stable — when a screen needs new state (e.g. allocation/pick
  detail on outbound orders), extend the existing entities rather than forking parallel data.
- When `wireframe.css`, a shell, or `data.js` changes, note it — those are shared anchors that
  affect every screen.

## Conventions to match (visual/UX)
ERP-themed wireframes: blue topbar, iconed expandable sidebar, Material underline inputs, dense
grouped "funnel" tables, uppercase buttons. Click-through happy paths navigate; data is mock.
Tracking inputs (Lot/Expiry/Serial) render only when the product's flag is on. "Today" is mocked
around 2026-06-15 for expiry warnings.
