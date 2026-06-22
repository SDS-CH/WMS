# Cross-Cutting Concerns Registry

> **This is the mechanism that prevents the "discovered too late" problem** (e.g. building Receiving →
> Putaway → Stock-Out, then discovering all three must be reopened to support Freeze Stock).
> Seeded from `../../docs/BLOCKING_RULES.md` and `../../docs/DATA_MODEL.md`. **Authoritative for what is
> shared.** A concern listed here is built **once** as a Phase-0 service and **consumed** by every process.

---

## The rule (enforced via the build cards)

1. Every concern below is owned by a **Phase-0 service** with a **frozen interface contract**.
2. **No consumer phase starts until the services it consumes are merged and their interfaces frozen** (gated by `PHASE_DEPENDENCY_MATRIX.md`).
3. **Every sub-phase build card MUST declare `consumes: [concern-ids]`** in its metadata header, and its *Acceptance criteria* must include the relevant guard tests from `BLOCKING_RULES.md`.
4. A concern's behaviour is **server-side and authoritative** — the UI mirrors it for UX, but the API re-checks at commit (never trust the client).

**Why this works:** because Receiving/Putaway/Move/Allocation all call `freeze.isLocationFrozen()` from day one, the *Freeze Stock workflow* (which only flips the freeze flag and runs the count) can be delivered late in Phase 6 and **changes nothing** in the earlier phases. The dependency was paid for up front, in Phase 0, as a one-line call each.

---

## The registry

