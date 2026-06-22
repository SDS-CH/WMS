# WMS Mockups — Build Log (history & feedback resolutions)

> Chronological record of **what was built and what feedback was resolved**, condensed. This is history — read it
> for the "why" behind a decision. Live status + roadmap: `mockups/MOCKUP_STATUS.md`. Domain rules: `docs/`.
> Locked mutation invariant: `docs/BLOCKING_RULES.md`.
>
> *(Note: every build pass also touched shared anchors — `data.js`, `erp-shell.js`, `wireframe.css`, etc. The repo
> is the source of truth, so the old per-pass "⚠ re-upload" reminders are dropped here. All inventory mutations in
> the mocks are session-only and reset on reload — except PWA flows, which persist to `sessionStorage` within a tab.)*

## 2026-06-22 — Oil & gas clients + client–area segregation turned ON (data.js)

- **3 oil & gas clients** added on the Luanda site — **Technip Energies** (`C-TCHP`), **Schlumberger** (`C-SLB`),
  **Yinson** (`C-YIN`) — with a global `CAT-OG` category, 12 products spanning the tracking profiles (fasteners = none,
  flange = lot/heat-number, equipment = serial, chemicals = lot+expiry), suppliers/carrier/consignees, and full
  receive → putaway → stock-out chains (ASNs incl. a partial; available + to-putaway LPNs incl. expired/to-inspect/
  damaged; outbound incl. a short-close + a back-order). Sites **Lyon DC / Paris Hub renamed → Luanda / Soyo (Angola)**.
- **Client–area segregation turned ON** (`settings.clientAreaSegregation:true`) — **confirmed client requirement**
  (different clients' stock must not share a location). Each O&G client given a **dedicated Storage Area** (D=Technip,
  E=Schlumberger, F=Yinson) with its own heavy bins; existing Areas B=Globex, A + Soyo-C left shared. All available
  O&G stock homed into its owner's Area; `binSegregationOk` now blocks cross-client putaway / move / transfer-receive /
  returns-restock. Decision recorded forward across `docs/` + `delivery/` + `CLAUDE.md` (see `delivery/DELIVERY_STATUS.md`
  → "Confirmed client requirements").
- **Verified:** node data-layer suite — **167 assertions, 0 fail** (segregation ownership · no plate stranded under
  segregation · re-home integrity · capacity within Area-D/E/F caps · FEFO short-close/back-order · serial counts ·
  referential integrity · no duplicate ids). The clients + site-rename were committed (`36d6719`); the segregation pass follows.

## ERP build — all 6 sections COMPLETE

- **Phase 0 — Foundation:** `index.html` (sitemap), `erp-dashboard.html`, the shells, the shared `data.js` dataset.
- **Phase 1 — Master Data:** clients, sites, locations, products (Details/Tracking/Packaging/Barcodes tabs),
  uom (31-unit library + packaging templates), users, import, categories, partners (suppliers/carriers),
  consignees, reasons (Reason Codes master, `reasonsFor()`), clientmap (client–user scoping). Edit layer added the
  slotting fields (client operating-sites; product category/weight/preferred-storage; bin capacity + Area; site
  Storage-Area management).
- **Phase 2 — Goods Reception:** `erp-gr-asn` (ASN list + create/edit; hands off to Receive via `?asn=`),
  `erp-gr-receipt` (Receive: over/short, adaptive qty, mixed lots, flag-driven lot/expiry/serial, serial-capture,
  LPN split, inline product-create, per-lot condition→disposition, expiry warnings, projected ASN status),
  `erp-gr-inspect` (QC worklist: pass/fail + disposition + reason + photo), `erp-gr-grn` (GRN document/print).
- **Phase 3 — Putaway:** `erp-pa-tasks` (directed-putaway list↔detail; tiered slotting home→consolidate→category,
  hard filters site/active/capacity/segregation, ranked suggestions + headroom + excluded-with-reason, tap-to-select
  cards, "assign manually" toggle, single Confirm). Spec: `docs/03_Putaway.md`.
- **Phase 4 — Stock-Out:** `erp-so-orders` (Outbound Orders doc-list + create/edit; full-stock-out toggle; ship-to
  consignee; Allocate › / Express fulfil › per order; Release/Cancel), `erp-so-alloc` (FEFO/FIFO allocation,
  reservation-aware, short-pick), `erp-so-dispatch` (Pick/Dispatch; serials; short-pick; issues stock),
  `erp-so-note` (Delivery Note document/print + serial appendix), `erp-so-fulfil` (Express one-pass). Back-order vs
  short-close per `client.allowBackorder`; `order.shipments[]` (one Delivery Note each). Spec: `docs/04_Stock_Out.md`.
- **Phase 5 — Inventory Operations (7 screens + Reason Codes master):** `erp-inv-status` (derived on-hand grid;
  reason-gated bulk status change; blocked = excluded from allocation; expiry warnings; ⋮ deep-link hub),
  `erp-inv-adjust` (qty adjustment + attribute correction, approval-gated), `erp-inv-transfer` (intra-site Move +
  inter-site Transfer order with in-transit lifecycle; partial auto-split), `erp-inv-count` (multi-location count
  *sheets*; bulk-approve with variance-tolerance gate; Gross |Δ|), `erp-inv-physical` (site/Area stock-take:
  freeze→count→post&unfreeze; overlap guard), `erp-inv-repack` (Split/Merge/Repack/Re-kit), `erp-inv-returns`
  (put-back + customer return → disposition → restock-direct/via-Putaway/quarantine). Seeded `DB.txns[]` audit log;
  every mutation appends via `logTxn()`. Spec: `docs/05_Inventory_Operations.md`. Invariant: `docs/BLOCKING_RULES.md`.
- **Phase 6 — Reports (10) + barcode/label engine:** `erp-rpt-soh/txns/expiry/inbound/outbound/variance/
  utilization/trace/statement/stockcard`. Shared report pattern (KPI tiles → filter grid → funnel table → Excel/Print
  toolbar + global `@media print`). All read existing `data.js` entities (no data-model change). NEW `assets/barcode.js`
  (Code 128 SVG + label/print) wired into Locations, Products, LPN labels, ASN, Putaway, Outbound, GRN, Delivery Note.
  Product UoM & Packaging tab rebuilt into a live per-product generator (+ internal EAN-13 generator). Spec: `docs/06_Reports.md`.

