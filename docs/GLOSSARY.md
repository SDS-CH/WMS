# Glossary — WMS Domain & Locked Vocabulary

> Single source of truth for terminology. If a term here conflicts with prose elsewhere, **this file wins.**
> Written for the transition from mockups to the coding phase: read this before naming entities, tables, or fields.

## Critical distinctions (do not conflate)

| Term | What it is | What it is **not** |
|------|------------|--------------------|
| **Zone** | An **addressing-path level** in a site's location structure (e.g. `Floor→Zone→Aisle→Rack→Bin`). Pure addressing; no factors, no slotting. | Not a slotting group, not an owner boundary. |
| **Storage Area** (**Area**) | A **managed, per-site logical grouping** for slotting + segregation, **decoupled from the addressing path**. Carries category affinity + optional owning client. | Not an addressing level; renaming `Zone…Bin` never changes it. |
| **Location** | A physical spot (storage bin, staging, dispatch, quarantine). | Not an Area; a storage Location is *assigned to* one Area. |
| **Wait/Put** | A **staging location type** that holds LPNs awaiting putaway. | Not a Zone, not an Area. |

## Core entities

- **Client (Principal / Owner)** — owns the stock (3PL: never on the operator's books). Attached to one or more **operating sites**.
- **Supplier** — **global** master; the source of inbound goods, referenced on an ASN header.
- **Carrier** — **global** master; who physically moves stock out, recorded on a dispatch / delivery note.
- **Consignee (ship-to)** — a **client-scoped** delivery point (the client's store / hospital / end customer). An outbound order ships to a **consignee**, *not* to the client — the client owns the stock, the consignee receives it. (Do not conflate: *client* = owner; *consignee* = destination.)
- **Site / Warehouse** — a physical facility. Owns (a) its ordered **addressing levels** and (b) its list of **Storage Areas**.
- **Location** — a spot in a site. Identity in three layers:
  - **System ID** — auto-generated, permanent, unique per site; the scannable key; never changes.
  - **Structured code** — human-readable, derived from the level path (e.g. `1-A-01-R1-B01`); regenerates if structure changes.
  - **User reference** — optional free-text label.
  - Functional **type**: `storage` | `wait/put` (staging) | `dispatch` | `quarantine`.
  - Storage locations also carry an assigned **Area** and optional **capacity**.
- **Storage Area** — `{ code, name, preferredCategories[], preferredSubCategories[], owningClient }`, per site.
- **Category / Sub-category** — a **global, cross-client** product taxonomy (same posture as UoM).
- **Reason code** — a configurable, master-data reason string (Section 01, `erp-md-reasons.html`) that an operator must pick when posting an inventory action. Belongs to a **domain** (status change / quantity adjustment / attribute correction / return) and, where relevant, a **group** — for status changes the group is the **target status**, which keeps the offered reasons logically linked to the chosen status. Recorded on the transaction log.
- **Product** — **client-scoped** (same SKU under two clients = two records). Carries tracking flags, UoM/packaging + barcodes, category/sub-category, base-unit **weight**, and optional **preferred storage**.
- **UoM (Unit of Measure)** — **global**, shared by all clients.
- **Packaging hierarchy** — per product; each level declares a **basis** (base unit, or a lower level) — see *Packaging basis* below.
- **LPN (License Plate / SSCC)** — the handling unit moved through receive → putaway → pick; carries lot/expiry/serial genealogy.
- **ASN** — Advance Shipment Notice; expected inbound. Status `open → partial → closed` is **derived** from per-line received qty.
- **GRN** — Goods Received Note; one per physical receipt.

## Key rules & concepts

- **Tracking flags** — `lot`, `expiry`, `serial`, per product (default: **lot/expiry ON, serial OFF**). **Expiry ⇒ lot** (expiry requires lot; lot may stand alone; serial independent — enable only for serialised goods).
- **FEFO** — First-Expiry-First-Out; the allocation order for outbound, driven by lot expiry.
- **Packaging basis** — a pack level is defined against either the **base unit** (independent/parallel packs, e.g. 6 / 12 / 14, non-nesting) or a **specific lower level** (true nesting, e.g. dozen = 2 six-packs). `factorToBase = basisFactor × qty`.
- **Shared vs client packaging** — UoM global; packaging **templates** can be shared/global; a product's packaging is created by **cloning** a template (so its barcodes stay independent).
- **Capacity** — optional per **bin**: `maxWeightKg`, `maxUnits`, `maxLpns` (pallet/LPN slots). Unset = unlimited. Enforced **at putaway only**. LPN weight = `qty × product.weightKg`.
- **Client–area segregation** — single system setting `clientAreaSegregation`. **OFF (default):** Areas shared, `owningClient` informational. **ON:** a client is offered only its own + unowned Areas; others blocked. (Client→site scoping is always on, independent of this.) **⚠ CONFIRMED REQUIREMENT for this client: it runs ON — different clients' stock must not share a location. The mock seed ships it ON with a dedicated Area per client (Areas D/E/F = Technip/Schlumberger/Yinson, B = Globex; Area A + Soyo Area C left shared). The product/greenfield default remains OFF (opt-in, per-deployment config).**
- **Preferred storage** — optional per product **per site**: `{ site, mode: 'location' | 'area', ref }`.
- **Directed putaway** — *suggested + override.* Rank order: **home → consolidate → category → open**. Recommended is pre-selected; operator may override with any valid location. One LPN → one bin (no splitting in v1).
- **Dual-channel, ERP-complete** — every operational action exists on **both** the PWA scanner and the ERP (manual entry). If scanners are offline, the ERP alone keeps the warehouse operable.
- **Classic vs Express fulfilment** (outbound, **per action**) — every open/back-ordered order can be handled either the **classic** way (separate **Allocate** → **Pick/Dispatch** screens — work-queues for separate teams) or via **Express Fulfil** (one guided pass: allocate→pick→dispatch). The Orders list offers **both**. **[coding phase]** Express Fulfil will be **permission-gated** (separate-team sites won't grant the right, so their staff see only *Allocate*); no role model in the mock yet. Serial-tracked lines and short/blocked stock always pause for review either way.
- **Back-order vs short-close** (outbound remainder policy, **per client** via `Client.allowBackorder`) — when an order can't be fully shipped: **back-order** keeps the unshipped remainder open (order → `partial`; it re-allocates and ships on a later delivery note) ; **short-close** ships what's available and **cancels** the remainder (order → `dispatched`, flagged short-closed).

## Status / lifecycle values (as used in the mock dataset)

- **LPN status:** `to-inspect` → `to-putaway` → `available` → `allocated`* → `dispatched` (also `quarantine` / `hold` for failed inspection). *(allocation is modelled as a reservation on the order; an LPN flips to `dispatched` when its qty is issued.)
- **ASN status (derived):** `open` → `partial` → `closed`.
- **Outbound order status:** `open` → `allocated` → `picking` → `picked` → `dispatched`; **`partial`** = partially shipped with a back-ordered remainder still open.
- **Lot condition at receipt:** `Good` (→ to-putaway) · `Hold for inspection` (→ to-inspect) · `Damaged` (→ quarantine).
- **Location status:** `active` | `inactive`.

## Naming conventions (mockups → carry into code where sensible)
- Files: `erp-<section>-<screen>.html`, `pwa-<section>-<screen>.html`; section codes `md` (master data), `gr` (goods reception), `pa` (putaway), `so` (stock-out), `inv` (inventory), `rpt` (reports).
- Dataset helpers in `data.js`: `siteAreas(siteId)`, `areaInfo(siteId, code)`, `asnStatus()`, `asnTotals()`, `catName()`, `subCatName()`.
