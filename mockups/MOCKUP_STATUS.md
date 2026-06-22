# WMS Mockups — Build Status

> Live build state for the **Mockups** phase (Phase 2 in `docs/00_Project_Overview.md`). Kept lean on purpose.
> **Last updated: 2026-06-19.**
>
> **This file = current state + roadmap only.** Everything else has a home; don't duplicate it here:
> | For… | Read |
> |---|---|
> | Vocabulary, tech rules, conventions | `CLAUDE.md` |
> | Functional specs (per section) | `docs/00_Project_Overview.md` … `docs/06_Reports.md` |
> | Locked vocabulary | `docs/GLOSSARY.md` |
> | Entities, fields, helpers | `docs/DATA_MODEL.md` |
> | The mutation invariant (every blocking rule) | `docs/BLOCKING_RULES.md` |
> | What was built when + feedback history | `docs/BUILD_LOG.md` |
> | Edge-case hardening — status/workflow gaps + the 25 fixes (per-task status + verification) | `EDGE_CASE_TRACKER.md` |

## ▶ Current state & next step

- **ERP: complete + dual-channel parity DONE** — all 6 sections (Master Data, Goods Reception, Putaway, Stock-Out,
  Inventory Ops, Reports), the pre-PWA hardening, the late cross-cutting features (photos, notes, client–user mapping,
  tracking test data), **and (2026-06-18) full ERP parity for the new receive/putaway features + label reprint**:
  per-each/per-pack LPN **split** (live-mint), **mixed-pallet build + decomposition**, real LPN/pallet **label printing**,
  and a **Labels / Reprint** screen (`erp-gr-labels.html`). See `docs/BUILD_LOG.md`.
- **PWA: Phases 0 (Foundation), 1 (Receipt), 2 (Putaway), 3 (Pick / Dispatch) + 4-core (Move + Count) BUILT & verified** (0 console
  errors). Scan engine, live session-`DB` mutations, home hub, 2 lookups, Receive (incl. LPN **split** + **mixed-pallet** build) /
  Inspect / LPN-label, **Putaway** (single LPN + **mixed-pallet decomposition** into child LPNs), a **Reprint label** screen
  (`pwa-gr-reprint.html`), **Pick / Dispatch** (`pwa-so-pick.html` — scan-driven pick → load → issue + delivery note), **Move**
  (`pwa-inv-move.html` — scan plate → scan dest → confirm; partial split + shared frozen/capacity/segregation guards) and **Count**
  (`pwa-inv-count.html` — scan loc → counts, found via scan-unknown, missing = 0 → submit a `pending-approval` sheet the ERP approves) —
  all flowing across screens (receive → putaway → live stock → pick → dispatch; move/count mutate + feed the ERP).
- **PWA: COMPLETE (2026-06-19)** — all phases built & verified (0 console errors): Phase 4b **ad-hoc dispatch** (`pwa-so-dispatch.html`)
  + Phase 5 **Inv-Ops batch** — `pwa-inv-transfer` (inter-site ship/receive), `pwa-inv-physical` (freeze → count → post),
  `pwa-inv-repack` (split / merge / repack / re-kit), `pwa-inv-returns` (re-enter + disposition). **18 PWA screens; all 13 home tiles live**
  (incl. the edge-case pass — `pwa-inv-dispose`, `pwa-so-rtv`). See the done blocks below.
- **Edge-case hardening pass — COMPLETE (2026-06-19).** A pre-coding audit found **25 status/workflow edge-case gaps** (unhappy paths:
  refuse-delivery, disposal/scrap, return-to-vendor, in-transit loss, damage-at-pick, dispatch audit + re-validation, freeze on
  adjust/repack, expiry blocks, maker-checker, …). **All 25 implemented across ERP + PWA with full dual-channel parity and verified**
  (37 data-layer assertions · all-files syntax sweep · in-browser load smoke + flow round-trips, 0 console errors). Added 2 new ERP
  screens (`erp-inv-dispose`, `erp-so-rtv`) + 2 new PWA screens (`pwa-inv-dispose`, `pwa-so-rtv`). **Per-task detail + verification:
  `EDGE_CASE_TRACKER.md`**; the global done-block is below.
- **▶ NEXT — MOCKUP PHASE (Phase 2) COMPLETE + edge-case hardened.** Both channels are fully built, cross-referenced and verified on
  the shared `data.js`. The agreed next deliverable is the **Cost Estimation (man-days) + DEV-phase plan** (Phase 3 — technical
  implementation, `docs/00_Project_Overview.md`); the closed edge-cases are scoped, demonstrated units of work that feed that estimate.
  Remaining: the **known limitations carried into the coding phase** (below) + optional theme polish.

## ✅ DONE (2026-06-22) — Oil & gas clients + client–area segregation ON (data.js)

> Post-mockup data extension for the real client. **3 oil & gas clients** on the (renamed) Luanda site — Technip
> Energies · Schlumberger · Yinson — each with a global `CAT-OG` category, 12 products across all tracking profiles,
> suppliers/carrier/consignees, and full receive → putaway → stock-out chains (ASNs incl. a partial; available +
> to-putaway LPNs; outbound incl. a short-close + a back-order). Sites **Lyon DC / Paris Hub → Luanda / Soyo (Angola)**.
> **Client–area segregation turned ON** (`settings.clientAreaSegregation:true`, a **confirmed client requirement**):
> each O&G client has a **dedicated Storage Area** (D=Technip, E=Schlumberger, F=Yinson) with heavy bins; B=Globex,
> A + Soyo-C shared. `binSegregationOk` now blocks cross-client putaway/move/transfer/restock. Decision recorded
> forward in `docs/` + `delivery/` + `CLAUDE.md`. **Verified:** node data-layer suite — **167 assertions, 0 fail**.
> *(`data.js` is a shared anchor — see `docs/BUILD_LOG.md` for the full entry.)*

## ✅ DONE (2026-06-19) — Work-item assignment ("dispatch to a person") + My-requests filter (ERP + PWA)