## Pre-PWA global review & hardening (2026-06-17)

Full audit of all 42 screens vs specs. Confirmed the end-to-end loop covers ~90% of common 3PL actions; the user
chose to act on every gap so the PWA inherits correct behaviour:
- **Invariant fixes enforced in the mocks** (see `docs/BLOCKING_RULES.md`): frozen-scope refusal cross-screen
  (`isLocFrozen`/`frozenTakeFor` — Putaway/Move/Transfer-ship/Allocation); capacity + client–area segregation on
  **every** bin-write (`binCapacityForAdd`/`binSegregationOk` — added to Move + Transfer-receive); serial-capture on
  classic Pick/Dispatch (was Express-only). Seed takes PHY-7001/7002 set to `open` so demo stock stays movable.
- **4 domain features added to v1:** Suppliers & Carriers master (`erp-md-partners`) + Consignees/ship-to master
  (`erp-md-consignees`) — an outbound order ships to a **consignee**, not the client (`order.shipTo`; Delivery Note
  prints ship-to / stock-owner / carrier); de-allocation + order/line cancellation (`cancelled`); found/missing count
  lines. Docs reconciled: `06`, `DATA_MODEL`, `01–05`, `GLOSSARY`, `CLAUDE.md`.

## Cross-cutting features added late

- **Photo justification (2026-06-17):** optional photo upload at **header + line** level across 17 GR/Stock-Out/
  Inventory-Ops/Putaway screens. NEW `assets/photos.js` (`window.photoField({ref, level, …})`, document-level
  delegation, FileReader thumbnails, lightbox, readonly mode) + flat `DB.attachments[]` (`{id, kind:'photo', ref,
  level, name, dataUrl, caption, by, at}`); helpers `attachmentsFor`/`attachmentCount`/`addAttachment`/`removeAttachment`.
  Every add/remove writes a `logTxn` row. Not mandatory — placeholders kept for the user to hide later. `ref`: header =
  document id; line = `` `${docId}:L${idx}` `` (or the LPN id).
- **Notes / remarks (2026-06-18):** free-text remark at **header + line** level across all ERP pages, all 10 reports
  (read-only Notes column), and the PWA receipt-stage screens. Textual sibling of photos (same `ref`). NEW
  `assets/notes.js` (`window.noteField({ref, level, …})`) + flat `DB.notes[]` (`{id, ref, level, text, by, at}`);
  helpers `noteFor`/`setNote`/`hasNote`/`noteRecFor`. Lightweight (no per-keystroke `logTxn`). `.erp-main` widened to
  100%. 40 screens wired; `'notes'` added to `PWA_DB_COLLECTIONS`.
- **Client–User mapping (2026-06-18):** NEW `erp-md-clientmap.html` — scope an ERP user to a client list (Add-User
  modal: searchable user select + All-Clients checkbox that hides the client picker + chip-list picker). `DB.users`
  enriched with `firstName`/`lastName`/`username`/`allClients`/`clientIds`; helpers `userClientNames`/`userClientsLabel`.
  Nav child `md-clientmap`. *(Coding phase: enforce this client scope server-side — reports/lists default to all-clients
  in the mock.)*
- **Tracking-flag test data (2026-06-18):** 4 dedicated products tagged `product.testCase` exercising the flag
  combinations — `P-TCA` (none, the ~90% case) · `P-TCB` (lot) · `P-TCC` (lot+expiry) · `P-TCD` (all). Each has a full
  chain (ASN-3101–3104, to-putaway LPN-00101–104, available stock LPN-00111–114 in 2 generous TEST bins LOC-TC01/02
  Area A, open order OUT-7101–7104), all under ACME/Lyon. Helpers `prodTrack`/`tracksLot`/`tracksExpiry`/`tracksSerial`/
  `trackingSummary`/`testCaseOf`/`testCaseNote`/`docCaseNote`. Same pass hardened 6 ERP screens that hardcoded
  Lot/Expiry columns (`erp-gr-grn`, `erp-gr-inspect`, `erp-pa-tasks`, `erp-inv-count`, `erp-inv-returns`, `erp-rpt-soh`)
  to render a muted `n/a` for untracked attrs (lists) / omit the field (detail/forms). **Serial default → OFF**
  (serials are scanned off the unit, not minted; corrected stale "all default ON" wording in `CLAUDE.md`,
  `01_Master_Data`, `GLOSSARY`, `DATA_MODEL`).

## PWA build

- **Phase 0 — Foundation (2026-06-17):** NEW `assets/pwa-scan.js` shared scan engine —
  `PWAScan.field({id,prompt,…,list,onScan})` returns an inline scan-box with **three modes**: ⌨ Manual (always-visible
  input, also catches keyboard-wedge hardware scanners), 📷 Camera (native `BarcodeDetector` over `getUserMedia`,
  secure-context only — live on `http://localhost`/https, auto-fallback on `file://`), 📋 Pick-from-list. Document-level
  delegation (survives shell rebuild). **Windows fix:** desktop Chrome/Edge ship no `BarcodeDetector`, so a vendored
  **ZXing** UMD (`assets/vendor/zxing-library-0.18.6.min.js`, pure-JS, `file://`-safe) is lazy-loaded on first camera
  open as the fallback (formats restricted to Code 128 / EAN-13 / EAN-8 / QR for speed). Added `resolveScan(code)` to
  `data.js` (case-insensitive; priority LPN → location → product → order → ASN; returns `{code,type,id,entity,label,
  sub,extra}` or null; pack-level barcode carries `extra.level`+factor) + read helpers `prodUom`/`packagingFor`/
  `lpnsAtLoc`/`lpnsOfProductAtSite`. Rebuilt `pwa-shell.js` (data-driven client/site context + bottom-sheet switcher,
  sessionStorage-persisted) and `pwa-home.html` (live task counts from `DB`, tiles tagged "· soon" until their phase
  lands). Rebuilt the 2 lookups (`pwa-md-lookup-loc`/`pwa-md-lookup-prod`) as scan→resolve→show.
