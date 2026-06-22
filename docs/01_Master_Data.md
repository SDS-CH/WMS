# Section 01 — Master Data

> Foundation reference data every other section depends on. **Channel:** ERP (PWA = lookup/scan only). See `00_Project_Overview.md`.

## Purpose
Define and maintain the core reference data: the clients whose stock is held, the physical warehouse network, the products (per client), how they're measured and barcoded, and who can use the system. Nothing can be received, stored, or shipped before this data exists.

## In Scope (v1)
- **Clients / Owners (principals)** — the entities whose stock is managed. (Normally synced from the ERP; kept as a standalone module in case it's needed independently.) Each client is attached to one or more **operating sites** (multi-select), which scopes its products, stock, and preferred storage.
- **Suppliers** (global) — the source of inbound goods; referenced on an ASN header. **Carriers** (global) — who physically moves stock out; recorded on dispatch and printed on the delivery note. (One screen, two tabs: `erp-md-partners.html`.)
- **Consignees / ship-to** (per client) — a client's **delivery points** (its stores, hospitals, end customers). **Key 3PL distinction:** an outbound order ships to a **consignee**, *not* to the client — the client owns the stock; the consignee is where it is delivered. (`erp-md-consignees.html`.)
- **Sites / Warehouses** (multi-site), each with a **configurable location structure** (see below) and storage/dispatch/staging areas beneath it.
- **Configurable location hierarchy (per site):** each site defines its own ordered list of addressing **levels** — e.g. `Floor → Zone → Aisle → Rack → Bin`, or just `Zone → Aisle`, or a single `Rack`. A new site starts from a **default** structure (`Zone → Aisle → Rack → Bin`) which the user can edit on the Site screen. Depth and level names are not fixed.
- **Location identity (three layers):**
  - **System ID** — auto-generated, unique per site, **permanent**; the scannable identity. Never changes on relabel/restructure; all stock & audit history reference it.
  - **Structured code** — human-readable code derived from the site's level path (e.g. `1-A-01-R1-B01`); helps an operator place themselves. Regenerates if structure changes.
  - **User reference** — optional free-text label the user can set (legacy code, "Cold room 2", a client's own label).
  - The printed barcode label carries the **System ID** (scannable) plus the **structured code** (and user reference where space allows).
- **Location functional types** — storage, plus a configurable **wait/put (staging)** location per site holding LPNs awaiting putaway, dispatch, and quarantine.
- **Location capacity (storage bins, optional)** — per-bin limits: **max weight (kg)**, **max units**, **max pallets / LPN slots**. Enforced at putaway (Section 03), never as a master-data-time block. Any unset limit = unlimited.
- **Storage Areas (slotting & segregation)** — a managed, per-site list of logical **Areas**, **decoupled from the addressing path** (renaming/restructuring `Zone…Bin` never affects them). Each storage location is **assigned to one Area** (individually or by **bulk assignment**). An Area carries its own **preferred categories / sub-categories** (slotting affinity) and an optional **owning client** (segregation). ⚠ Vocabulary: **"Zone" is reserved for an addressing-path level**; the logical slotting grouping is an **Area**.
- **Client–area segregation (system setting)** — when ON, a client is offered only its own Areas plus unowned (shared) Areas at putaway; other Areas are blocked. When OFF (greenfield default), Area ownership is informational and clients share Areas. Lets the operator run shared now and dedicate Areas later with no data migration. **⚠ CONFIRMED for THIS client: segregation runs ON — different clients' stock must not share a location. Each client is given a dedicated Storage Area. The build must deliver the system toggle + the per-area owning-client editor (Sites screen) and enforce it server-side on every bin-write.**
- **Product categorisation** — a global, **cross-client Category → Sub-category** taxonomy (same posture as UoM; belongs to no client). Each product picks a category and an optional sub-category; drives Area affinity for directed putaway and reporting.
- **Reason codes (configurable)** — the master list of reasons operators must pick on operational actions, grouped by **domain**: **stock status change** (keyed by the *target status*, so reasons are logically linked — e.g. "Failed inspection" only when sending to Quarantine), **quantity adjustment** (by direction ±), **attribute correction** (wrong lot / expiry / serial / product / owning client), and **returns / put-back disposition**. Add or remove reasons per group; the operational screens (Section 05) read this list rather than hardcoding it.
- **Products**, scoped **per client** (the same physical SKU under two clients = two distinct product records).
- **Tracking attributes** per product: lot/batch, expiry, serial — **lot/batch and expiry enabled by default; serial OFF by default** (enable only for serialised goods — serials are scanned off the physical unit, not minted). **Expiry implies lot:** a product tracking expiry must also track lot (units in a batch share one expiry), so enabling expiry enables lot.
- **Product categorisation fields:** each product carries a **category** + optional **sub-category** (from the global taxonomy above).
- **Product physical attributes:** dimensions, **weight** (the base-unit weight feeds putaway capacity math), hazmat class, temperature/storage conditions.
- **Preferred storage (optional, per product per operating site)** — a home location, pre-filtered to the client's sites: either a **specific location** (fixed-location bin) or a **preferred Area** (any open bin in it). Putaway offers it first; it is never required.
- **Units of measure & packaging hierarchy** (each → inner → carton → pallet) with conversion factors. Each pack level declares what it is **defined against** — either the **base unit** (independent/parallel pack sizes, e.g. pack of 6 / 12 / 14, which don't nest) or a **specific lower level** (true nesting, e.g. "dozen = 2 six-packs"). The factor to the base unit is auto-computed (basis factor × qty). A single product can carry both nested chains and parallel pack sizes.
- **Shared vs client packaging:** units of measure are **global** (shared by all clients). Packaging hierarchies come in two tiers — **shared/global templates** (e.g. "Dozen = 12 each", a standard Each→Six-pack→Dozen→Carton→Pallet shape) that belong to no client, and **client/product packaging** created by **cloning a template onto a product**, then adding that product's own per-level barcodes. Cloning keeps each product's barcodes independent while reusing the common shape.
- **Barcodes** per item and per packaging level (EAN/UPC/GS1).
- **License Plate / SSCC configuration** (numbering scheme & label format) — the handling unit used through receive → putaway → pick.
- **Users, roles & permissions** (operator, supervisor, admin); access scoped by site and/or client.
- **Bulk import (CSV)** for products and locations (practical necessity for onboarding a client).

## Out of Scope (v2 backlog)
*(Suppliers, carriers, and consignees were pulled into v1 — see In Scope below. No master data remains deferred.)*

## Key Concepts / Entities
- **Client** — owner of stock; attached to one or more **operating sites**. Also carries an **outbound short-shipment policy** (`allowBackorder` — short-close vs back-order; see Section 04), editable on the Clients screen.
- **Supplier / Carrier** — global trading-partner masters: the inbound source (on an ASN) and the outbound mover (on a delivery note).
- **Consignee (ship-to)** — a client-scoped delivery point; an outbound order's `shipTo` target (distinct from the owning client).
- **Site** — a warehouse; **owns its own location-level structure** (ordered addressing levels) **and** its list of **Storage Areas**.
- **Location** — a bin/area belonging to one site; permanent **system ID** (scannable) + derived **structured code** + optional **user reference**; a functional type (storage, wait/put staging, dispatch, quarantine); a path of level values; storage bins also carry an assigned **Area** and optional **capacity** limits.
- **Storage Area** — a managed per-site logical grouping for slotting/segregation, **decoupled from the addressing path**; carries preferred categories/sub-categories and an optional owning client.
- **Category / Sub-category** — a **global, cross-client** product taxonomy.
- **Reason code** — a configurable, system-wide reason string belonging to a **domain** (status change / adjustment / correction / return) and, where relevant, a **group** (the target status, or adjustment direction). Operational actions reference one when posting; it is recorded on the transaction log.
- **Product** — client-scoped; carries tracking flags + UoM/packaging + barcodes, **plus category/sub-category, base-unit weight, and optional per-site preferred storage**.
- **LPN config** — rules for generating license-plate IDs.
- **User / Role** — with site/client scope.

## Business Rules
- Product code is unique **per client**.
- A site defines its **own** ordered location levels; locations at that site expose exactly those levels (no fixed depth, no empty "unused" levels).
- Location **system ID** is unique per site and **permanent** — it is the scannable key and never changes on relabel or restructure.
- The **structured code** is derived from the level path and is for human reading; it may change if the structure changes. The **user reference** is optional.
- Client + site scoping is applied to every downstream record.
- Tracking flags: **lot + expiry default ON, serial defaults OFF** (enable serial only for serialised goods). **Expiry ⇒ lot:** enabling expiry forces lot on (lot may be on without expiry; expiry without lot is not allowed). Serial is independent.
- Packaging levels each declare a **basis** — the **base unit** (independent/parallel packs) or a **lower level** (nesting); factor-to-base = basis factor × qty, computed automatically. This supports both nested chains and parallel pack sizes (e.g. a 6-pack and a 14-pack off the same base).
- Units of measure are **global**. Packaging templates may be **shared (global)**; a product's packaging is **client-scoped** (it carries that product's barcodes) and is normally created by **cloning a shared template**.
- **Categories are global** (cross-client); a product references one category + optional sub-category.
- A **Storage Area** belongs to one site and is **decoupled from the addressing path** — editing the `Zone…Bin` structure never changes Area membership. Each storage location belongs to **at most one Area**; non-storage locations need none.
- **Capacity** limits live on the **bin** (physical); **category affinity** lives on the **Area** (logical). Capacity is checked at **putaway**, not at master-data entry; unset = unlimited.
- **Client–area segregation** is a single system setting; OFF by greenfield default (Areas shared, ownership informational). It can be turned ON later with no migration. **For this client it is ON from go-live (confirmed requirement) — see the demo seed: Areas D/E/F are dedicated to Technip/Schlumberger/Yinson, B to Globex.**

## Screens (for mockup phase)
- **ERP:** list + create/edit for Clients (incl. **operating-sites** multi-select), Sites (incl. **location-structure editor** + **Storage Area management**), Locations (fields rendered **dynamically** from the site's levels; system ID + structured code + user reference + label preview; **Area assignment** incl. **bulk assign**, and optional **capacity** limits), **Categories** (global Category → Sub-category taxonomy), **Reason Codes** (`erp-md-reasons.html` — configurable reason lists by domain/group; feeds the Section-05 operational screens), Products (incl. category/sub-category, weight, and **preferred storage** — location or area), UoM/packaging, Barcodes, Users/Roles, **Suppliers & Carriers** (`erp-md-partners.html`), **Consignees / ship-to** (`erp-md-consignees.html`); CSV import for products & locations. **Client–area segregation** toggle (system setting).
- **PWA:** location lookup and product lookup by scan (read-only).

## Dependencies
Consumed by every other section. No upstream dependency.
