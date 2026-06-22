# Data Model — WMS

> Consolidated domain model, distilled from the mock dataset (`mockups/assets/data.js`) and the section specs.
> This is the **coding bridge**: entities, fields, types, enums, and relationships in one place.
> Terminology follows `GLOSSARY.md` (Zone = addressing level; Area = slotting group). Where the mock
> dataset takes a shortcut for display purposes, it's flagged **[mock]** with the production intent.

## Conventions
- **IDs** are string keys, prefixed by type (`C-`, `S-`, `LOC-`, `P-`, `LPN-`, `ASN-`, `OUT-`, `U-`, `CAT-`, `SUB-`, `PKG-`). Production may use UUIDs/sequences; keep the human prefix for readability.
- **Scoping:** almost everything is scoped by **client** and **site**. A `Product` is *client-scoped* (same SKU under two clients = two records). Stock, LPNs, ASNs, and orders are *site-scoped*.
- **Money/valuation:** none — 3PL holds client-owned stock; the model tracks quantity, location, and genealogy only.

## Entity-relationship overview
```
Client ──< (operating) Site ──< Location ──>1 StorageArea (storage bins only; area scoped to site)
  │                       └──< StorageArea (site.areas[])      StorageArea ──> owningClient? (Client)
  │                                                            StorageArea ──> preferred Category/Sub
  ├──< Product (client-scoped) ──>1 Category ──< SubCategory
  │        ├──>0..1 preferred storage: per Site → Location | Area
  │        └──1 Packaging (cloned from a shared template)  Packaging.levels[] ──> UoM
  ├──< LPN ──>1 Product, ──>1 Site, ──>1 Location (current)   [carries lot/expiry/serials]
  ├──< ASN ──>0..1 Supplier ──< ASN.line ──>1 Product   (status derived: open→partial→closed)
  ├──< Consignee (ship-to, client-scoped)
  └──< Outbound ──>0..1 Consignee (shipTo) ──< Outbound.line ──>1 Product   ──< Shipment ──>0..1 Carrier
User ──> site scope + client scope
UoM (global)   Category/Sub (global)   Packaging templates (global, shared)   Settings (system)
Supplier (global)   Carrier (global)   Attachments (flat, ref-keyed photos)
```

---