- **Phase 1 — Receipt (2026-06-17):** first mutating phase; flows commit to the session-persisted `DB`.
  `pwa-gr-receive.html` rebuilt to mirror `erp-gr-receipt` (source: scan/pick ASN or blind → lines → form → done;
  adaptive qty, flag-driven lot/expiry/serial, condition→disposition Good/Hold/Damaged + reason, over/short vs ASN
  remainder + reason; confirm mints an LPN, increments `asn.line.received`, writes a `receive` `logTxn`, `PWA.save()`s).
  NEW `pwa-gr-inspect.html` (to-inspect worklist; pass→to-putaway / fail→quarantine|hold|damaged + reason + photo).
  NEW `pwa-gr-lpn.html` (LPN label via `barcode.js` + Print). **DB persistence across navigations:** `pwaHydrate()`
  (called once by `pwa-shell.js`) restores a `sessionStorage` snapshot of the mutable collections; `PWA.save()`
  re-snapshots; `PWA.resetDemo()` ("↺ Reset demo data" in the switcher) clears it back to seeds. ERP pages never call
  these, so the ERP keeps its reset-on-load mocks. Verified end-to-end: a PWA receive mints an LPN that appears as live
  stock on the product lookup + as a Putaway task on home; serial / over-short / inspection paths work; reset restores seeds.

### PWA Phase 1–2 — test findings & enhancements (2026-06-18, in progress)
- **#1 — LPN split + batch label print (DONE).** The PWA receive minted exactly **one LPN per confirm**, while the
  ERP (`erp-gr-receipt`) splits a received line into **N plates** (per box/pallet). Added to `pwa-gr-receive.html`:
  a **"Split into LPNs"** control (offers each packaging level above base that yields ≥2 plates — mirrors the ERP),
  **multi-plate minting** (last plate carries the remainder; conservation `Σ qty = base`; lot/expiry/serial genealogy
  carried; serials sliced per plate so each plate holds its own), and a **"Print all N labels"** batch button +
  per-plate label links on the done screen (loaded `assets/barcode.js` into the screen). **No anchor change**
  (`data.js`/shells untouched). Verified: node unit test (conservation + serial slicing across 8 cases); in-browser
  ACME Olive Oil split per Carton → 2 plates [72, 48]; GLBX Vaccine split per Blister-of-10 → 2 plates [10, 10] with
  serials VAXA-0001–0010 / 0011–0020 (20 unique, no overlap); `labelHTML` renders an SVG label; 0 console errors.