> A lightweight cross-cutting facet — **one optional `assignee` (→ User.id) on work items + a "My requests / My tasks" filter** at the top of every main list. **No new screens, no new entity.** A supervisor *dispatches* a request to a person in the ERP; both channels can **filter to "mine"**; the PWA also offers per-task **self-claim**. Unassigned = **"Any"** (the default). Full detail in `docs/DATA_MODEL.md` → *Work-item assignment*.
>
> - **Scope (confirmed with user) — "core floor queues":** Outbound (pick/dispatch/fulfil) · Putaway · Inspect · Count · Physical · Transfers · Returns · RTV · Receive (ASN) · Disposal. Putaway & Inspect carry the field **on the LPN/pallet** (no document). Adjustments & Repack excluded (back-office).
> - **Foundation (`data.js`):** optional `assignee` on the work-item collections + LPN/pallet; `DB.currentUserId` (mock; ERP=`U-002`); helpers `assigneeName · isMine · isAssignedTo · assignableUsers · assigneeFilterOptions · assigneePickerOptions · assigneeFilterPass`; a small demo seed (a few items pre-assigned to `U-002`/`U-003`, rest "Any").
> - **ERP (10 screens):** an **Assignee** filter (`Any · ★ My requests · each user`) + **Assignee column** + a **dispatch picker** in each create/edit/detail (persists onto the live record). `so-orders` (reference) · `gr-asn` · `gr-inspect` · `pa-tasks` (LPN **and** pallet rows) · `inv-count` · `inv-physical` · `inv-transfer` (keys off `fromSite`) · `inv-returns` · `so-rtv` · `inv-dispose`. (so-alloc/dispatch/fulfil inherit the order's assignee.)
> - **PWA (11 screens):** a shell-injected **`All / My tasks`** toggle (on `data-pwa-assignable` screens) that repoints `DB.currentUserId`→`PWA.userId` (`U-003`), filters each task list to "mine", and shows **👤 assignee + Claim/Release** per task. `so-pick` (reference) · `gr-receive` · `gr-inspect` · `pa-putaway` (LPN+pallet) · `inv-count` · `inv-physical` · `inv-transfer` (both tabs) · `inv-returns` · `so-rtv` · `inv-dispose` · `home` (mine-aware tile counts).
> - **Anchors touched:** **`data.js`** (the field + `currentUserId` + 7 helpers + seed), **`pwa-shell.js`** (`PWA.userId`/`mineOnly`/`setMine`, the `currentUserId` repoint, the `data-pwa-assignable` toggle bar), **`wireframe.css`** (one `.pwa-mine-bar` block). Spec synced: `docs/DATA_MODEL.md`.
> - **Demo users renamed** to the client's team: `U-002` **Benjamin Felix** (ERP user / supervisor) · `U-003` **Samer Merhi** (PWA floor operator) · `U-004` **Nicolas Masserey** (Paris). `U-001` Alice Bernard / `U-005` Sara Conti unchanged.
> - **🔑 Coding-phase carry-over (flagged, not built):** **PWA self-claim must be ROLE-GATED** in the implementation — same posture as Express Fulfil / ad-hoc dispatch (shown to all in the mock). ERP dispatch should likewise respect role/scope. *(Same PWA-snapshot caveat as prior phases: a returning tab needs "Reset demo data" once to pick up the seeded assignees.)*
> - **Verified:** 49 node data-layer assertions (helpers/seeds/names/Any-label/filter-pass + post-rename) · all **60 inline scripts parse-clean** · in-browser smoke on every distinct shape — ERP `so-orders` / `inv-transfer` / `pa-tasks` / `gr-asn`, PWA `so-pick` / `pa-putaway` / `inv-transfer` — filter + column + dispatch + toggle + claim all working, **0 console errors**; "My requests" narrows correctly (e.g. ERP user Benjamin sees only his rows; PWA Samer's putaway 9 → 1).

## ✅ DONE (2026-06-19) — Edge-case hardening: 25 status/workflow gaps closed (ERP + PWA)

> Pre-coding **unhappy-path audit → fix program.** Full detail + **per-task status** live in **`EDGE_CASE_TRACKER.md`** (the
> authoritative log); this block is the orchestrator's global overview. **All 25 implemented and verified — no remaining gaps —
> with full dual-channel parity for every floor-relevant flow.**
>
> - **🔴 Critical (data-integrity):** dispatch now writes a `dispatch` `logTxn` audit row **and** re-validates frozen/expired/blocked
>   plates at commit (`dispatchGuard`, C1); **adjust + repack now refuse a frozen stock-take scope** (`isLocFrozen`, C2).
> - **🟠 High:** **refuse delivery at the door** (no stock minted, ASN→`refused`) + ASN void/cancel · first-class **Disposal / Scrap**
>   (new `erp-inv-dispose`, approval-gated, terminal `disposed`) · **Return-to-vendor / client** (new `erp-so-rtv`, ships stock back to
>   a supplier/client — the missing non-consignee outbound) · **in-transit loss / short / damaged-receive + write-off** (`lost`) ·
>   **damage / not-found at pick** (`pickReject` + auto count sheet) · **expired stock blocked** from `available` at receipt + putaway.
> - **🟡🔵 Medium/Low:** putaway overflow-park · mixed-pallet line reject · maker-checker on every approval (`sameActor`) ·
>   orphan-allocation warnings · wrong-client receipt guard · serial count + duplicate validation on issue · duplicate-receipt guard ·
>   mis-putaway/mis-pick guards · cancel/release mid-flight · master-data receipt reasons (temp-excursion / seal-broken) · cold-chain
>   carrier warning · over-receipt approval gate · hold-release client sign-off · GRN-per-receipt · blind↔open-ASN reconciliation.
> - **PWA parity (verified live, 0 console errors):** **refuse** (`pwa-gr-receive`) · **disposal raise** (`pwa-inv-dispose`, maker-checker —
>   floor raises, ERP approves) · **RTV ship** (`pwa-so-rtv`) · transfer **write-off** (`pwa-inv-transfer`); both new PWA screens wired into
>   `pwa-home` tiles. Back-office-only flows (approvals, expiry sweep, order cancel, hold sign-off, adjust) stay **ERP-only by design**
>   (no scanner counterpart) — see the tracker's *Channel parity* section.
> - **Anchors touched:** **`data.js`** — new statuses `disposed`/`lost`, `ASN.state` (`cancelled`/`refused`), collections
>   `DB.disposals/rtvs/grns/refusals`, reason domains `dispose`/`refuse`/`rtv`/`receipt`, ~20 helpers + seed (overflow bins, `LPN-00040`,
>   `DSP-7001`, `RTV-7001`). **`erp-shell.js`** — nav: Disposal (Inventory) + Return-to-vendor (Stock-Out). **`pwa-home.html`** — 2 tiles.
>   **4 new screens, ~19 edited; no `wireframe.css` change.**
> - **Verified:** 37 node data-layer assertions · syntax-parse of all 20 changed/new files · in-browser load smoke (0 console errors) +
>   live flow round-trips (refuse→REF-…, RTV ship→stock issued, transfer write-off→`lost`, dispatch guard/txn, disposal raise).
> - **Companion artifact:** the original prioritized gap analysis — `edge-case-gap-analysis.html`.

## ✅ DONE (2026-06-19) — PWA Phase 5: Inventory-Ops batch (closes the PWA)

> The four deferred Inv-Ops floor screens. **All scan-first, all mutate the live session `DB` and mirror the locked enforced rules**
> (`docs/BLOCKING_RULES.md`); each reuses existing `data.js` helpers + the proven scan-flow templates. **No `data.js`/shell/CSS anchor
> change** — pure new screens; `pwa-home.html` (+ 4 tiles, all live) and `index.html` (sitemap) updated.
>
> - **`pwa-inv-transfer.html` (inter-site ship / receive).** The floor side of inter-site transfers (creation stays in the ERP; intra-site
>   relocation is the separate `pwa-inv-move`). Tabs **To ship** (drafts from this site) / **To receive** (in-transit to this site) / **Done**.
>   **Ship**: scan-confirm each plate (mis-ship guard + override) → commit sends plates **in-transit** (whole plate, or **partial split** of a
>   child plate leaving the remainder at origin) with a **frozen-source guard** + `transfer-ship` txn. **Receive**: scan/pick a destination bin
>   at the to-site → **capacity + segregation + freeze** checked live → commit makes each plate **available** (site reassigned) + `transfer-receive` txn.
> - **`pwa-inv-physical.html` (physical inventory — freeze · count · post).** Tabs **Open** / **Counting** / **Closed**. **Freeze** an open take →
>   **re-snapshots system qty at the freeze moment** (movement stops now) and locks the scope — the locked freeze rule then **blocks Putaway / Move /
>   Transfer / Allocation cross-screen** (`isLocFrozen`). Scan / tap each in-scope location → count its plates (prefilled system qty; tap **0** = missing,
>   scan an unlisted item = **found**, **blind-count** toggle) → save. **Post** (all counted) corrects every plate to the counted figure, **mints found
>   plates**, logs `count` txns, and **unfreezes**; **Abandon** unfreezes with no corrections. Reuses the cycle-count interaction.
> - **`pwa-inv-repack.html` (split / merge / repack / re-kit).** Scan a source plate, pick a kind: **split** (1 → several, remainder stays on source) ·
>   **merge** (several **same product+lot+expiry** → 1) · **repack** (1 → 1, new packaging, qty + genealogy unchanged) · **re-kit** (free outputs).
>   A live **balance** guard (outputs ≤ source for split; ≥2 for merge; every output needs qty/product for re-kit) gates Confirm. Commit **consumes
>   sources** (split leaves the remainder; others → `consumed`), **mints output LPNs** (repack/merge carry serials), logs a `repack` txn. Frozen-source guard.
> - **`pwa-inv-returns.html` (returns / put-back).** Tabs **To process** / **Processed**. Process an office-created open return **or** build a new one
>   one-pass (kind put-back / customer return; scan a product/LPN → qty / lot / reason). Per line choose a **disposition**: **Restock → bin** (scan/pick
>   a bin, **capacity + segregation** checked) · **Via Putaway** (→ staging, enters the directed-putaway queue) · **Quarantine / Damaged** (→ blocked plate).
>   Commit mints the LPN(s) at the right status+loc and logs a `return` txn — mirrors `erp-inv-returns` exactly.
> - **Anchors touched:** none in `assets/`. `pwa-home.html` (+ Transfers / Physical inventory / Repack / Returns tiles, all live, with live task-count
>   badges), `index.html` (sitemap: the 4 PWA inv-ops links). Specs re-synced: `docs/05_Inventory_Operations.md`.
> - **Verified:** inline-script syntax (node) for all 4 + the shared assets, **+ in-browser live commits, 0 console errors** — Transfer **TRF-8002**
>   shipped Lyon→Paris (LPN-00020 → in-transit) then **received** at Paris (→ available @ C-01, site reassigned, txns); Returns **RET-9002** restocked to
>   a bin (LPN-00123, capacity-checked) + a new **RET-9003** quarantined (LPN-00124 @ QUAR); Physical **PHY-7002** frozen (LOC-B0102 `isLocFrozen`→true) →
>   counted (empty bin + 50→49) → posted (LPN-00009 corrected 50→49, unfrozen); Repack **split** LPN-00016 300 → 100+100 + 100 remainder (RPK-7001) and
>   **merge** LPN-00051+00052 (120+120) → 240 (RPK-7002, sources consumed). Conservation holds on every commit; `transfer-ship/receive`, `count`, `repack`,
>   `return` txns logged.
> - **Coding-phase carry-overs (flagged):** **(a)** `pwa-inv-repack` enforces a **frozen-source guard** (and the PWA returns restock runs capacity+segregation);
>   the **ERP `erp-inv-repack` omits the frozen check** — align it in the build (the locked freeze rule should cover repack too). **(b)** PWA persists to
>   `sessionStorage`; the ERP reloads seed `data.js` per page — the server DB removes both caveats. `preview_screenshot` stayed renderer-stuck, so verified
>   via DOM snapshot + `preview_eval` + node syntax checks (per the method note).

## ✅ DONE (2026-06-19) — PWA Phase 4b: Ad-hoc dispatch (outbound “case 1”)

> The floor's controlled mirror of **blind receipt** — for the rare *“PC is off / customer truck waiting, no ERP order”* case.
> **One new PWA screen** (`pwa-so-dispatch.html`) + a small `data.js` anchor touch; reuses the proven pick scan-flow +
> `erp-so-fulfil` commit shape, so the floor can **originate** an outbound on purpose-built rails — **NOT** free-form blind shipping.
>
> - **`pwa-so-dispatch.html` (NEW).** A 3-step one-pass flow: **(1) governance gate** — mandatory **ship-to consignee**
>   (`consigneesFor`, client-scoped; blocks if the client has none) **+ manual reference + reason** (new master-data domain) **+ operator**
>   (audit stamp); **(2) build + pick** — scan a **product** (FEFO/FIFO auto-allocate, same `outboundCandidates` a normal pick uses) **or a
>   specific LPN** (grab-this-pallet), set qty, then the **identical scan-confirm pick sub-flow** as `pwa-so-pick` (scan bin → scan LPN/unit
>   → qty → **serials where tracked**); **(3) load & dispatch** — carrier + proof-of-load photo/note → commit. Commit **creates the
>   outbound order inline** (`nextOutId` → `OUT-…`, `adhoc:true`, `approval:'pending'`, reason + operator), **issues the stock**
>   (decrements LPNs, `dispatch` `logTxn`), writes a real **delivery note** (`DN-…`), and posts `dispatched` (ordered qty == shipped → complete
>   by construction; ad-hoc documents exactly what left, so no back-order math). **Mirrors every enforced guard** — frozen-scope &
>   expired plates excluded (`outboundCandidates`/explicit LPN-add checks), wrong-client/site refused, serial-on-issue required, no
>   double-allocation across lines (`freeForWork`). **Role-gated** (shown to all here, like Express Fulfil) + **flagged for back-office
>   approval** on the done screen. *(Non-customer removals — samples / QA / scrap — stay on the adjustment-out path, not here.)*
> - **Anchors touched (`data.js`):** new master-data reason domain **`dispatch`** (renders automatically in `erp-md-reasons.html` — it's
>   generic over `DB.reasonDomains`) + helper **`nextOutId()`**. No shell / CSS change. `pwa-home.html` (+ Ad-hoc dispatch tile, live) ·
>   `pwa-so-pick.html` (+ “No ERP order? ＋ Ad-hoc dispatch” discovery link on the To-pick list) · `index.html` (sitemap).
> - **Verified:** node suite (**22 assertions** — `dispatch` domain + `reasonsFor`, `nextOutId`=OUT-7105, consignees, full commit
>   round-trip: order appended with adhoc+approval+governance, stock issued + conservation, `dispatch` txn logged, `outboundComplete`,
>   consignee name resolves; all 3 touched inline scripts + shared assets parse) **+ in-browser, 0 console errors** — full happy path
>   (gate → add P-TCA 50 via FEFO → scan-confirm pick → carrier → commit) created **OUT-7105** (LPN-00111 200→150, **DN-7105-1**, ad-hoc
>   + approval-pending flag), the dispatch **persists cross-screen** into `pwa-so-pick` → Dispatched, and the guards fire (empty-gate,
>   wrong-client LPN-00021, expired LPN-00022 blocked, already-added).
> - **Coding-phase carry-overs (flagged, not built):** **(a)** ERP-side *surfacing* of the `approval:'pending'` ad-hoc flag (a review
>   queue / badge on `erp-so-orders` / `erp-so-note`) — the data is stamped; the ERP screen wasn't touched this pass. **(b)** Classic
>   `pwa-so-pick` + ERP dispatch don't `logTxn('dispatch')` on issue (pre-existing gap) — ad-hoc does; align them in the build.

## ✅ DONE (2026-06-19) — PWA Phase 4-core: Move + Count

> The rest of the core loop on the floor. **Two new PWA screens, NO anchor change** — `data.js`, the shells and
> `wireframe.css` were untouched; both screens reuse existing helpers + the proven putaway/pick scan-flow template.
>
> - **`pwa-inv-move.html` (Move — intra-site relocation).** Tabs **Move** (scan/pick an `available` plate for the current
>   client+site) / **Recent** (move history from `DB.moves`, newest first). Scan a plate → **quantity to move** (default whole) →
>   scan/pick a **destination bin** (the same ranked-bin block as Putaway: home → consolidate → category → open, with capacity
>   read-out + an *excluded* list). **Partial** splits a child LPN at the destination (genealogy + serials sliced) and leaves the
>   remainder on the source; **whole** relocates the plate (keeps its id + status). **Mirrors every enforced rule** — refuses a
>   **frozen** source *or* destination (`frozenTakeFor`), runs **capacity + client–area segregation** on the destination
>   (`binCapacityForAdd`/`binSegregationOk`), records a `MOV-…` in `DB.moves` + a `move` `logTxn`. Optional condition photo/note keyed
>   to the plate. Deep link `?lpn=` opens straight into the form. `expired` plates are flagged but still movable.
> - **`pwa-inv-count.html` (Count — cycle count on the floor).** Tabs **Count** / **Submitted**. Scan a **storage bin** → its
>   countable plates load (qty>0, this site, not in-transit) prefilled at system qty (lot shown only where the product tracks it);
>   key the physical count, tap **0** to mark a plate **missing**, or scan an item not listed to add it as **found** (mints a plate on
>   approval). A **blind-count** toggle hides system qty. One sheet **accumulates many locations**; **Submit** writes a single
>   `pending-approval` count sheet into `DB.counts` — the *exact* shape `erp-inv-count.html` reads (`locations[].lines[].{lpn,product,
>   lot,systemQty,countedQty,found?}`) — which the supervisor approves on the ERP to correct stock. Optional count evidence photo/note
>   keyed to the sheet id. Deep link `?loc=` starts a sheet on that bin.
> - **Anchors touched:** none in `assets/`. `pwa-home.html` (Move + Count added to the `LIVE` set → tiles tappable; Count tile badge
>   styled) and `index.html` (sitemap: the two PWA-inv links flipped from “not built”).
> - **Verified:** node suite (**22 assertions** — inline-script syntax for both screens + all shared assets parse; Move partial-split
>   conservation + child mint + `move` txn, whole-move id/qty preserved, freeze locks the bin; Count sheet shape + the ERP `applyApprove`
>   round-trip: short 150→148, missing 5→0, **found** mints a 24-unit plate, net −2+24) **+ in-browser both screens, 0 console errors**
>   (live partial move LPN-00008 240→140 + child `LPN-00123` @ A0102 · MOV-6002 in Recent; count LOC-A0102 → `CNT-9004`
>   pending-approval persisted, net +17; home shows both tiles live + the Count badge picks up the new sheet).
> - **Caveat (same as prior PWA phases):** the PWA sheet persists in `sessionStorage`; the **ERP** reloads seed `data.js` per page, so
>   the live `CNT-9004` is verified ERP-compatible via the node `applyApprove` simulation rather than a cross-page open (server DB removes
>   this in the build). `preview_screenshot` remained renderer-stuck — verified via DOM snapshot + `preview_eval` + node, per the method note.

## ✅ DONE (2026-06-18) — label parity + reprint, ERP & PWA

> **Locked rule satisfied:** *every operational action — including **printing AND re-printing** a label — is now doable in BOTH
> the PWA scanner AND the ERP (manual).* Both work items below are complete; full detail in `docs/BUILD_LOG.md`. Reused the
> existing `data.js` model + helpers + `barcode.js` — **no data-model change**.
>
> - **A — ERP parity.** `erp-gr-receipt.html` **live-mints** real plates (`nextLpnId`+`logTxn`, loads `barcode.js`): split
>   **per each** + per pack level (last plate carries the remainder, serials sliced, `Σqty=base`), posts `received` + Close-ASN-short,
>   done modal prints **per-plate** + **"Print all"** labels; **mixed-pallet build** (per-line "📦 Add to pallet" → close → one
>   `PLT-…` + manifest label; on-pallet lines read-only; Hold/Damaged blocked). `erp-pa-tasks.html` lists **mixed pallets** and
>   **decomposes** them (one child LPN per line via `decomposePalletLine`, reusing the slotting + capacity/segregation/frozen picker).
> - **B — reprint / re-access (both channels).** NEW **`erp-gr-labels.html`** (Goods Reception → Labels / Reprint) and NEW
>   **`pwa-gr-reprint.html`** (PWA Home → Labels): **#1** scan/pick an LPN or pallet → reprint, **#3** recency-ordered
>   **recent-receipts** recovery, **#2** reprint everything against an ASN. ERP previews the label inline; PWA hands off to `pwa-gr-lpn.html`.
> - **Anchors touched:** `erp-shell.js` (nav: + Labels / Reprint, relabel "Manual Receipt"→"Receive"), `pwa-home.html` (+ Reprint tile),
>   `index.html` (sitemap). Specs re-synced: `docs/02_Goods_Reception.md`, `docs/03_Putaway.md`.
> - **Verified:** node data-layer suite (26 assertions) + in-browser, **0 console errors** across all 5 screens (`LPN-00115` minted &
>   ASN closed; `PLT-00002` built & posted; `PLT-00001` decomposed → 3 child LPNs; ERP preview + PWA handoff render).
> - **Coding-phase carry-overs (flagged, not built):** audit every reprint (who/when/which — duplicate-floor-label risk); server DB
>   removes the ERP reset-on-load + PWA tab-close persistence caveats; migrate `erp-pa-tasks` off its local capacity impl to the shared
>   `binCapacityForAdd`/`binSegregationOk`.

## Anchors (shared files — change carefully; note it when you do)

`assets/`: **`wireframe.css`** (ERP+PWA theme — one file to re-skin) · **`data.js`** (single linked mock dataset;
IDs cross-reference across screens; all helpers; **`DB.pallets[]`** = transient mixed-pallet handling units; **+ edge-case layer** —
statuses `disposed`/`lost`, `ASN.state`, collections `DB.disposals/rtvs/grns/refusals`, reason domains dispose/refuse/rtv/receipt, ~20 helpers; see `EDGE_CASE_TRACKER.md`; **+ assignment layer** — optional `assignee` on work items/LPN/pallet, `DB.currentUserId`, `assigneeName`/`isMine`/`assignableUsers`/`assignee{Filter,Picker}Options`/`assigneeFilterPass`) · **`erp-shell.js`** (ERP topbar + iconed expandable sidebar —
**nav lives here only**, incl. Disposal + Return-to-vendor — + the global searchable-select engine) · **`pwa-shell.js`** (PWA phone frame + data-driven
client/site context + `pwaHydrate`/`PWA.save`/`resetDemo`; **+ `PWA.userId`/`mineOnly`/`setMine` + the `data-pwa-assignable` "My tasks" toggle**) · **`pwa-scan.js`** (scan engine: camera + manual +
pick-list) · **`vendor/zxing-library-0.18.6.min.js`** (camera fallback for Windows desktop) · **`barcode.js`**
(Code 128 + labels) · **`photos.js`** (`photoField` + `DB.attachments[]`) · **`notes.js`** (`noteField` + `DB.notes[]`).

> **Shell-injection gotcha (critical, recurring):** the shells rebuild `document.body` from the innerHTML of
> `#page-content` **only**. Anything outside it — modals, overlays, **and screen-local `<style>` blocks** — is
> discarded. ALL page markup *and* every screen-local `<style>` must live **inside** `#page-content`.

## Screen inventory & status

**ERP — all built & verified** (`index.html` = sitemap/launcher; `erp-dashboard.html` = landing):
| Section | Screens |
|---|---|
| Master Data | `clients` `consignees` `sites` `locations` `products` `partners` `categories` `reasons` `users` `clientmap` `uom` `import` |
| Goods Reception | `gr-asn` `gr-receipt` `gr-inspect` `gr-grn` `gr-labels` |
| Putaway | `pa-tasks` |
| Stock-Out | `so-orders` `so-alloc` `so-dispatch` `so-fulfil` `so-note` `so-rtv` *(return-to-vendor)* |
| Inventory Ops | `inv-status` `inv-adjust` `inv-transfer` `inv-count` `inv-physical` `inv-repack` `inv-returns` `inv-dispose` *(disposal/scrap)* |
| Reports | `rpt-soh` `rpt-txns` `rpt-expiry` `rpt-inbound` `rpt-outbound` `rpt-variance` `rpt-utilization` `rpt-trace` `rpt-stockcard` `rpt-statement` |

**PWA:**
- **Built:** `pwa-home` (live task hub) · `pwa-md-lookup-loc` · `pwa-md-lookup-prod` · `pwa-gr-receive` ·
  `pwa-gr-inspect` · `pwa-gr-lpn` · `pwa-pa-putaway` · `pwa-gr-reprint` (label reprint / recovery) ·
  `pwa-so-pick` (Pick / Dispatch — scan-driven pick → load → issue + delivery note) ·
  `pwa-so-dispatch` (Ad-hoc / emergency dispatch — inline order + governance + delivery note) ·
  `pwa-inv-move` (intra-site Move — scan plate → dest, partial split) · `pwa-inv-count` (cycle Count — scan loc → `pending-approval` sheet) ·
  `pwa-inv-transfer` (inter-site ship / receive) · `pwa-inv-physical` (freeze → count → post) ·
  `pwa-inv-repack` (split / merge / repack / re-kit) · `pwa-inv-returns` (re-enter + disposition) ·
  `pwa-so-rtv` (return-to-vendor — scan-confirm & ship) · `pwa-inv-dispose` (raise disposal / scrap — maker-checker). *(last two: edge-case pass.)*
- **PWA COMPLETE — nothing pending.**
- ⚠ The 18 built PWA screens are the **only** valid PWA references. Any other `pwa-*` file is an obsolete pre-ERP
  sketch — **rebuild, don't reference.**

## ▶ PWA build plan (the active roadmap)

The PWA is the final mockup phase. **Build phase-by-phase; each phase is implemented AND validated as a
client-presentable, step-by-step camera demo on dummy data (`http://localhost:8765`, 0 console errors) before the
next begins.**

**Locked decisions:** (1) **scanning = native `BarcodeDetector` camera + ZXing fallback + manual + pick-from-list**
(every field offers all modes; works in any browser; demo by printing a real Code-128/EAN label from the ERP and
scanning it). (2) **Live session mutations** — PWA flows commit to the session `DB` (persisted in `sessionStorage`
within the tab) so one operation flows across screens (receive→putaway→stock→pick). (3) **Core loop first.**

**Build rules (carry the ERP onto the floor):** same no-build constraint (plain HTML + shared `wireframe.css` +
vanilla JS; every file beside `assets/`; all markup + `<style>` inside `#page-content`). Reuse `data.js` helpers and
**mirror the enforced rules** (`docs/BLOCKING_RULES.md`): frozen-scope refusal, bin-write capacity + segregation,
serial-on-issue, expiry exclusion + FEFO/FIFO, conservation + `logTxn()` on every commit. Reuse `photoField()`,
`noteField()`, `barcode.js`; honour product tracking flags.

| Phase | Screen(s) | Status |
|---|---|---|
| 0 — Foundation | `pwa-scan.js`, `resolveScan`, `pwa-shell`, `pwa-home`, 2 lookups | ✅ built |
| 1 — Receipt | `pwa-gr-receive` (+ LPN split, mixed-pallet build), `pwa-gr-inspect`, `pwa-gr-lpn` | ✅ built · ⏳ user validating |
| 2 — Putaway | `pwa-pa-putaway` — single LPN (ranked bin + capacity/segregation/frozen guards) **and mixed-pallet decomposition** (scan pallet → place each line → child LPNs) | ✅ built · ⏳ user validating |
| 3 — Pick/Dispatch | `pwa-so-pick` (pick list → scan loc → scan product/LPN → qty → serials if tracked → short-pick → load/dispatch confirm w/ carrier + proof-of-load photo → issue + delivery note) | ✅ built · ⏳ user validating |
| 4-core — Move + Count | `pwa-inv-move` (scan LPN → scan dest → confirm; partial split; frozen/capacity/segregation guards) · `pwa-inv-count` (scan loc → confirm plates → counts, found via scan-unknown, missing = 0 → submit `pending-approval`) | ✅ built · ⏳ user validating |
| 4b — Ad-hoc dispatch | `pwa-so-dispatch` — controlled emergency outbound **case 1**: inline order (mandatory ship-to consignee + manual ref + reason + operator) · scan product (FEFO) **or** LPN · serial/lot/expiry + frozen/expired guards · → `dispatched` + delivery note · **role-gated** + **post-hoc back-office approval**. Reuses `erp-so-fulfil` commit shape. *(NOT free-form blind shipping; non-customer issues → adjustment-out.)* | ✅ built · ⏳ user validating |
| 5 — Inv-Ops remainder | `pwa-inv-transfer` (ship/receive) · `pwa-inv-physical` (freeze/count/post) · `pwa-inv-repack` (split/merge/repack/re-kit) · `pwa-inv-returns` (disposition) | ✅ built · ⏳ user validating |

## Phase 1–2 — test findings & enhancements (in progress with the user)

- **#1 (2026-06-18) — LPN split + batch print · DONE.** The PWA receive minted only **1 LPN per confirm**, while the
  ERP (`erp-gr-receipt`) splits a received line into **N plates** (per box/pallet). Added to `pwa-gr-receive.html`: a
  **"Split into LPNs"** control (offers each packaging level above base that yields ≥2 plates — mirrors the ERP),
  **multi-plate minting** (last plate carries the remainder; conservation `Σ qty = base`; lot/expiry/serial genealogy
  carried; serials sliced per plate), and a **"Print all N labels"** batch button + per-plate label links on the done
  screen (the screen now also loads `assets/barcode.js`). **No anchor change** (`data.js`/shells untouched). Verified:
  node unit test (conservation + serial slicing); in-browser Olive Oil split per Carton → 2 plates [72, 48]; Vaccine
  split per Blister-of-10 → 2 plates [10, 10] with serials VAXA-0001–0010 / 0011–0020 (20 unique, no overlap); 0 console errors.
- **#2 (2026-06-18) — per-each split + mixed-pallet LPN (the 3 labelling models) · DONE.** Covered the three real
  models the user raised: **(1 item → 1 label)** default; **(N items → N labels)** the split now also offers **per
  each** (base unit), not just pack levels; **(N items → 1 pallet label)** a new **mixed (aggregate) pallet** — one
  license plate holding many product/lot lines, built **post-hoc** (the user's refinement): an **"📦 Add to pallet"**
  button on every received line (ASN or blind) defers it onto a session pallet — a "pallet in progress" bar tracks it —
  then **"Close pallet & print label"** mints one `PLT-…` keyed to the ASN (posting received qty back to the ASN line at
  close) + one manifest label. A line already added **reopens read-only** (only "cancel & remove from pallet" — no
  double-receipt; ASN list badges it "on pallet"). At **Putaway** the pallet is scanned and **decomposes** — each line placed into a bin
  mints a persistent **child LPN** (genealogy carried), the pallet closing when empty (the *transient parent → persistent
  children* model). Built `pwa-pa-putaway.html` (NEW — also lands PWA roadmap **Phase 2**: single-LPN directed putaway,
  ranked bins + capacity/segregation/frozen guards). **Anchor change:** `data.js` (`DB.pallets[]` + `nextPalletId` /
  `palletById` / `palletsAtSite` / `palletTotals` / `palletOpenLines` / `decomposePalletLine`; `resolveScan` recognises
  `PLT-`; `PWA_DB_COLLECTIONS += 'pallets'`; seed pallet `PLT-00001`). Verified in-browser: pallet → 3 child LPNs
  (home/category/open bins, guards enforced); receive-built `PLT-00002` flows into putaway live; single-LPN putaway; 0 errors.
- **#3 (2026-06-18) — putaway split across bins (partial putaway) · DONE.** User test finding: a plate that doesn't fit one
  bin must be **split into two+ bins**. Was out-of-scope (v1 = one LPN → one bin). Added a **"quantity to place"** field on
  putaway in **both** channels (`erp-pa-tasks.html` + `pwa-pa-putaway.html`): less than the full qty places that amount and
  mints a **child LPN** for the remainder (source stays `to-putaway`), looping until fully stored; capacity/segregation/frozen
  are checked for the **entered** qty so a partial fits a smaller bin. Applies to single LPNs **and** mixed-pallet lines.
  **Anchor:** `data.js` — new shared `putawayPlace(lpnId, binId, qty, opts)` + `decomposePalletLine` gained an optional
  `opts.qty` (backward-compatible; omit = whole line). Also fixed the ERP pre-selection to fall back to a valid suggestion when
  the product's home is full for the remainder. Verified: node suite (13 assertions — conservation, serial slicing, partial/whole,
  pallet partial + backward-compat) + in-browser both channels (split 120 → 50 + 70 across bins; pallet line 24 → 10 + 14; 0 errors).
- **#4 (2026-06-18) — operator-chosen decompose order + Putaway history/Completed tab · DONE.** Two user test findings, **no
  anchor change** (pure screen UI; `data.js`/shells untouched — `decomposePalletLine` already took a `lineIdx`, the txn log already
  recorded every putaway). **(a) Pick the decomposition order:** mixed-pallet lines were forced into array order; now the operator
  **places lines in any order** — ERP manifest **chips are clickable** (qty shown, so you can grab the bulky items first), PWA
  manifest **rows are tappable**; a partly-placed line keeps its remainder for the next bin. **(b) Putaway no longer vanishes:**
  both screens now mirror the Receive section's **tabs** — **To put away** (open work) / **Completed** (history from
  `DB.txns type:'putaway'`: when · LPN · client · product · lot/expiry · qty · from → to · by · source), with **label reprint**
  (re-prints from the record, never re-mints — ERP inline `printLabels`, PWA hands off to `pwa-gr-lpn.html?lpn=`). Files:
  `erp-pa-tasks.html`, `pwa-pa-putaway.html`. Specs re-synced: `docs/03_Putaway.md`. Verified: node suite (13 assertions —
  out-of-order decompose 2→0→1 closes the pallet, putaway txns logged with site/to/qty, child LPN reprintable) + in-browser both
  channels (ERP `switchPalletLine(2)` jumps to line 3; Completed shows the seed putaway with reprint; PWA tab + tappable manifest; 0 console errors).
- **#5 (2026-06-18) — in-progress / partial-putaway visibility · DONE.** User finding: a part-done plate or pallet gave **no read-only context** on return — you couldn't see that 80 of 100 already went to a bin, or which pallet lines were placed where. Added a **friendly progress UX** in both channels: worklist **"partial" badge + "X of Y placed"** with a **Resume ›** action; a read-only **"Partially put away"** panel on the single-LPN detail (placed/original + progress bar + remaining + each placement: qty → bin · child LPN · when · by) and a **"Partially decomposed"** panel on the pallet view (placed lines → bin · child LPN · when), with the PWA pallet manifest also showing **placed ✓ → bin** inline and **"Z left · Y placed"** on a part-placed line. **Anchor change (`data.js`):** new helpers `putawaysFromSource(sourceId)` + `lpnPutawayProgress(lpnId)`, and **2 in-progress seed demos** (ACME/Lyon: `LPN-00120` 80/100 placed + child `LPN-00121`; `PLT-00003` 1-of-3 lines placed + child `LPN-00122`). Screens now **omit `ref:'putaway'`** on `putawayPlace` so a partial child's txn `ref` links to its source LPN (whole placement still `ref:'putaway'`). Files: `erp-pa-tasks.html`, `pwa-pa-putaway.html`, `data.js`. Specs re-synced: `docs/03_Putaway.md`. Verified: node suites (24 assertions total — seeds 80/20/100 + PLT 1-placed; live partial links child→source; whole keeps `ref:'putaway'`) + in-browser both channels (ERP Resume + both progress panels; PWA partial badges, progress card, manifest ✓→bin; live 60/120 partial links to source; **0 console errors**). *Note: PWA shows the new seeds only on fresh/Reset state — a pre-existing `sessionStorage` snapshot (hydrated over the seed) needs "Reset demo data" once.*
- **#7 (2026-06-18) — inspection reason codes wired to master data + damage-found-at-putaway reject · DONE.** Two
  linked user findings. **(a) Inspection reasons were hardcoded:** the reject-reason dropdown on both inspect screens
  (`erp-gr-inspect.html` / `pwa-gr-inspect.html`) used a baked-in list and ignored `erp-md-reasons.html` entirely. Now the
  dropdown is **driven by the chosen disposition**, pulled live from `reasonsFor('status', disposition)` (Quarantine / Hold /
  Damaged each show their own curated reasons; a still-valid pick survives a disposition switch) — matching the model already
  used by `inv-status`/`inv-adjust`/`inv-returns`. **No data change** (reused the existing `status` reason domain + helper).
  **(b) Damage found *during* putaway:** putaway was place-only — discovering e.g. 20 of 100 damaged forced you to store all
  100 as *available* then re-disposition via Adjustments (briefly sellable). Added a **"⚠ Report damage / reject"** control to
  the single-LPN putaway detail in **both** channels (`erp-pa-tasks.html` + `pwa-pa-putaway.html`): reject a sub-qty (or the
  whole plate) to a blocked disposition (quarantine/hold/damaged) with a **mandatory master-data reason** + photo; the rejected
  qty splits onto a child LPN at the QA/quarantine location (**excluded from availability**) and the **good remainder stays
  *to-putaway*** to keep flowing into a bin. **Anchor change (`data.js`):** new shared `putawayReject(lpnId, rejectQty, opts)`
  — mirrors `inspectionSplit` but for a `to-putaway` source; whole-reject keeps the plate id, a partial keeps the good qty on
  the plate + mints a child; conserves qty + carries lot/expiry/serial genealogy; logs a `type:'status'` txn (audit trail, **not**
  a `putaway` txn — never shows as a completed putaway). *(Stock Status, Section 05, deliberately skips `to-putaway` plates, so
  this is the in-flow path.)* Mixed-pallet-line reject deferred. Specs re-synced: `docs/02_Goods_Reception.md`, `docs/03_Putaway.md`.
  **Verified:** node suite (16 assertions — 120→100+20 split conservation, quarantine routing, genealogy, status-txn, non-to-putaway
  + reject-0 guards, reject-all flips id) + in-browser **both channels** (ERP `LPN-00012` reject 20 → damaged child `LPN-00123`
  @ QA-01, 100 remain to put away; PWA same → quarantine child; reason lists track disposition; **0 console errors** across all 4 screens).
- **#6 (2026-06-18) — partial accept / reject on inspection · DONE.** User finding: inspection was all-or-nothing (Pass **or** Fail the whole plate). Now the decision is **quantity-based** in both channels — the inspector sets the **accepted quantity** (default = whole plate; **Accept all / Reject all** shortcuts). Accepted units release to **to-putaway** (enter the putaway queue → available once stored); any **rejected** shortfall splits onto a **new child LPN** at a blocked disposition (**quarantine / hold / damaged**) and **never enters available stock** (e.g. 100 → accept 90 → putaway, reject 10 → quarantine). **Anchor (`data.js`):** new shared `inspectionSplit(lpnId, acceptQty, opts)` — whole-accept/whole-reject keep the plate id; a partial keeps the accepted qty on the original plate and mints a child for the rejected qty (conserves qty, carries lot/expiry/serial genealogy, writes `inspect` txns). The **ERP inspect screen now mutates `DB`** like the PWA did (it previously only recorded a local decision); its tabs (Pending/Passed/Failed/All) derive from live status + `inspect` txns, and a decided plate opens **read-only**. Added `inspect` to `erp-rpt-txns` type list/category. Files: `erp-gr-inspect.html`, `pwa-gr-inspect.html`, `assets/data.js`, `erp-rpt-txns.html`. Specs re-synced: `docs/02_Goods_Reception.md`. Verified: node suite (9 assertions — 60→50/10 split conservation + quarantine routing + genealogy ref; re-inspect guard; accept-all keeps id) + in-browser both channels (ERP 60→50/10 split, Passed/Failed tabs + read-only decided view; PWA 60→45/15 split persists → accepted **45 appears in Putaway**, rejected **excluded**; **0 console errors**). *Same ERP session-reset caveat as putaway: the accept→putaway hand-off persists across screens in the PWA (sessionStorage), but the ERP reloads seed `data.js` per page (server DB removes this in the build).*

## Tracking test data (active reference for the current test phase)

The flag deciding lot/expiry/serial lives on the **product** and drives show/hide of those fields/columns on every
screen (lists show muted `n/a` for untracked; detail/forms omit). **Default: lot + expiry ON, serial OFF** (serials
are scanned off the unit, not minted — enable serial only for serialised goods; **expiry ⇒ lot**). Four labelled
products under **ACME / Lyon** (the default PWA context) exercise the combinations, each with a full ASN → putaway →
stock → outbound chain and a `testCase` grid badge:

| Case | Product | Tracking | Chain (ASN · to-putaway · avail · order) |
|---|---|---|---|
| A (~90% real-world) | `P-TCA` | none | ASN-3101 · LPN-00101 · LPN-00111 · OUT-7101 |
| B | `P-TCB` | lot | ASN-3102 · LPN-00102 · LPN-00112 · OUT-7102 |
| C | `P-TCC` | lot + expiry | ASN-3103 · LPN-00103 · LPN-00113 · OUT-7103 |
| D | `P-TCD` | lot + expiry + serial | ASN-3104 · LPN-00104 · LPN-00114 · OUT-7104 |

Available stock sits in 2 generous TEST bins (`LOC-TC01/02`, Area A) so it never collides with the capacity demos.
Helpers: `prodTrack`/`tracksLot`/`tracksExpiry`/`tracksSerial`/`trackingSummary`/`testCaseOf`/`testCaseNote`/`docCaseNote`.
"Today" is mocked at **2026-06-15** for expiry warnings.

## Known limitations carried into the coding phase (flagged, not fixed)

- **Per-client scope** is mock-wide (reports/lists default to all-clients; `erp-md-clientmap` defines the mapping) —
  **enforce `User.clients` server-side** in the build.
- **Export** (Excel/CSV) is stubbed across reports — only browser **Print** works.
- ERP inventory mutations are **session-only** (reset on reload); PWA flows persist to `sessionStorage` within a tab.
- Putaway still uses a local capacity impl — should call the shared `binCapacityForAdd`/`binSegregationOk` in the build.
- **Operations dashboard** tiles are static — wire to live `DB` rollups.

## Open theme to-dos (optional polish)

- Replace the eyeballed blue with the exact brand hex (one CSS variable in `wireframe.css`).
- Swap placeholder icons for the client's set if available.
- Relabel the `index.html` sitemap entry "Manual Receipt" → "Receive" for consistency.

---
*Verification method note: functional checks have been via DOM snapshot + `preview_eval` (every flow exercised) plus
a deterministic `node` dataset-integrity check. The preview server tends to serve a stale cached `data.js`/`erp-shell.js`
within a session — the on-disk files are authoritative; verify data-layer changes with `node` or a cache-busted fetch,
and a fresh `file://` open / new browser picks up the latest. `preview_screenshot` was stuck renderer-side in recent
sessions — re-attempt if visual proof is needed.*