## Client
The stock owner (principal). `DB.clients[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `C-…` |
| name | string | ✓ | display name |
| legal | string |  | legal entity name |
| contact / email / phone | string |  | primary contact |
| country | string |  | |
| status | enum | ✓ | `active` \| `inactive` |
| **sites** | string[] | ✓ | operating sites — `→ Site.id`. Scopes the client's products, stock, preferred storage. |
| **allowBackorder** | bool |  | outbound short-shipment policy: `false` (default) = **short-close** (ship available, cancel the rest); `true` = **back-order** (remainder stays open, re-allocates when stock arrives). |

## Supplier
The source of inbound goods. **Global** (shared across clients). `DB.suppliers[]`. Referenced by `ASN.supplier`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `SUP-…` |
| name | string | ✓ | |
| contact / email / phone / country | string |  | primary contact |
| status | enum | ✓ | `active` \| `inactive` |

## Carrier
Who physically moves stock out. **Global.** `DB.carriers[]`. Recorded on a dispatch shipment (`Shipment.carrier`) and printed on the delivery note.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `CAR-…` |
| name | string | ✓ | |
| scac | string |  | carrier code (SCAC) |
| mode | string |  | service / mode (e.g. `Road`, `Road · 2–8 °C`) |
| contact / phone | string |  | |
| status | enum | ✓ | `active` \| `inactive` |

## Consignee (ship-to)
A client's **delivery point** (store / hospital / end customer). **Client-scoped.** `DB.consignees[]`. **Key 3PL distinction:** an outbound order ships to a **consignee** (`Outbound.shipTo`), *not* to the client — the client owns the stock, the consignee is where it is delivered.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `CNE-…` |
| client | string | ✓ | `→ Client.id` (scope) |
| name | string | ✓ | |
| address / city / country | string |  | delivery address |
| contact / phone | string |  | |
| status | enum | ✓ | `active` \| `inactive` |

## Site
A warehouse. Owns its **addressing levels** and its **Storage Areas**. `DB.sites[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `S-…` |
| name / city / country | string | ✓/ / | |
| type | string |  | e.g. "Distribution Centre", "Cross-dock Hub" (free text) |
| status | enum | ✓ | `active` \| `inactive` |
| **levels** | string[] | ✓ | ordered **addressing path** (e.g. `['Floor','Zone','Aisle','Rack','Bin']`). Drives `Location.structured` + `Location.path` keys. *No factors* — addressing only. |
| **areas** | StorageArea[] | ✓ | managed slotting/segregation groups (below) |

`DB.defaultLocationLevels` (`['Zone','Aisle','Rack','Bin']`) seeds a new site's `levels`; editable afterward.

### StorageArea (nested in `Site.areas[]`)
Logical grouping for slotting + segregation, **decoupled from `levels`**.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| code | string | ✓ | unique **within the site** (e.g. `A`, `B`); referenced by `Location.area` |
| name | string | ✓ | e.g. "Area A — Ambient" |
| preferredCategories | string[] |  | `→ Category.id` — slotting affinity |
| preferredSubCategories | string[] |  | `→ SubCategory.id` — finer affinity |
| owningClient | string \| '' |  | `→ Client.id`; '' = unowned/shared. Used only when segregation is ON. |

## Location
A physical spot. `DB.locations[]`. Identity = the permanent, scannable `id`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | **System ID** — `LOC-…`, permanent, scannable, never changes |
| site | string | ✓ | `→ Site.id` |
| type | enum | ✓ | `storage` \| `wait/put` \| `dispatch` \| `quarantine` |
| path | object |  | level→value map keyed by the site's `levels` (e.g. `{Floor:'1',Zone:'A',…}`) |
| structured | string | ✓ | human code derived from `path` (e.g. `1-A-01-R1-B01`); regenerable; may change on restructure |
| userRef | string |  | optional free-text label (e.g. "Cold zone", "Inbound staging") |
| status | enum | ✓ | `active` \| `inactive` |
| **area** | string |  | `→ Site.areas[].code` (storage bins only; independent of `path`) |
| **maxWeightKg** | number |  | capacity — unset = unlimited |
| **maxUnits** | number |  | capacity — unset = unlimited |
| **maxLpns** | number |  | capacity = pallet/LPN slots — unset = unlimited |

Capacity is enforced **at putaway only** (Section 03), never as a master-data block.

## Category / Sub-category
Global, cross-client product taxonomy. `DB.categories[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `CAT-…` |
| name | string | ✓ | |
| subs | SubCategory[] |  | each `{ id:'SUB-…', name }` |

## Product
Client-scoped. `DB.products[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `P-…` |
| client | string | ✓ | `→ Client.id` (scope) |
| sku | string | ✓ | unique **per client** |
| name | string | ✓ | |
| uom | string | ✓ | base unit label (free text; aligns to a `UoM.code`/name) |
| barcode | string |  | base-unit barcode (per-level barcodes live on Packaging) |
| track | object | ✓ | `{ lot:bool, expiry:bool, serial:bool }`. **Rule: expiry ⇒ lot.** Default: lot + expiry ON, **serial OFF** (enable serial only for serialised goods). |
| **category** | string |  | `→ Category.id` |
| **subCategory** | string |  | `→ SubCategory.id` |
| **weightKg** | number |  | **base-unit** weight — feeds putaway capacity math (`LPN weight = qty × weightKg`) |
| **preferred** | PreferredStorage[] |  | optional home per site (below) |

### PreferredStorage (`Product.preferred[]`)
| Field | Type | Req | Notes |
|-------|------|-----|-------|
| site | string | ✓ | `→ Site.id` (must be one of the client's sites) |
| mode | enum | ✓ | `location` (fixed bin) \| `area` (any open bin in an Area) |
| ref | string | ✓ | if `location` → `Location.id`; if `area` → `Site.areas[].code` |

## UoM (Unit of Measure)
Global, shared by all clients. `DB.uoms[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| code | string | ✓ | e.g. `EA`, `KG`, `PAL` |
| name | string | ✓ | |
| cat | enum | ✓ | `Count` \| `Weight` \| `Volume` \| `Length` \| `Packaging` |
| base | bool |  | true = base unit of its measurement category (one per `cat` for Count/Weight/Volume/Length) |
| dec | bool |  | allows decimal quantities |

## Packaging
Two tiers: **shared templates** (no client/product) and **product packaging** (cloned from a template, carrying that product's barcodes). `DB.packagings[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `PKG-…` (templates: `PKG-T-…`) |
| name | string | ✓ | |
| shared | bool |  | true = global template (`client`/`product` = '—') |
| client | string |  | `→ Client.id` (product packaging) |
| product | string |  | `→ Product.id` (product packaging) |
| base | string | ✓ | label of the base level (e.g. "Each", "Vial") |
| levels | PackLevel[] | ✓ | ordered, base first |

### PackLevel (`Packaging.levels[]`)
| Field | Type | Req | Notes |
|-------|------|-----|-------|
| level | string | ✓ | display name (e.g. "Six-pack", "Carton") |
| uom | string | ✓ | `→ UoM.code` |
| basis | string |  | what this level is **defined against**: `'base'` (independent/parallel pack) or a **lower level name** (true nesting). Absent ⇒ defined against the immediately lower level. |
| perParent | number | ✓ | qty in its basis unit |
| factor | number | ✓ | cumulative **factor to base** = basisFactor × perParent (precomputed in mock) |
| barcode | string |  | per-level barcode (product packaging); '—' for templates |
| note | string |  | human note |

> A product can mix **nested chains** and **parallel packs** (e.g. a 6-pack and a 14-pack both off base). Provenance: a product packaging is **cloned** from a template (not referenced), so barcodes stay independent. **[mock]** the clone source isn't recorded; production should keep a `clonedFrom` template id for traceability.

## LPN (License Plate)
The handling unit; the primary stock-bearing record. `DB.lpns[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `LPN-…` (SSCC in production) |
| client | string | ✓ | `→ Client.id` |
| site | string | ✓ | `→ Site.id` |
| product | string | ✓ | `→ Product.id` |
| qty | number | ✓ | **base units** on the plate |
| lot | string |  | present when product tracks lot |
| expiry | date (ISO) |  | present when product tracks expiry; drives **FEFO** |
| serials | string[] |  | present when product tracks serial; unique, count = `qty`. **[mock]** seeded as a display range like `'SN-301…360'`; production = explicit list. |
| status | enum | ✓ | see LPN status below |
| loc | string | ✓ | `→ Location.id` (current location) |

**Stock-on-hand is derived**, not a separate table: SoH = LPNs with `status:'available'` grouped by product/lot/location. **[mock]** keep this in mind when building reports.

## ASN (Advance Shipment Notice) — inbound
`DB.asns[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `ASN-…` |
| client / site | string | ✓ | scope |
| **supplier** | string |  | `→ Supplier.id` — source of the goods |
| lines | ASNLine[] | ✓ | |

**ASNLine:** `{ product → Product.id, qty (expected base), received (base received so far) }`.
**Status is derived** via `asnStatus()`: `open` (received ≤ 0) → `partial` → `closed` (every line received ≥ qty). Never stored.

## Outbound (order) — outbound
`DB.outbound[]`. Extended in **Section 04 (Stock-Out)** to carry allocation + pick detail.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `OUT-…` |
| client / site | string | ✓ | scope |
| ref | string |  | client PO / reference |
| **shipTo** | string |  | `→ Consignee.id` — the **delivery point** (a client consignee), NOT the client itself |
| created | date (ISO) |  | request date |
| status | enum | ✓ | `open` → `allocated` → `picking` → `picked` → `dispatched`; **`partial`** = some shipped, remainder back-ordered (re-enters allocation); **`cancelled`** = order (or its un-shipped remainder) cancelled, reservations freed |
| fullStockOut | bool |  | true = ship **all available** for each line's product/site; line `qty` is ignored |
| shortClosed | bool |  | true once a short shipment cancelled the remainder (client without back-order); order ends `dispatched` |
| dispatched | date (ISO) |  | date of the latest dispatch |
| shipments | Shipment[] |  | immutable history of dispatched batches — **each is one Delivery Note** |
| lines | OutLine[] | ✓ | below |

**OutLine:** `{ product → Product.id, qty (base ordered), shipped (cumulative base issued across all dispatches), alloc: Allocation[] (CURRENT round), cancelled?: bool }`. Remaining-to-fulfil = `qty − shipped`; allocation always works on the remaining qty. A **`cancelled`** line is excluded from `outTotals`/`outboundComplete` and is not offered on Allocation / Pick-Dispatch / Express Fulfil.

**Shipment (`Outbound.shipments[]`):** `{ id (delivery-note ref, e.g. `DN-7005-1`), date, carrier (→ Carrier.id), lines:[{ product, picked (base shipped this delivery), alloc:[{lpn,lot,expiry,from,qty,picked,serials}] }] }`. One order → one shipment when fully shipped; **multiple shipments** when back-ordered (one delivery note each). The delivery note prints the order's **consignee** (`shipTo`) as ship-to, the client as stock owner, and the shipment **carrier**.

**Remainder policy (per `Client.allowBackorder`):** a dispatch shipping less than ordered either **back-orders** the shortfall (order → `partial`, remainder re-allocates) or **short-closes** it (order → `dispatched`, `shortClosed=true`, remainder cancelled). Serial-tracked lines and short/blocked stock always pause for review.

**Two fulfilment paths (per action, not per setting):** an open/back-ordered order can be handled either by the **classic** route (separate Allocate → Pick/Dispatch screens — work-queues for separate teams) **or** by **Express Fulfil** (`erp-so-fulfil.html`, one guided pass). The Orders list offers **both** actions on every open/`partial` order. **[role — coding phase]** Express Fulfil is intended to be **permission-gated** (e.g. an "Express fulfilment" right for all-rounder operators); separate-team sites simply won't grant it, so their staff see only *Allocate*. No role model exists in the mock yet — both are shown to everyone. *(An earlier `Site.fulfilmentMode` / `Outbound.modeOverride` mechanism was removed in favour of this.)*

### Allocation (`OutLine.alloc[]`)
One entry per LPN/lot drawn to fill the line, chosen by **FEFO** (expiry-tracked products) or **FIFO** (non-expiry, oldest plate first). Filled on the Allocation screen.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| lpn | string | ✓ | `→ LPN.id` |
| lot / expiry | string |  | copied from the LPN (blank when untracked) |
| from | string | ✓ | `→ Location.id` (where the LPN sits) |
| qty | number | ✓ | base units **reserved** from this LPN |
| picked | number | ✓ | base units actually picked (captured at Pick/Dispatch; 0 until then) |

**Allocation = reservation on the order line.** The LPN stays `available` with reduced **free** qty (`lpnAvail` = `LPN.qty` − reservations by other live orders) and flips to `dispatched` only when its remaining qty is issued at dispatch. A line whose requested qty exceeds what's allocatable is a **short pick**. **[mock]** partial-LPN reservations are not persisted on the LPN; they live on `alloc[]`. Serials are recorded on issue for serial-tracked products.

## User
`DB.users[]`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `U-…` |
| name / email | string | ✓ | |
| role | enum | ✓ | `Administrator` \| `Supervisor` \| `Operator` |
| sites | scope | ✓ | site scope. **[mock]** display string ("All sites"/"Lyon DC"); production = `Site.id[]` or "all". |
| clients | scope | ✓ | client scope. **[mock]** display string; production = `Client.id[]` or "all". |
| status | enum | ✓ | `active` \| `inactive` |

Role drives the inline-create policy in Receive (privileged roles create products live; others create as pending/unverified).

## Work-item assignment (`assignee`) — cross-cutting
A lightweight "dispatch a request to a person" facet on **work items**. **Not a new entity** — just one optional field reused across collections, plus a "My requests" / "My tasks" filter on every main list (ERP grids + PWA task lists). Added 2026-06-19.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| **assignee** | string |  | `→ User.id`. Absent / `''` = **unassigned**, shown as **"Any"** (the default). Lives on the work-item record. |

**Where it lives:** on the document-backed queues `Outbound` · `ASN` · `Transfer` · `Cycle Count` · `Physical Inventory` · `Return` · `RTV` · `Disposal`; and **on the `LPN` / transient pallet** for the status-derived queues (Putaway `to-putaway`, Inspect `to-inspect`) — those have no document, so the plate carries the field. *(Adjustments & Repack are out of scope — back-office, not dispatched.)*

**Current user:** `DB.currentUserId` (mock; default `U-002`). The **PWA shell repoints it to the floor operator** (`PWA.userId` = `U-003`) on load, so `isMine()` resolves to the right person in each channel. **[mock]** production = the authenticated session user.

**UI:** ERP lists get an **Assignee** filter (`Any · ★ My requests · each user`) + an **Assignee column** + a **dispatch picker** in the create/edit/detail (a supervisor assigns). PWA task lists get a shell-injected **`All / My tasks`** toggle (on `data-pwa-assignable` screens) + a per-task **Claim / Release** self-assign. **[role — coding phase]** PWA self-claim must be **permission-gated** (same posture as Express Fulfil / ad-hoc dispatch); shown to all in the mock.

**Helpers (`data.js`):** `assigneeName(id)` (→ name, or `'Any'`), `isMine(rec)`, `isAssignedTo(rec,userId)`, `assignableUsers(siteId)` (active users for the dropdowns, site-scoped with all-active fallback), `assigneeFilterOptions(siteId,sel)` / `assigneePickerOptions(siteId,sel)` (option-list builders), `assigneeFilterPass(rec,fstate)` (`fstate ∈ 'all'|'mine'|User.id`).

## Reason codes (`DB.reasonDomains[]`) — master data
Configurable reason lists, edited in `erp-md-reasons.html`. Operational screens read them via
`reasonsFor()` instead of hardcoding. Uniform shape so the editor renders every domain generically.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | domain key: `status` \| `adjust` \| `correct` \| `return` |
| label | string | ✓ | display name |
| groupedBy | string |  | label of the grouping dimension (`'Target status'`, `'Direction'`); `''` = single shared list |
| groups | Group[] | ✓ | `{ key, label, reasons:string[] }` |

**Group key semantics:** for `status` the key **is the target LPN status** (`available`/`quarantine`/`hold`/`damaged`/`expired`) — this is what links a reason to a status so no illogical pairing is offered. For `adjust` the key is `increase`/`decrease`. For `correct`/`return` there is one group (`all`).

**Seed:** `status` (4 groups by target status), `adjust` (increase/decrease), `correct` (single list incl. wrong lot/expiry/serial/product/owning client), `return` (single list). **[mock]** reasons are display strings; production would key them by a stable code.

## Physical Inventory (`DB.physicals[]`) — Section 05
A freeze→count→reconcile→unfreeze event over a whole **site** or a single **Area**.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `PHY-…` |
| site | string | ✓ | `→ Site.id` |
| scope | enum | ✓ | `site` \| `area` |
| area | string |  | `→ Site.areas[].code` when `scope:'area'` |
| status | enum | ✓ | `open` → `frozen` → `closed` |
| frozen | bool | ✓ | while true the scope blocks putaway / moves / allocation |
| created / by / closed | | | lifecycle |
| locations | PhysLoc[] | ✓ | `{ loc, status:'pending'\|'counted', lines:[{ lpn, product, systemQty, countedQty }] }` |

**Freeze** flips `frozen` + status. **Post** (only when every location `counted`) sets each LPN `qty=countedQty` (+ `count` txn), then `frozen=false`, status `closed`. **Abandon** unfreezes with no corrections. **Freeze is ENFORCED cross-screen** (was advisory): Putaway, Move, Transfer-ship and Allocation call `isLocFrozen`/`frozenTakeFor` and **refuse** any location inside an active `frozen` take. Seed takes start `open` (not `frozen`) so the shared demo stock stays movable until a tester freezes one live. A location may carry a **found** line (`lpn:''`, no system plate) — posting mints a new `available` plate; a counted-0 line is **missing** and zeroes the plate.

## Repack / Split / Merge / Re-kit (`DB.repacks[]`) — Section 05
A conversion job: source plate(s) **consumed**, output plate(s) **created**, carrying lot/expiry/serial genealogy.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `RPK-…` |
| kind | enum | ✓ | `split` (1→N) \| `merge` (N→1, same product+lot+expiry) \| `repack` (1→1, new packaging) \| `rekit` (assemble/disassemble) |
| site / status / created / by | | ✓ | `status:'confirmed'` (jobs post immediately in the mock) |
| sources | `{lpn, product, qty}[]` | ✓ | consumed plates |
| outputs | `{lpn, product, qty, lot, expiry, loc, note}[]` | ✓ | created plates (`lpn` minted via `nextLpnId()`) |

**Posting:** outputs are pushed to `DB.lpns` as `available`; sources set `status:'consumed'` (split reduces the source by the output total, consuming it only if it hits 0) + a `repack` txn. **[mock]** serials carry wholesale on repack/merge; split/re-kit serial reassignment is not modelled per-child.

## Cycle Count (`DB.counts[]`) — Section 05
One count **sheet** spans **one or many locations** (count many bins in a single entry — no freeze; the frozen
full stock-take is Physical Inventory). `variance = countedQty − systemQty` per line; approval corrects stock
across every location on the sheet. One sheet = one approval decision.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `CNT-…` |
| site | string | ✓ | `→ Site.id` |
| status | enum | ✓ | `counted` → `pending-approval` → `approved` \| `rejected` |
| created / countedBy / countedDate / approved | | | lifecycle |
| locations | CountLoc[] | ✓ | `{ loc(→Location.id), lines:CountLine[] }` — one group per counted location |
| › lines | CountLine[] | ✓ | `{ lpn, product, lot, systemQty, countedQty, found? }` |

**Approve:** for every line across all `locations[]`, sets each LPN `qty = countedQty` (+ `count` txn per corrected plate). A **found** line (`lpn:''`, `found:true`, `systemQty:0`) **mints a new `available` plate** at the bin via `nextLpnId()`; a **missing** line (counted 0 on a system plate) zeroes it. **Reject:** no change; recount. **[mock]** serial-level counts for serial-tracked products remain a production gap. *(Model changed 2026-06-17: one `location`→`locations[]` so a sheet covers many bins; found/missing lines added in the pre-PWA pass.)*

## Return / Put-back (`DB.returns[]`) — Section 05
Stock re-entering inventory. Processing creates a plate per line and logs a `return` txn.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `RET-…` |
| kind | enum | ✓ | `putback` (over-pick / unused) \| `customer` (post-dispatch return) |
| client / site | string | ✓ | scope |
| ref | string |  | `→ Outbound.id` (source order) |
| status | enum | ✓ | `open` → `closed` |
| created / closed / by | | | lifecycle |
| lines | ReturnLine[] | ✓ | `{ product, qty, lot, expiry, serials[], reason, disposition, toLoc, lpn }` |

**Disposition per line** (`reasonsFor('return')` drives the reason): `restock` → bin **(direct)** = new LPN `available` at the chosen bin (passes the shared capacity + segregation checks); `restock` → **via Putaway** = new `to-putaway` LPN at inbound staging that enters the directed-Putaway queue (slotting applied there); `quarantine`/`damaged` → new **blocked** LPN routed to the site's quarantine location (excluded from allocation). Genealogy carried. **[mock]** RMA credit/billing is out of scope — only the physical stock re-entry is modelled.

## Stock Move (`DB.moves[]`) — Section 05
Intra-site relocation, location → location within one site. Immediate (no approval); posting sets `LPN.loc` and logs a `move` txn.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `MOV-…` |
| site / lpn / product | string | ✓ | scope + plate |
| qty | number | ✓ | whole-plate qty (display) |
| from / to | string | ✓ | `→ Location.id` (same site) |
| status | enum | ✓ | `done` (moves are immediate) |
| date / by / note | | | audit |

## Transfer Order (`DB.transfers[]`) — Section 05
Inter-site, Site A → Site B, with an in-transit state. A line transfers a **whole plate** (partial-plate splits go through Repack first).

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `TRF-…` |
| client | string |  | `→ Client.id` |
| fromSite / toSite | string | ✓ | `→ Site.id` (must differ) |
| status | enum | ✓ | `draft` → `in-transit` → `received` \| `cancelled` |
| created / shipped / received / by | | | lifecycle dates + actor |
| lines | TransferLine[] | ✓ | `{ lpn, product, qty, lot, expiry, serials[], recvLoc }` |

**Lifecycle effects:** *Ship* (draft→in-transit) sets each line's LPN `status:'in-transit'` (+ `transfer-ship` txn). *Receive* (in-transit→received) sets the LPN `site=toSite`, `loc=recvLoc` (chosen per line at receipt), `status:'available'` (+ `transfer-receive` txn). Lot/expiry/serial carry across unchanged.

## Adjustment / Correction (`DB.adjustments[]`) — Section 05
Two kinds on one collection; both approval-gated (`pending → posted | rejected`). Reasons from `DB.reasonDomains`.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `ADJ-…` |
| kind | enum | ✓ | `qty` (quantity delta) \| `correct` (attribute correction) |
| client / site / lpn / product | string | ✓ | scope + target plate |
| status | enum | ✓ | `pending` \| `posted` \| `rejected` |
| created / by | string | ✓ | raised date + raiser |
| posted | date |  | set when approved |
| reason | string | ✓ | from `reasonsFor('adjust',dir)` (qty) or `reasonsFor('correct')` |
| note | string |  | free text |
| **qty kind:** dir | enum | ✓ | `increase` \| `decrease` |
| beforeQty / delta / afterQty | number | ✓ | posting sets `LPN.qty = afterQty` |
| **correct kind:** changes | Change[] | ✓ | `{ field, from, to }`; `field` ∈ `lot`/`expiry`/`serial`/`product`/`client`. Posting writes each to the LPN. |

Posting also appends a `txn` (`type:'adjust'` or `'correct'`). **[mock]** before-values snapshot at raise time; production should re-validate against live qty at approval (concurrent adjustments).

## Transaction history / audit (`DB.txns[]`)
Append-only event log. Seeded minimally in the mock (a receive, a putaway, a dispatch); every
**Section 05 (Inventory Operations)** action appends a row via `logTxn()`. **Section 06** Transaction
History reads it. *(Previously a flagged production gap — now materialised as a thin table.)*

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `TXN-…` (auto via `logTxn`) |
| ts | string | ✓ | timestamp `YYYY-MM-DD HH:mm` |
| type | enum | ✓ | `receive` \| `putaway` \| `move` \| `transfer-ship` \| `transfer-receive` \| `adjust` \| `correct` \| `count` \| `status` \| `repack` \| `return` \| `dispatch` \| `attach` \| `attach-remove` |
| lpn / product | string |  | `→ LPN.id` / `→ Product.id` |
| qty | number |  | base units affected (signed for adjustments) |
| from / to | string |  | `→ Location.id` (move/putaway) or site (transfer) |
| site | string |  | `→ Site.id` |
| user | string |  | actor (display name in mock) |
| ref | string |  | linked document (GRN / order / transfer / etc.) |
| note | string |  | human description (e.g. `available → quarantine · Damage found`) |

## Attachments / photo justification (`DB.attachments[]`)
Optional photo evidence attached to a document (header) or a line. One flat collection, rendered/edited by the shared `assets/photos.js` widget across Goods Reception, Stock-Out and Inventory-Ops. Never mandatory.

| Field | Type | Req | Notes |
|-------|------|-----|-------|
| id | string | ✓ | `ATT-…` |
| kind | string | ✓ | `photo` |
| ref | string | ✓ | owning id — a document id (header) or a line ref (`${docId}:L${idx}` / an LPN id) |
| level | enum | ✓ | `header` \| `line` |
| name / dataUrl / caption / by / at | | | filename, image data, caption, actor, timestamp |

Every add/remove also writes a `logTxn()` row (`attach` / `attach-remove`). **[mock]** data-URL placeholders; production stores real uploads.

## Settings (system)
`DB.settings` — `{ clientAreaSegregation: bool }` (greenfield default **false**). ON = a client is offered only its own + unowned Areas at putaway; OFF = Areas shared, `owningClient` informational. Client→site scoping is always on regardless. **⚠ This client REQUIRES segregation → the seed ships it `true`, with a dedicated Area per client (Areas D/E/F = Technip/SLB/Yinson, B = Globex; Area A + Soyo Area C shared). The build MUST deliver the toggle + per-area `owningClient` config and server-side enforcement (CC-02).**

---

## Enumerations (collected)
- **LPN.status:** `to-inspect`, `to-putaway`, `available`, `allocated`, `picked`, `dispatched`, `in-transit`, `consumed` (source of a repack/split/merge), `hold`, `quarantine`, `damaged`, `expired` *(typical lifecycle: to-inspect → to-putaway → available → allocated → picked → dispatched; inspection failure → quarantine/hold)*. **Blocked statuses** (excluded from allocation): `quarantine`, `hold`, `damaged`, `expired`. `expired` = intact stock past shelf-life (distinct from physically `damaged`).
- **ASN.status (derived):** `open`, `partial`, `closed`.
- **Outbound.status:** `open`, `allocated`, `picking`, `picked`, `partial` (back-order), `dispatched`, `cancelled`.
- **Location.type:** `storage`, `wait/put`, `dispatch`, `quarantine`.
- **Location.status / Client.status / Site.status / User.status:** `active`, `inactive`.
- **Product.preferred.mode:** `location`, `area`.
- **UoM.cat:** `Count`, `Weight`, `Volume`, `Length`, `Packaging`.
- **User.role:** `Administrator`, `Supervisor`, `Operator`.
- **Lot condition at receipt** (drives routing, Section 02): `Good` → to-putaway · `Hold for inspection` → to-inspect · `Damaged` → quarantine.

## Derived values & helpers (in `data.js`)
- `asnTotals(a)` → `{ exp, rec, linesComplete, lines }`; `asnStatus(a)` → open/partial/closed.
- `siteAreas(siteId)`, `areaInfo(siteId, code)` — Area lookup.
- `catName(id)`, `subCatName(id)`, `prodName(id)`, `dbName(coll,id)`, `unitWeight(productId)`.
- `statusBadge(status)` — maps status → CSS badge class (presentation only).
- **Putaway capacity:** `binWeight = Σ(lpn.qty × product.weightKg)`, `binUnits = Σ lpn.qty`, `binLpns = count(lpns at bin)`; a candidate passes if each is ≤ the bin's max (unset = ∞).
- **Putaway ranking:** home → consolidate → category(Area affinity) → open; recommended pre-selected; operator override always allowed. One LPN → one bin (no splitting in v1).
- **Outbound (Section 04):** `outReserved(lpnId, exceptOrderId)`, `lpnAvail(lpnId, exceptOrderId)` (free qty after other orders' reservations); `outboundCandidates(product, client, site, exceptOrderId)` → `{usesExpiry, list}` (FEFO or FIFO-ordered available LPNs); `fefoAllocate(line, order)` → `{alloc, allocated, requested, short, usesExpiry}` (greedy fill, honours `fullStockOut`); `outTotals(o)` → `{lines, req, allc, pick, ship, remaining, short}`; `lineShipped(line)`, `lineRemaining(line)` (ordered − shipped), `outboundComplete(o)` (every line fully shipped), `clientAllowsBackorder(clientId)`.
- **Inventory Ops (Section 05):** `BLOCKED_STATUSES` (`['quarantine','hold','damaged','expired']`), `isBlocked(status)`, `isExpired(lpn)` (expiry < `WMS_TODAY`), `isAllocatable(lpn)` (available + not past-expiry + free qty > 0); `lpnById(id)`, `locName(id)` (structured code); `onHandLpns(site)` (qty>0 plates, any status — stock-on-hand is the `available` subset); `logTxn(t)` / `nowStamp()` (append an audit row to `DB.txns[]`); `nextLpnId()` (mint the next `LPN-…` id for repack/split/found-stock outputs).
- **Capacity + segregation (shared, single source of truth):** `binLoad(binId)`, `binCapacityForAdd(binId, qty, product)` → `{ok, fails[], after}`, `binSegregationOk(binId, client)`. Used by Putaway directed-slotting, Returns direct-restock, **and** the intra-site Move + inter-site Transfer-receive destinations (every path that places a plate into a bin runs the same checks).
- **Physical-inventory freeze (shared):** `frozenTakeFor(locId)` → the locking `PHY-…` take or null; `isLocFrozen(locId)`. Putaway, Move, Transfer-ship and Allocation refuse a location inside an active `frozen` take.
- **Consignees / partners:** `consigneesFor(clientId)` (a client's active ship-to points), `consigneeName(id)`; suppliers/carriers resolve via the generic `dbName('suppliers'|'carriers', id)`.
- **Reason codes (master data):** `reasonsFor(domainId, groupKey)` (configured list for a domain + group — single-group domains ignore the key); `addReason(domainId, groupKey, text)` / `removeReason(domainId, groupKey, text)` (mutate the master, used by `erp-md-reasons.html`); `reasonDomain(id)`, `reasonGroup(domainId, groupKey)`.

## Production gaps to design later (flagged above)
1. **Stock-on-hand / balances** — currently derived from LPNs; decide whether to materialise.
2. **Serials** — store explicit unique lists, not display ranges.
3. **User scope** — model site/client scope as id lists, not display strings.
4. **Outbound allocation** — *modelled in the mock* (FEFO/FIFO allocation, reservation-aware availability, short-picks, dispatch, back-order vs short-close, multi-shipment delivery notes). Production decisions remaining: persist partial-LPN reservations on the LPN (mock keeps them only on `alloc[]`), and snapshot delivery notes immutably rather than re-deriving from order state.
5. **Packaging provenance** — record the template a product packaging was cloned from.
6. **Transaction history / audit** — now a thin `DB.txns[]` table (seeded + appended via `logTxn()`); production should make it strictly immutable/append-only with full actor + before/after snapshots.