- **#2 — per-each split + mixed-pallet LPN + Putaway (2026-06-18, DONE).** Implemented the three real labelling models
  from the domain discussion (1 item → 1 label · N items → N labels · N items → 1 pallet label). **(a) Per-each split:**
  the receive "Split into LPNs" control now also offers the base unit (per each), with a >50-plate safety confirm.
  **(b) Mixed (aggregate) pallet — the transient-parent model:** a new `DB.pallets[]` handling unit holds many
  product/lot lines under ONE license plate (`PLT-…`) + one manifest label. Persistent stock stays homogeneous LPNs —
  the pallet is **transient** and **decomposes** at putaway. Helpers in `data.js`: `nextPalletId` / `palletById` /
  `palletsAtSite` / `palletTotals` / `palletOpenLines` / `decomposePalletLine` (mints a child LPN per placed line,
  carrying lot/expiry/serial, and closes the pallet when empty); `resolveScan` recognises `PLT-`; `'pallets'` added to
  `PWA_DB_COLLECTIONS`; one seed pallet `PLT-00001`. Receiving is **post-hoc** (per the user's refinement): an
  **"📦 Add to pallet"** button on every received line (ASN or blind) defers it onto a session accumulator (a "pallet
  in progress" bar tracks it); **"Close pallet & print label"** then mints one `PLT-…` keyed to the ASN and posts the
  received qty back to the ASN line at close. A line already on the pallet **reopens read-only** (no Confirm/Add — prevents
  double-receipt; only "↶ Cancel confirmation & remove from pallet" reverts it), and the ASN lines list badges it
  "📦 on pallet". `pwa-gr-lpn.html` renders a pallet manifest label for `?pallet=`. **(c) Putaway (NEW
  `pwa-pa-putaway.html`, also lands PWA roadmap Phase 2):** worklist of to-putaway LPNs + pallets → single LPN gets a
  ranked bin suggestion (home→consolidate→category→open) + headroom + excluded-with-reason + commit-time
  capacity/segregation/frozen guards → `available` + putaway `logTxn`; a mixed pallet is scanned → manifest → each line
  placed into a guarded bin → `decomposePalletLine` mints the child LPN. `pwa-home` Putaway tile is live (LPNs + pallets).
  Verified (node decomposition/conservation unit test + in-browser): seed `PLT-00001` → 3 child LPNs across
  home/category/open bins; receive-built `PLT-00002` flows into putaway and decomposes live; single-LPN putaway routes to
  a ranked bin; excluded bins show capacity reasons; 0 console errors. **Files:** `pwa-pa-putaway.html` (new),
  `pwa-gr-receive.html`, `pwa-gr-lpn.html`, `pwa-home.html`, `assets/data.js` (anchor — pallets model).
- **⚠ ERP parity PENDING (2026-06-18).** These features (per-each/per-pallet split, mixed-pallet build + decomposition,
  LPN/pallet label printing) exist **only in the PWA** so far. The ERP (`erp-gr-receipt.html`, `erp-pa-tasks.html`) does
  not have them yet — `erp-gr-receipt` split is display-only with no label printing, and `erp-pa-tasks` has no pallet
  decomposition. **Also flagged: label reprint / re-access** — after the receive "done" screen (or a dead battery / out of
  paper) there's no way back to an already-created LPN/pallet label even though it's in the DB; needed in **both** channels.
  Dual-channel parity is required → the actionable tasks are in `mockups/MOCKUP_STATUS.md` ("▶ NEXT SESSION — label parity
  + reprint"): **A.** ERP parity (split / mixed-pallet / decomposition / label printing), **B.** reprint & re-access in both
  channels (#1 scan-or-pick → reprint, #3 recent-receipts list, optional #2 from the ASN). ✅ **Done 2026-06-18 — see the next entry.**
- **✅ ERP parity + label reprint COMPLETE (2026-06-18).** Both work items landed; every receive / putaway / label action is now
  dual-channel. **A — ERP parity:** `erp-gr-receipt.html` rewritten to **live-mint** real plates (`nextLpnId` + `logTxn`, not the
  old display-only `lpnSeq` counter; now loads `assets/barcode.js`). The split offers **per each** (base unit) as well as per pack
  level (every level yielding ≥2 plates), mints N plates (last carries the remainder, serials sliced per plate, `Σqty = base`),
  posts `received` back to the ASN and honours **Close ASN short**, and the done modal prints **per-plate** labels + **"Print all"**.
  Added the **mixed-pallet build** (per-line "📦 Add to pallet" → pallet-in-progress bar → "Close pallet & print label" mints one
  `PLT-…` keyed to the ASN + a manifest label; Hold/Damaged blocked from a pallet; on-pallet lines reopen read-only — no
  double-receipt; stable per-line `_uid` so pallet membership survives line shuffles). `erp-pa-tasks.html` gained a **"Mixed pallets
  to decompose"** worklist + a decomposition flow that reuses the existing ranked slotting + capacity/segregation/frozen picker and
  mints one child LPN per line via `decomposePalletLine`, closing the pallet when empty. **B — reprint / re-access:** NEW
  **`erp-gr-labels.html`** (Goods Reception → Labels / Reprint) and NEW **`pwa-gr-reprint.html`** (PWA Home → Labels) — both do
  **#1** scan/pick an LPN or pallet → reprint, **#3** a recency-ordered **recent-receipts** recovery list (battery-off recovery), and
  **#2** reprint everything against an ASN; the ERP previews the label inline (shared `labelHTML`), the PWA hands off to the existing
  `pwa-gr-lpn.html`. **No data-model change** — reused `DB.pallets[]` + `nextLpnId`/`nextPalletId`/`decomposePalletLine`/`palletsAtSite`/
  `palletTotals`/`resolveScan` + `barcode.js`. **Anchors touched:** `erp-shell.js` (nav: + Labels / Reprint, "Manual Receipt"→"Receive"),
  `pwa-home.html` (+ Reprint tile), `index.html` (sitemap). Specs re-synced: `02_Goods_Reception.md`, `03_Putaway.md`. **Verified:**
  node data-layer suite (26 assertions — split conservation, serial slicing, per-each, live-mint id uniqueness, `logTxn`, ASN posting +
  close-short, decomposition) + in-browser (0 console errors across all 5 screens; `LPN-00115` minted & ASN-3103 → closed; `PLT-00002`
  built & ASN posted `[120,80]`; `PLT-00001` decomposed → 3 child LPNs; ERP inline preview + PWA `pwa-gr-lpn` handoff both render).
  **Carried limitation:** the ERP is reset-on-load (no `sessionStorage`), so its recent/by-ASN lists reflect seed + current-page mints
  only — production = server DB. `erp-pa-tasks` still uses its local capacity impl (shared-helper migration is a separate flagged task).
- **✅ Putaway split across bins (partial putaway) — ERP + PWA (2026-06-18).** User test finding: a plate that doesn't fit one
  bin must split into two+ bins (was out of scope — v1 had one-LPN-one-bin). Added a **"quantity to place"** field to putaway in
  both channels; placing less than the full qty stores that amount and mints a **child LPN** for the remainder (source stays
  `to-putaway`), looping until fully stored — conserves qty, carries genealogy, re-checks capacity/segregation/frozen for the
  **entered** qty (so a partial fits a smaller bin). Works for single LPNs **and** mixed-pallet lines. **Anchor:** `data.js` — new
  shared `putawayPlace(lpnId, binId, qty, opts)` (whole = stores the plate keeping its id; partial = child + decrement source) and
  `decomposePalletLine` gained an optional `opts.qty` (backward-compatible — omit = whole line). Also fixed the ERP detail
  pre-selection to fall back to a valid suggestion when the product's home is full for the remainder (else the now-full home was
  pre-picked with no confirm button). Spec re-synced (`docs/03_Putaway.md`: split moved from v2 backlog into v1). Verified: node
  suite (13 assertions — conservation, serial slicing, partial vs whole, pallet partial + whole-line backward-compat) + in-browser
  both channels (ERP `LPN-00012` 120 → 50 @ home + 70 @ another bin; PWA same; PWA pallet `PLT-00001` line 24 → 10 + 14; 0 errors).
- **✅ Decompose in any order + Putaway history (Completed tab) — ERP + PWA (2026-06-18).** Two user test findings on putaway.
  **(a) Forced decomposition order:** mixed-pallet lines were walked in array order (`findIndex` first-open), so the operator
  couldn't start with the bulky items in front of them. Now the operator **chooses the order** — ERP renders the manifest as
  **clickable chips** (qty shown; `switchPalletLine(idx)` opens any open line), PWA makes the **manifest rows tappable**
  (`data-line` → set `S.lineIdx`); a partly-placed line keeps its remainder open for the next bin (the auto-advance now prefers
  the line just worked on if a remainder remains, else the first open line). **(b) Finished putaways vanished:** both screens now
  mirror the Receive section's **tabs** — **To put away** (open work) / **Completed**. The Completed tab reads the txn log
  (`type:'putaway'`, site/client-scoped): ERP table = when · LPN · client · product · lot/expiry · qty · from → to · by · source
  + a **Reprint label** action (inline `printLabels`, pulls live lot/expiry/location from the LPN); PWA = recent-putaway cards that
  hand off to `pwa-gr-lpn.html?lpn=` for reprint. Reprint re-prints from the record, never re-mints. **No anchor change** — pure
  screen UI (`erp-pa-tasks.html`, `pwa-pa-putaway.html`); `decomposePalletLine` already accepted any `lineIdx` and `logTxn` already
  recorded every putaway. Spec re-synced (`docs/03_Putaway.md`). Verified: node suite (13 assertions — out-of-order decompose
  2→0→1 closes the pallet; 3 putaway txns logged with site/to/qty; child LPN reprintable; single whole-plate putaway logs 1 txn) +
  in-browser both channels (ERP `switchPalletLine(2)` jumps to the 3rd line; Completed shows seed `LPN-00008` putaway w/ reprint;
  PWA To do/Completed tabs + tappable manifest switch line out of order; **0 console errors**).
- **✅ In-progress / partial-putaway visibility — ERP + PWA (2026-06-18).** User finding: after a **partial** putaway (place 80 of
  100, confirm, 20 left) or a paused pallet decomposition, there was **no read-only context** on return — you couldn't see that 80
  already went to a specific bin, or which pallet lines were placed where. Added a friendly **progress UX**: (worklist) a **"partial"**
  badge + **"X of Y placed"** and a **Resume ›** action on any part-worked plate/pallet; (single-LPN detail) a read-only **"Partially
  put away"** panel — placed/original, a progress bar, remaining, and each prior placement (qty → bin · child LPN · when · by);
  (pallet decompose) a read-only **"Partially decomposed"** history + the PWA manifest now shows **placed ✓ → bin** per done line and
  **"Z left · Y placed"** on a part-placed line. **Anchor (`data.js`):** new `putawaysFromSource(sourceId)` (placements recorded
  against a source LPN id **or** a pallet id) + `lpnPutawayProgress(lpnId)` (placed/remaining/original + placements for a still-open
  plate); seeded **two in-progress demos** so it shows on load — `LPN-00120` (80/100 placed, child `LPN-00121`) and `PLT-00003`
  (1-of-3 lines placed, child `LPN-00122`). The two screens now **omit `ref:'putaway'`** on the single-LPN `putawayPlace` call so a
  partial child's txn `ref` defaults to its **source LPN id** (genealogy link); a whole placement still records `ref:'putaway'`, and
  pallet children already carried `ref = pallet id`. So one helper covers both. Files: `erp-pa-tasks.html`, `pwa-pa-putaway.html`,
  `assets/data.js`. Spec re-synced (`docs/03_Putaway.md`). Verified: node suite (seeds = 80/20/100 + PLT 1-placed; a live partial's
  child `ref` === source; a whole placement keeps `ref:'putaway'`; child LPN excluded from progress) + in-browser both channels
  (ERP Resume + both progress panels render the placement history; PWA partial badges, LPN progress card, manifest **✓ → bin**; a
  live 60/120 partial links child→source; **0 console errors**). *Mock caveat: the PWA shows the new seeds on fresh/Reset state only —
  a returning tab whose `sessionStorage` snapshot predates the seed needs one "Reset demo data" (server DB removes this in the build).*
- **✅ Partial accept / reject on inspection — ERP + PWA (2026-06-18).** User finding: inspection was all-or-nothing (Pass **or**
  Fail the whole plate); they needed *100 to inspection → accept 90 (→ putaway), reject 10 (won't enter stock)*. Made the QC decision
  **quantity-based** in both channels: an **accepted quantity** field (default = whole plate) with **Accept all / Reject all**
  shortcuts; a live note ("Accept 90 → putaway · reject 10 (won't enter stock)") reveals the **disposition + reason** only when a
  shortfall is rejected. **Anchor (`data.js`):** new shared `inspectionSplit(lpnId, acceptQty, opts)` — accepted units → the original
  plate continues as **to-putaway**; rejected units → a **new child LPN** at a blocked disposition (**quarantine / hold / damaged**),
  routed to the quarantine location; whole-accept / whole-reject keep the plate's id; conserves qty (`accepted+rejected=original`),
  carries lot/expiry/serial genealogy, writes `inspect` txns (rejected child `ref` = source LPN). The **ERP inspect screen now mutates
  `DB`** (it previously only recorded a local decision + banner) — its Pending/Passed/Failed/All tabs derive from live status + the
  `inspect` txn log, scoped to inspection-relevant plates, and a **decided plate opens read-only**. Added `inspect` to the
  `erp-rpt-txns` type filter + ADJ_T category (internal, no on-hand delta — rejects sit in quarantine, still accounted). Files:
  `erp-gr-inspect.html`, `pwa-gr-inspect.html`, `assets/data.js`, `erp-rpt-txns.html`. Spec re-synced (`docs/02_Goods_Reception.md`).
  Verified: node suite (9 assertions — 60→50/10 split conserves total on-hand, child → quarantine-type loc, rejected child txn refs
  source, re-inspect of a decided plate returns null, accept-all keeps id → to-putaway) + in-browser both channels (ERP 60→50/10 with
  Passed/Failed tabs + read-only decided view; PWA 60→45/15 persists so the accepted **45 appears in the Putaway worklist** while the
  rejected child stays out; **0 console errors**). *Same ERP session caveat as putaway: the accept→putaway hand-off survives across
  screens in the PWA (sessionStorage) but the ERP reloads seed `data.js` per page (server DB removes this in the build).*

- **✅ Inspection reason codes → master data + damage-found-at-putaway reject — ERP + PWA (2026-06-18).** Two linked user
  findings. **(a)** Both inspection screens (`erp-gr-inspect`, `pwa-gr-inspect`) had a **hardcoded** reject-reason list that
  ignored the Reason Codes master; rewired so the reason dropdown is driven by the chosen **disposition** via
  `reasonsFor('status', disp)` (Quarantine / Hold / Damaged each show their own curated reasons; repopulates on change) —
  matching `inv-status`/`inv-adjust`/`inv-returns`. No data change. **(b)** Putaway was place-only; a "**⚠ Report damage /
  reject**" control was added to the single-LPN putaway detail in **both** channels (`erp-pa-tasks`, `pwa-pa-putaway`): peel a
  damaged sub-qty (or the whole plate) to a blocked disposition with a **master-data reason** + photo; rejected qty → child LPN
  at the QA/quarantine location (**excluded from availability**), good remainder stays **to-putaway**. **Anchor (`data.js`):**
  new `putawayReject(lpnId, rejectQty, opts)` (mirrors `inspectionSplit` for a `to-putaway` source; logs a `type:'status'`
  txn, not `putaway`). Specs re-synced (`docs/02`, `docs/03`). Verified: node suite (16 assertions) + in-browser both channels
  (`LPN-00012` 120 → reject 20 → child @ QA-01, 100 stay to put away; **0 console errors**).
- **✅ PWA Phase 3 — Pick / Dispatch (`pwa-so-pick.html`) (2026-06-18).** The floor-operator outbound flow, scan-driven and
  aligned to the ERP Stock-Out screens. One guided pass: **pick list** (orders to fulfil at the operator's client+site) → tap/
  scan an order → per-line **pick** (scan the bin then the LPN/product to confirm; quantity with **short-pick**; **serials**
  for serial-tracked lines — prefilled off the unit, required, guarded) → **Load & dispatch** (carrier + proof-of-load photo +
  dispatch note) → **issue** (decrement LPNs, `dispatched` when emptied) + **delivery note** (`order.shipments[]`, `DN-…`).
  **Honours an existing ERP allocation** (`line.alloc[]`) when present, else **auto-FEFO/FIFO** the remaining qty (serves the
  classic *and* Express paths). The commit is a faithful copy of `erp-so-fulfil.confirmFulfil` (same `outboundCandidates` /
  `outboundComplete` / `clientAllowsBackorder` → **back-order** `partial` or **short-close**), so PWA-issued shipments render in
  `erp-so-note.html`. **No `data.js` change** — reuses the Section-04 helpers. Home hub: `pick` tile went **LIVE**; sitemap
  updated. Files: `pwa-so-pick.html` (new), `pwa-home.html`, `index.html`. Spec re-synced (`docs/04_Stock_Out.md`). Verified
  in-browser, ACME + GLBX contexts: allocated full pick (`OUT-7001`: LPN-00008 240→180, `DN-7001-1`, complete), serial pick +
  guard (`OUT-7104`/P-TCD: serials `SN-TCD-…`, guard blocks blank), short-pick → **short-close** (`OUT-7101` 70/120, ACME),
  short → **back-order** (`OUT-7005` 50/70 → `partial`, 20 owed, GLBX); **0 console errors**.
- **✅ PWA Phase 3 — validation refinements (2026-06-18, from user review).** Three points from first review of `pwa-so-pick`:
  **(a)** the `allocated`-vs-`open` distinction read as two badges with no felt difference — the order view now states the
  **provenance** ("✓ reserved by the office" vs "auto-allocated FEFO") and the list badge reads **reserved**; **(b)** "Confirm
  pick" worked without scanning — it's now **gated on both the bin + LPN/product being confirmed** (scan or tap-from-list),
  with an audited **manual override** for the can't-scan case; **(c)** added **To pick / Dispatched tabs** (mirrors Putaway's
  *Completed*) — *Dispatched* lists the `order.shipments[]` delivery notes for the site/client, tappable to a read-only note
  detail (lines · serials · carrier · outcome). No `data.js` change. Verified in-browser (scan-gate blocks then enables; manual
  override path; `DN-7101-1` lands in Dispatched + opens its note; **0 console errors**).
- **✅ PWA Phase 4-core — Move + Count (2026-06-19).** The rest of the core loop on the floor; **two new screens, no anchor
  change** (`data.js`, both shells and `wireframe.css` untouched — pure reuse of existing helpers + the putaway/pick scan-flow
  template). **`pwa-inv-move.html`** (intra-site Move): tabs *Move* (scan/pick an `available` plate for the current client+site) /
  *Recent* (history from `DB.moves`); scan plate → quantity → scan/pick destination via Putaway's **ranked-bin block** (home →
  consolidate → category → open, capacity read-out + *excluded* list); **partial** splits a child LPN at the destination (genealogy +
  serials sliced) and leaves the remainder, **whole** relocates the plate (keeps id+status); **mirrors every enforced rule** — refuses
  a **frozen** source *or* destination, runs **capacity + client–area segregation** on the destination (`binCapacityForAdd` /
  `binSegregationOk`), writes `MOV-…` to `DB.moves` + a `move` `logTxn`; optional condition photo/note; deep link `?lpn=`.
  **`pwa-inv-count.html`** (cycle Count): tabs *Count* / *Submitted*; scan a **storage bin** → its countable plates (qty>0, this site,
  not in-transit) load prefilled at system qty (lot shown only where the product tracks it); key the count, tap **0** = **missing**,
  scan an unlisted item = **found** (mints a plate on approval); **blind-count** toggle hides system qty; one sheet **accumulates many
  bins**; **Submit** writes a single `pending-approval` count sheet to `DB.counts` in the *exact* shape `erp-inv-count.html` reads
  (`locations[].lines[].{lpn,product,lot,systemQty,countedQty,found?}`) — the supervisor approves on the ERP to correct stock; optional
  count evidence; deep link `?loc=`. Home hub: `move` + `count` tiles went **LIVE**; sitemap updated. Files: `pwa-inv-move.html`,
  `pwa-inv-count.html` (new), `pwa-home.html`, `index.html`. Spec re-synced (`docs/05_Inventory_Operations.md`). Verified: node suite
  (**22 assertions** — inline-script syntax for both screens + all shared assets; Move partial-split conservation + child mint + `move`
  txn, whole-move id/qty preserved, freeze locks the bin; Count sheet shape + ERP `applyApprove` round-trip: short 150→148, missing 5→0,
  **found** mints a 24-unit plate, net −2+24) **+ in-browser, 0 console errors** — live partial move LPN-00008 240→140 + child
  `LPN-00123` @ 1-A-01-R1-B02 (`MOV-6002` in Recent); count LOC-A0102 → `CNT-9004` pending-approval persisted (net +17); home shows both
  tiles live + the Count badge picks up the new sheet. (PWA→ERP shown ERP-compatible via the node `applyApprove` sim — the ERP reloads
  seed `data.js` per page in the mock; `preview_screenshot` stayed renderer-stuck, so verified by DOM snapshot + `preview_eval` + node.)

- **✅ PWA Phase 4b — Ad-hoc / emergency dispatch (`pwa-so-dispatch.html`) (2026-06-19).** The floor's controlled mirror of **blind
  receipt** for the *“PC off / customer truck waiting, no ERP order”* case — the missing outbound **origination** path (today the PWA can
  only pick an ERP-created order). **NOT free-form blind shipping:** a 3-step one-pass flow that forces the governance an outbound needs.
  **(1) Governance gate** — mandatory **ship-to consignee** (`consigneesFor`, client-scoped; blocks if the client has none) **+ manual
  reference + reason** (new master-data domain `dispatch`) **+ operator** (audit). **(2) Build + pick** — scan a **product** (FEFO/FIFO
  auto-allocate via the same `outboundCandidates` a normal pick uses) **or a specific LPN** (grab-this-pallet), set qty, then the
  **identical scan-confirm pick sub-flow** as `pwa-so-pick` (scan bin → scan LPN/unit → qty → **serials where tracked**); a `freeForWork`
  guard stops any plate being allocated twice across lines. **(3) Load & dispatch** — carrier + proof-of-load photo/note → commit
  **creates the outbound order inline** (`nextOutId` → `OUT-…`, `adhoc:true`, `approval:'pending'`, reason + operator), **issues the
  stock** (decrements LPNs, `dispatch` `logTxn`), writes a real **delivery note** (`DN-…`), posts `dispatched` (ordered qty == shipped →
  complete by construction — ad-hoc documents exactly what shipped, so no back-order math). **Guards mirrored:** frozen-scope & expired
  plates excluded, wrong-client/site refused, serial-on-issue required. **Role-gated** (shown to all, like Express Fulfil) + **flagged for
  back-office approval** on the done screen (the inverse of reconciling a blind receipt to its PO). *(Non-customer removals — samples / QA
  / scrap — stay on the adjustment-out path, not here.)* **Anchors (`data.js`):** new `dispatch` reason domain (renders automatically in
  `erp-md-reasons` — generic over `DB.reasonDomains`) + `nextOutId()`; no shell/CSS change. Also `pwa-home.html` (+ Ad-hoc dispatch tile,
  live), `pwa-so-pick.html` (+ “No ERP order? ＋ Ad-hoc dispatch” discovery link), `index.html` (sitemap). Spec re-synced
  (`docs/04_Stock_Out.md`). Verified: node suite (**22 assertions** — `dispatch` domain + `reasonsFor`, `nextOutId`=OUT-7105, consignees,
  full commit round-trip [order appended w/ adhoc+approval+governance, stock issued + conservation, `dispatch` txn, `outboundComplete`,
  consignee resolves], all 3 touched inline scripts + shared assets parse) **+ in-browser, 0 console errors** — gate → add P-TCA 50 (FEFO)
  → scan-confirm pick → carrier → commit created **OUT-7105** (LPN-00111 200→150, **DN-7105-1**, ad-hoc + approval-pending), dispatch
  **persists cross-screen** into `pwa-so-pick` → Dispatched, guards fire (empty-gate, wrong-client LPN-00021, expired LPN-00022 blocked,
  already-added). **Carry-overs (flagged):** (a) ERP-side surfacing of the `approval:'pending'` flag (review queue / badge) — data stamped,
  ERP screen untouched this pass; (b) classic `pwa-so-pick` + ERP dispatch omit `logTxn('dispatch')` on issue (pre-existing) — ad-hoc logs it; align in the build.

- **✅ PWA Phase 5 — Inventory-Ops batch (4 screens, closes the PWA) (2026-06-19).** The four deferred Inv-Ops floor screens, all
  scan-first, all mutating the live session `DB` and mirroring the locked enforced rules; each reuses existing `data.js` helpers + the
  established scan-flow templates. **No `assets/` anchor change** — pure new screens; `pwa-home.html` (+ 4 live tiles with task-count badges)
  and `index.html` (sitemap) updated. **`pwa-inv-transfer.html`** — inter-site **ship / receive** (creation stays in the ERP; intra-site
  move is `pwa-inv-move`): tabs To ship / To receive / Done; ship scan-confirms each plate (mis-ship guard + override) → in-transit
  (whole, or **partial child split**, with a frozen-source guard) + `transfer-ship` txn; receive scans/picks a destination bin at the to-site
  (**capacity + segregation + freeze** checked) → available + site reassigned + `transfer-receive` txn. **`pwa-inv-physical.html`** —
  freeze → count → post: **Freeze re-snapshots system qty at the freeze moment** and locks the scope (the locked freeze rule then blocks
  Putaway/Move/Transfer/Allocation cross-screen via `isLocFrozen`); scan/tap each in-scope location → count (prefilled system qty, **0** =
  missing, scan-unlisted = **found**, blind toggle) → save; **Post** corrects every plate, mints found plates, logs `count` txns, unfreezes;
  **Abandon** unfreezes with no corrections (reuses the cycle-count interaction). **`pwa-inv-repack.html`** — scan a source plate, pick a
  kind: **split** (1→several, remainder stays) · **merge** (several same product+lot+expiry → 1) · **repack** (1→1 new packaging, qty +
  genealogy unchanged) · **re-kit** (free outputs); a live **balance** guard gates Confirm; commit consumes sources (split leaves remainder,
  else `consumed`), mints outputs (repack/merge carry serials), logs a `repack` txn; **frozen-source guard**. **`pwa-inv-returns.html`** —
  tabs To process / Processed; process an office-created open return **or** build one one-pass (kind put-back/customer; scan product/LPN →
  qty/lot/reason); per line a **disposition** — Restock → bin (scan/pick a bin, **capacity + segregation** checked) · Via Putaway (→ staging,
  directed-putaway queue) · Quarantine / Damaged (→ blocked plate); commit mints the LPN(s) at the right status+loc + a `return` txn (mirrors
  `erp-inv-returns`). Specs re-synced (`docs/05_Inventory_Operations.md`). Verified: inline-script syntax (node) for all 4 + shared assets,
  **+ in-browser live commits, 0 console errors** — Transfer **TRF-8002** Lyon→Paris ship (LPN-00020→in-transit) then **received** at Paris
  (→ available @ C-01, site reassigned); Returns **RET-9002** restocked (LPN-00123, capacity-checked) + new **RET-9003** quarantined
  (LPN-00124 @ QUAR-01); Physical **PHY-7002** frozen (LOC-B0102 `isLocFrozen`→true) → counted (empty + 50→49) → posted (LPN-00009 50→49,
  unfrozen); Repack **split** LPN-00016 300→100+100 (+100 remainder, RPK-7001) and **merge** LPN-00051+00052 →240 (RPK-7002). Conservation
  holds on every commit. **Carry-over (flagged):** ERP `erp-inv-repack` omits a frozen-source check that the PWA enforces — align in the build.
  **This closes the PWA and the mockup phase (Phase 2): both channels fully built on the shared `data.js`.**

## Feedback resolutions — Phase 5 (Inventory Operations)

| Date | Screen | Change |
|------|--------|--------|
| 06-17 | `erp-inv-transfer` | Partial quantities on Move + Transfer (default whole plate); partial auto-splits a child LPN. |
| 06-17 | `erp-shell.js` + `wireframe.css` | Globalized searchable dropdowns app-wide (`enhanceSelects`/`initSS` + MutationObserver; `.ss-*` styles). Skips topbar chrome, `<select multiple>`, `[data-no-ss]`. |
| 06-17 | all Inv-Ops list screens | Mandatory **Since date** (default last 30d) on terminal/All tabs only; **hidden** on pending/active tabs; non-terminal rows always show. Stock Status exempt (current-state view; protect with server-side paging). |
| 06-17 | `erp-inv-transfer` | Default tab = Moves (intra-site); each tab owns one create button; "Transfer orders (inter-site)" renamed. |
| 06-17 | `erp-inv-count` | Added ERP create flow, then **model changed to a count SHEET spanning many locations** (`count.locations[]`, no freeze); worksheet add bin/Area, keyboard-fast inline counts (Enter→next), blind-count toggle; approve corrects all plates across all locations. |
| 06-17 | `erp-inv-count` | **Bulk approve/reject** on Pending; risk control = configurable **variance tolerance** (default 0) on the largest plate-level Δ (not a zero-only rule); out-of-tolerance flagged ⚠ review. Added **Gross |Δ|** column (so +100/−100 reads Net 0 / Gross 200 / Max 100). |
| 06-17 | `erp-md-reasons` + `erp-inv-status` | Added **`Expired`** as a 5th blocked status (expiry-centric WMS; `BLOCKED_STATUSES += expired`); enriched Hold/Quarantine/Available reason lists; moved the expiry reason out of Damaged. Declined splitting Hold; Scrap/Lost stay as adjustments. |
| 06-17 | `erp-inv-status` | **Expired-but-allocatable bug fixed** — `outboundCandidates`/`fefoAllocate` now check the date (`WMS_TODAY`/`isExpired`); seeded LPN-00022 (expired but `available`). Added "⚠ Select expired" quick-action, per-row ⋮ hub (view history + deep-links), and `applyStatus` guardrails (release confirm; warn when blocking a reserved plate, listing the orders). |
| 06-17 | `erp-inv-adjust/transfer/repack/count` | The 4 Stock-Status ⋮ deep-links now **pre-load** the target form (plate/location preselected) via `?lpn=`/`?loc=`; guards keep them from adopting an ineligible plate (form opens unfilled). |
| 06-17 | `erp-inv-physical` | Implemented **+ New stock-take** create flow (site/Area scope, live scope preview, snapshot to `open`). Added **overlap guard** (block a take whose locations are already in an `open`/`frozen` take at the same site). |
| 06-17 | `erp-inv-returns` | **Restock split into two paths:** direct-to-bin (immediate `available`) vs **via Putaway** (mints `to-putaway` at staging → enters the directed-Putaway queue). Direct-restock bin picker now runs the **shared capacity + segregation** guard. |

## Feedback resolutions — Phase 6 (Reports)

| Date | Screen | Change |
|------|--------|--------|
| 06-17 | NEW `erp-rpt-stockcard` | **Stock Card / Product Ledger** (10th report) — product (or lot) picker → header + on-hand-by-lot → full chronological `DB.txns[]` ledger with signed qty + running balance (anchored to live on-hand). Deep-links `?product=&lot=`; ⋮ link from Stock Status. Kept separate from Traceability (recall = narrow) vs Stock Card (audit = broad). |
| 06-17 | NEW `assets/barcode.js` + 8 screens | Dependency-free **Code 128** SVG + `labelHTML()`/`printLabels()`. Rolled into Locations, Products (Barcodes tab), LPN labels, ASN, Putaway, Outbound, GRN, Delivery Note. Symbology note: Code 128 in the mock; EAN-13 / GS1-128 (lot+expiry via AIs) in the build. |
| 06-17 | `erp-md-products` + `erp-md-uom` | Clarified the **3-layer packaging model** (global Units → reusable shared Templates → per-product instance). Rebuilt the Product UoM & Packaging tab into a live generator reading the product's own `DB.packagings` (base unit locked to product UoM; start-from-template clones + blanks barcodes; add/edit/remove level with cascading factor-to-base recompute; per-level barcode). Barcodes tab renders from the same model. UoM screen's product rows became read-only with "Edit on product →". Added a **Generate internal** EAN-13 button (GS1 restricted-circulation prefix `20` + check digit, flagged INTERNAL) for unbarcoded/repacked goods. |