| ID | Concern | Phase-0 service (proposed) | Mock helper (interface sketch) | Consumed by | Production-gap ref (DATA_MODEL) |
|---|---|---|---|---|---|
| **CC-01** | Stock blocking / **freeze** | `IFreezeService` | `isLocFrozen`, `frozenTakeFor` | Putaway, Move, Transfer-ship, Allocation, Pick, Dispatch | Physical Inventory |
| **CC-02** | Bin **capacity + segregation** | `ICapacityService` | `binCapacityForAdd`, `binSegregationOk`, `binLoad` | Putaway, Returns-restock, Move, Transfer-receive | — |
| **CC-03** | **Audit / transaction log** (every mutation writes one) | `IStockLedgerService.LogTxn` | `logTxn`, `nowStamp` | **every** mutating action, all phases | Txn history (make strictly append-only) |
| **CC-04** | **Conservation of quantity + genealogy carry** | enforced in `IStockService` split/move ops | the split/mint/decrement pattern | Receiving, Putaway, Inv-Ops, Stock-Out | Serials = explicit lists |
| **CC-05** | **Tracking-flag** field visibility (lot/expiry/serial per product) | `track` on Product → DTO flags | `tracksLot/Expiry/Serial`, `trackingSummary` | every screen with lot/expiry/serial | — |
| **CC-06** | **FEFO/FIFO allocation + reservation-aware availability** | `IAllocationService` | `fefoAllocate`, `outboundCandidates`, `lpnAvail`, `outReserved` | Stock-Out, ad-hoc dispatch | Persist partial-LPN reservations |
| **CC-07** | **Reason codes + approval / maker-checker** | `IReasonService` + approval gate | `reasonsFor`, `sameActor` | Status change, adjust, correct, count, physical, disposal, RTV | Reasons keyed by stable code |
| **CC-08** | **Multi-tenant scoping** (client + site) | `ITenantScopeService` (filter + assert) | `User.clients/sites` (flagged `[mock]`) | **every** read and write | Model scope as id lists (decision #2) |
| **CC-09** | **Work-item assignment** ("My tasks" / dispatch / self-claim) | `assignee` field + `IAssignmentService` | `assigneeFilterPass`, `isMine`, `assignableUsers` | all floor queues (10 ERP / 11 PWA surfaces) | — |
| **CC-10** | **Role / permission gating** | host roles/claims (see HOST_MAP §A2) | flagged carry-overs | Express fulfil, ad-hoc dispatch, PWA self-claim | role model is host-side |
| **CC-11** | **Validate-at-commit against live stock** | a discipline enforced in every service handler | "re-read + re-check inside confirm" | all mutations | — |
| **CC-12** | **Deep-link / pre-fill never bypasses guards** | pre-fill validated server-side | "ineligible target → unfilled form" | all deep-linked screens | — |

---

## Per-concern contracts (the big ones)

### CC-01 Freeze — `IFreezeService`
- `bool IsLocationFrozen(locId)` · `PhysicalInventory FrozenTakeFor(locId)` (the blocking `PHY-…` or null).
- **Only the `frozen` state blocks** (`open`/`closed` don't). Consumers must **name the blocking take** in the error.
- **Consumers (must call before placing/removing/allocating stock at a location):** Putaway, Move (source *and* destination), Transfer-ship, Allocation, Pick, Dispatch.
- **Acceptance (every consumer card inherits):** committing into/out of a frozen-scope location is **refused** with the `PHY-…` named; `open`/`closed` scopes pass.

### CC-02 Capacity + segregation — `ICapacityService`
- `CapacityResult CheckForAdd(binId, qty, productId)` → `{ ok, fails[], after }` · `bool SegregationOk(binId, clientId)`.
- Capacity = weight/units/LPN-slots vs the bin max (unset = ∞). Segregation honours `settings.clientAreaSegregation`.
- 📌 **DECISION (client-confirmed): client–area segregation is REQUIRED for this client** — different clients' stock must **not** share a location. This deployment runs `clientAreaSegregation = ON` with a **dedicated Storage Area per client** (`Area.owningClient`); the greenfield default stays OFF. The build MUST deliver **(a)** the system toggle + per-area `owningClient` config UI (Phase 1 · P01-S02) and **(b)** server-side `SegregationOk` enforcement on every bin-write. Mock seed: Areas D/E/F = Technip/Schlumberger/Yinson, B = Globex; Area A + Soyo Area C shared.
- **Consumers:** Putaway directed-slotting, Returns direct-restock, Move destination, Transfer-receive destination. **Single source of truth — no per-screen reimplementation** (the mock flagged `erp-pa-tasks` for using a local impl; the build must not).

### CC-03 Audit ledger — `IStockLedgerService`
- `void LogTxn(type, lpn, qty, from, to, site, user, ref, reason, note)`. **An action that mutates stock and writes no txn row is a bug.**
- `type ∈ {receive, putaway, move, transfer-ship, transfer-receive, adjust, correct, count, status, repack, return, dispatch, attach, attach-remove}`.
- SQL 2014: append-only table, hand-rolled (no system-versioned temporal tables) — see `COMMON_DATABASE_RULES`.

### CC-06 Allocation — `IAllocationService`
- `Allocation[] Allocate(line, order)` (FEFO if product tracks expiry, else FIFO; honours `fullStockOut`); excludes **past-expiry** and **frozen-scope** stock; reservation-aware (`lpnAvail` nets other live orders).
- Serial-tracked lines must capture serials **before** dispatch — enforced on classic Pick/Dispatch **and** Express Fulfil.

### CC-08 Tenant scoping — `ITenantScopeService`
- Every WMS query is filtered by the caller's permitted **clients + sites**; every write asserts the target is in scope. **Server-side, not just UI.** This is the production gap the mock flagged ("enforce `User.clients` server-side"). Implementation is **decision #2** in `HOST_INTEGRATION_MAP.md`.

---

## Worked example — how Freeze stays a non-event

| Phase | What it builds | Freeze touch-point | Cost of the dependency |
|---|---|---|---|
| 0 | `IFreezeService` (interface + impl: reads `frozen` takes) | — | built once |
| 3 Putaway | place LPN into bin | `if (freeze.IsLocationFrozen(binId)) block;` | **1 call** |
| 6 Move | relocate LPN | check source **and** dest frozen | **2 calls** |
| 5 Allocation | reserve stock | exclude frozen-scope candidates | **1 filter** |
| 6 Physical Inventory | the freeze **workflow** (flip flag, count, post) | *sets* the state the others already respect | self-contained |

➡ Delivering the Physical Inventory workflow last requires **zero rework** in Putaway/Move/Allocation, because they were built against `IFreezeService` from the start. **That is the entire point of this registry.**

---

*Source of the invariants: `../../docs/BLOCKING_RULES.md` (do not restate rules here — link to it). Service names are proposals for Phase 0 to finalize and freeze.*
