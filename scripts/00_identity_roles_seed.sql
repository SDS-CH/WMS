/* ============================================================================
   WMS (3PL) — IDENTITY ROLES SEED  (Role Families + Roles for the WMS module)
   ----------------------------------------------------------------------------
   Target engine  : Microsoft SQL Server 2014  (hard constraint)
   ⚠ TARGET DB    : the HOST IDENTITY database (the AU / AuthContext DB — the one
                    holding [dbo].[Users], [dbo].[Roles], [dbo].[RoleFamilies],
                    [dbo].[ERPModules]) — **NOT** the per-agency DMS_xx database.
                    Roles are global: seed ONCE per environment, not per agency.

   WHY THIS FILE EXISTS (the privileges convention)
   ------------------------------------------------
   Every WMS card with a user-facing surface carries a "### 🔐 Privileges"
   section (Role Family + Role Name). Backend enforcement is
   [Authorize(Roles = "<Role Name>")] on the mutating endpoints; the frontend
   hides menus/buttons via data.roles + SdsAccessChecker. Those roles must exist
   in the identity DB — THIS file creates them.

   ▶ CONVENTION FOR ALL FUTURE CARDS: a card that introduces a NEW role in its
     Privileges section MUST, in the same pass, append that role here as a
     guarded insert (and its family, if new). This file is the single seeding
     source for WMS roles; the section trackers' Decisions hold the registry.

   Structure in the identity DB (AuthContext):
     [ERPModules]    Id · Module ('WMS') · …            ← must already exist
     [RoleFamilies]  Id · Name · Description · ModuleId ← FK ERPModules
     [Roles]         Id · Name · Description · FamilyId ← FK RoleFamilies
     [UserRoles]     UserId · RoleId                    ← NOT seeded here —
                     assignment is done by an admin via the host Users & Roles
                     screen (or GroupRoles for group-based assignment).
   Role/RoleFamily translators (fr-FR labels) are optional and not seeded.

   ⚠ ROLE-NAME COLLISIONS: JWT role claims are FLAT strings — [Authorize(Roles=
   "Manage Products")] cannot tell which family a role came from. The script
   first SELECTs any same-named roles that already exist under OTHER families;
   if that result is non-empty, review before assigning (or rename the WMS role
   here AND in the cards, e.g. prefix "WMS …").

   Idempotent: every INSERT is guarded by NOT EXISTS; safe to re-run anywhere.
   If the 'WMS' module row is missing, the script raises an error and seeds
   NOTHING (register the WMS module in the host admin first, then re-run).

   HOW TO RUN
   ----------
   USE [<your identity DB>];   -- e.g. the AU/identity database of the environment
   -- then execute this file. Re-run safe.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---- 0. Resolve the WMS module (required by RoleFamilies.ModuleId) ---------- */
DECLARE @moduleId INT = (SELECT TOP 1 Id FROM dbo.ERPModules WHERE Module = N'WMS');
IF @moduleId IS NULL
    RAISERROR(N'ERPModules has no ''WMS'' row — register the WMS module in the host admin first, then re-run this script. NOTHING was seeded.', 16, 1);

/* ---- 1. Collision check (review if this returns rows) ----------------------
   Same-named roles under OTHER families already satisfy [Authorize(Roles=...)]
   for the WMS endpoints. If rows appear: either accept the overlap knowingly,
   or rename the WMS role (here AND in the cards). */
SELECT r.Id, r.Name AS CollidingRole, ISNULL(f.Name, N'(no family)') AS ExistingFamily
FROM dbo.Roles r
LEFT JOIN dbo.RoleFamilies f ON f.Id = r.FamilyId
WHERE r.Name IN (N'Manage Sites', N'Manage Partners', N'Manage Clients',
                 N'Manage UoM & Packaging', N'Manage Categories', N'Manage Consignees',
                 N'Manage Reason Codes', N'Manage Products', N'Manage Locations',
                 N'Manage WMS Users', N'ASN Manager', N'Refuse Delivery', N'Receiving Operator',
                 N'Quality Inspector', N'Putaway Operator', N'Outbound Orders Manager',
                 N'Allocation Operator', N'Dispatch Operator', N'Express Fulfilment',
                 N'RTV Operator', N'Stock Status Manager', N'Stock Adjuster', N'Adjustment Approver',
                 N'Move Operator', N'Transfer Operator', N'Count Operator', N'Count Approver',
                 N'Physical Inventory Manager', N'Repack Operator', N'Returns Operator',
                 N'Disposal Operator', N'Disposal Approver')
  AND (f.Name IS NULL OR f.Name NOT IN (N'WMS - Master Data', N'WMS - Goods Reception', N'WMS - Putaway', N'WMS - Stock Out', N'WMS - Inventory Ops'));

/* ---- 2. Role Families ------------------------------------------------------- */
DECLARE @fam TABLE (Name NVARCHAR(100), Description NVARCHAR(300));
INSERT INTO @fam (Name, Description) VALUES
    (N'WMS - Master Data',      N'WMS warehouse master data administration (sites, partners, clients, products, locations, …)'),
    (N'WMS - Goods Reception',  N'WMS inbound flow (ASN, receiving, inspection, GRN, refusals)'),
    (N'WMS - Putaway',          N'WMS storage flow (directed slotting, placement/splits, pallet decomposition, damage rejects, overflow park)'),
    (N'WMS - Stock Out',        N'WMS outbound flow (outbound orders, allocation, pick/dispatch, express fulfil, delivery notes, RTV)'),
    (N'WMS - Inventory Ops',    N'WMS in-warehouse stock operations (status management, moves, transfers, counts, physical inventory, adjustments, repack, returns, disposal)');

INSERT INTO dbo.RoleFamilies (Name, Description, ModuleId)
SELECT s.Name, s.Description, @moduleId
FROM @fam s
WHERE @moduleId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.RoleFamilies f WHERE f.Name = s.Name);

/* ---- 3. Roles (source of truth = the cards' 🔐 Privileges sections) ---------
   ▶ Future cards APPEND their new roles to this VALUES list (same guard). */
DECLARE @rol TABLE (Family NVARCHAR(100), Name NVARCHAR(100), Description NVARCHAR(400));
INSERT INTO @rol (Family, Name, Description) VALUES
    -- WMS - Master Data (one coarse Manage role per story; cards MD-*)
    (N'WMS - Master Data', N'Manage Sites',           N'Create/edit/delete sites, addressing levels and storage areas (Master Data › Site; also covers the Storage-areas section).'),
    (N'WMS - Master Data', N'Manage Partners',        N'Create/edit/delete suppliers and carriers (Master Data › Suppliers & Carriers, incl. the pilot carrier endpoints).'),
    (N'WMS - Master Data', N'Manage Clients',         N'Create/edit/delete clients and their operating sites (Master Data › Clients).'),
    (N'WMS - Master Data', N'Manage UoM & Packaging', N'Create/edit/delete units of measure and packaging hierarchies (Master Data › UoM & Packaging).'),
    (N'WMS - Master Data', N'Manage Categories',      N'Create/edit/delete categories and sub-categories (Master Data › Categories).'),
    (N'WMS - Master Data', N'Manage Consignees',      N'Create/edit/delete consignees (Master Data › Consignees).'),
    (N'WMS - Master Data', N'Manage Reason Codes',    N'Add/rename/remove reason codes (Master Data › Reason Codes; reads stay open — dropdown sources for all operational users).'),
    (N'WMS - Master Data', N'Manage Products',        N'Create/edit/delete products, preferred storage, product packaging and barcodes (Master Data › Products).'),
    (N'WMS - Master Data', N'Manage Locations',       N'Create/edit/delete storage locations, bulk area assignment, label printing (Master Data › Locations).'),
    (N'WMS - Master Data', N'Manage WMS Users',       N'SENSITIVE — administer WMS user profiles and their site/client scopes (Master Data › Users & Roles). Assign narrowly.'),
    -- WMS - Goods Reception (cards GR-*)
    (N'WMS - Goods Reception', N'ASN Manager',        N'Create/edit/delete and VOID inbound orders / ASNs (cards GR-ASN-CRUD/VOID/EDITOR; the read-only ASN worklist needs no role).'),
    (N'WMS - Goods Reception', N'Refuse Delivery',    N'Refuse a delivery at the warehouse door — irreversible, no stock minted (cards GR-REFUSAL-*; typically door supervisors).'),
    (N'WMS - Goods Reception', N'Receiving Operator', N'Run the Receive flow — draft receipts, traceability capture, confirm (mint LPNs), mixed pallets, inline product quick-create (cards 09–17; quick-create is LIVE only when the user also holds Manage Products).'),
    (N'WMS - Goods Reception', N'Quality Inspector',  N'Formal QC decision on to-inspect plates — accept/reject/partial split with dispositions (quarantine/hold/damaged) and mandatory reject reasons (cards 19/21). Kept distinct from Receiving Operator for segregation of duties.'),
    -- WMS - Putaway (cards PUT-*)
    (N'WMS - Putaway', N'Putaway Operator', N'Run the storage flow — place/split to-putaway plates (stock goes available), park to overflow, decompose mixed pallets, damage-found rejects (cards PUT 03/04/05 endpoints; screens 07/08/09).'),
    -- WMS - Stock Out (cards SO-*)
    (N'WMS - Stock Out', N'Outbound Orders Manager', N'Create/edit/delete outbound orders and their lines, release allocations, cancel orders (reason-coded) and cancel/restore lines (cards SO-ORDERS 01/02 endpoints; screens 04/05). The orders worklist read needs no role.'),
    (N'WMS - Stock Out', N'Allocation Operator',     N'Confirm FEFO/FIFO stock allocations — reserve plates against outbound orders, incl. manual overrides and short allocations (card SO 07 endpoint; screen 09 Confirm). Candidate reads + the allocation worklist need no role. Kept distinct from Outbound Orders Manager (classic-path sites run allocation as its own team).'),
    (N'WMS - Stock Out', N'Dispatch Operator',       N'Run the pick & issue flow — save picks + serials, report damage-at-pick / stock-not-found, and CONFIRM DISPATCH (issue stock out, mint delivery notes; cards SO 10/11/12 endpoints, screen 14 buttons). The pick worklist + pick-detail reads need no role. The single most consequential WMS right — stock leaves the building.'),
    (N'WMS - Stock Out', N'Express Fulfilment',      N'Run the ONE-PASS outbound flow — reserve, pick and dispatch in a single Confirm fulfilment, incl. express damage/not-found (card SO 15 endpoints; screen 16 — the whole menu entry is gated). Mandated as a SEPARATE right (spec CC-10): holding Allocation Operator + Dispatch Operator does NOT include it. Grant narrowly — one unreviewed click issues stock.'),
    (N'WMS - Stock Out', N'RTV Operator',            N'Run the Return-to-Vendor flow — raise RTVs (typed supplier/client destination, eligible available-or-blocked plates), cancel them with a reason, and SHIP & ISSUE the stock out (cards SO 17/18 endpoints; screens 20/21 buttons). The RTV register read needs no role. Distinct from Dispatch Operator — returning stock to a vendor is a different accountability than shipping a customer order.'),
    -- WMS - Inventory Ops (cards INV-*)
    (N'WMS - Inventory Ops', N'Stock Status Manager', N'Block/release stock plates — bulk status changes (available ↔ quarantine/hold/damaged/expired, reason-coded; hold release needs the client auth ref) and the expired sweep, incl. releasing live order reservations when blocking reserved plates (card INV 01 endpoints; screen 02 bulk bar + Flag-expired). The stock-status list/history reads need no role. Consequential right — a release makes blocked goods shippable again.'),
    (N'WMS - Inventory Ops', N'Stock Adjuster',       N'Raise stock-correction requests — quantity adjustments (damage/loss/found) and attribute corrections (wrong lot/expiry/serial/product/owning client), reason-coded, landing as PENDING for approval; raising never touches stock (card INV 03 raise endpoint; screen 05 New buttons). The register reads need no role. Kept distinct from Adjustment Approver — CC-07 separation of duties.'),
    (N'WMS - Inventory Ops', N'Adjustment Approver',  N'Decide pending stock-correction requests — APPROVE & POST (applies the change to the plate + audit ledger, after freeze/stale/segregation re-validation) or reject. The raiser can NEVER approve their own request (F13, enforced per user on top of this role). Grant to supervisors — this right changes client inventory (cards INV 04 endpoints; screen 05 decide buttons).'),
    (N'WMS - Inventory Ops', N'Move Operator',        N'Relocate stock WITHIN a site — immediate guarded moves (freeze/segregation/capacity), whole plate or partial split (card INV 06 confirm endpoint; screen 09 New-move form). Routine housekeeping right; the move register read needs no role.'),
    (N'WMS - Inventory Ops', N'Transfer Operator',    N'Run the inter-site transfer flow — create/cancel drafts, SHIP (stock leaves the origin; releases open-order reservations after confirm), conditioned RECEIVE (good/damaged→quarantine/short→loss) and reasoned in-transit WRITE-OFFS (cards INV 07/08 endpoints; screens 09/10 buttons). Heavier accountability than Move Operator — grant deliberately; the transfer register read needs no role.'),
    (N'WMS - Inventory Ops', N'Count Operator',       N'Create and submit cycle-count sheets — multi-location worksheets, blind counts, found/missing lines, landing as PENDING-APPROVAL; submitting never touches stock (card INV 11 submit endpoint; screen 13 New-count builder). The count register reads need no role. The maker half of the CC-07 pair with Count Approver.'),
    (N'WMS - Inventory Ops', N'Count Approver',       N'Decide pending count sheets — APPROVE & CORRECT (posts counted quantities, mints found plates, zeroes missing ones — after frozen-scope + stale-sheet re-validation) or reject for recount, singly or BULK within the variance tolerance (largest plate-level Δ gate). The counter can NEVER approve their own sheet (F13, per user on top of this role). Grant to supervisors — this right corrects client inventory (cards INV 12 endpoints; screen 13 bulk bar + decide buttons).'),
    (N'WMS - Inventory Ops', N'Physical Inventory Manager', N'Run full stock-takes end to end — create scoped takes (site/Area, no-overlap), FREEZE the scope (halts putaway/moves/transfers/allocation across it — the CC-01 guard), count/recount every bin, POST corrections & unfreeze (corrects plates wholesale, mints found, zeroes missing) or abandon (cards INV 14/15 endpoints; screen 16 buttons). Grant narrowly — one click halts a warehouse. The stock-take register reads need no role.'),
    (N'WMS - Inventory Ops', N'Repack Operator',      N'Confirm stock-conversion jobs — split / merge / repack / re-kit: consume source plates, mint genealogy-carrying outputs, incl. releasing open-order reservations on consumed sources after confirm (card INV 17 confirm endpoint; screen 18 builder). Self-balancing operation, no approval step; the job register read needs no role.'),
    (N'WMS - Inventory Ops', N'Returns Operator',     N'Run the stock re-entry flow — register put-backs / customer returns (flag-driven lot/expiry/serial capture) and PROCESS them line-by-line with dispositions (restock-direct under the shared bin guards / via-Putaway / quarantine / damaged), minting the plates (cards INV 19/20 endpoints; screen 21 buttons). The returns register reads need no role.'),
    (N'WMS - Inventory Ops', N'Disposal Operator',    N'Raise disposal requests — scrap / destroy / write-off of BLOCKED-or-EXPIRED plates only, method-scoped reasons, landing as PENDING; raising never touches stock (card INV 22 raise endpoint; screen 24 form + the Stock Status Dispose hand-offs). The maker half of the CC-07 pair with Disposal Approver.'),
    (N'WMS - Inventory Ops', N'Disposal Approver',    N'Decide pending disposals — APPROVE & POST (decrements the plate after freeze/released/stale re-validation; TERMINAL ''disposed'' at zero; signed ''dispose'' ledger row) or reject. The raiser can NEVER approve their own request (F13, per user on top of this role). Grant to supervisors only — this right destroys client inventory (card INV 23 endpoints; screen 24 decide buttons).');

INSERT INTO dbo.Roles (Name, Description, FamilyId)
SELECT s.Name, s.Description, f.Id
FROM @rol s
JOIN dbo.RoleFamilies f ON f.Name = s.Family
WHERE NOT EXISTS (SELECT 1 FROM dbo.Roles r WHERE r.Name = s.Name AND r.FamilyId = f.Id);

/* ---- 4. Summary — what the identity DB now holds for WMS -------------------- */
SELECT f.Name AS RoleFamily, r.Name AS RoleName, r.Id AS RoleId
FROM dbo.RoleFamilies f
JOIN dbo.Roles r ON r.FamilyId = f.Id
WHERE f.Name LIKE N'WMS - %'
ORDER BY f.Name, r.Name;
GO

/* ============================================================================
   END — seeded (idempotent): 5 role families · 32 roles.
   NOT seeded: UserRoles/GroupRoles assignments (host admin) · fr-FR translators.
   Applied additions (newest last — append future cards' roles above the summary):
     2026-07-03  initial registry — 10 Master Data roles + ASN Manager + Refuse Delivery
     2026-07-03  Receiving Operator (Receive-page cards 09–17)
     2026-07-03  Quality Inspector (Inspect-page cards 18–21)
     2026-07-04  family WMS - Putaway + Putaway Operator (Putaway cards 01–09)
     2026-07-05  family WMS - Stock Out + Outbound Orders Manager (Orders cards SO 01–05)
     2026-07-05  Allocation Operator (Allocation cards SO 06–09)
     2026-07-05  Dispatch Operator (Pick/Dispatch cards SO 10–14)
     2026-07-05  Express Fulfilment (Express Fulfil cards SO 15–16 — separate right, CC-10)
     2026-07-05  RTV Operator (RTV cards SO 17–21)
     2026-07-06  family WMS - Inventory Ops + Stock Status Manager (Stock Status cards INV 01–02)
     2026-07-06  Stock Adjuster + Adjustment Approver (Adjustments & Corrections cards INV 03–05 — maker-checker pair, CC-07)
     2026-07-06  Move Operator + Transfer Operator (Moves & Transfers cards INV 06–10)
     2026-07-06  Count Operator + Count Approver (Cycle Count cards INV 11–13 — maker-checker pair, CC-07)
     2026-07-06  Physical Inventory Manager (Physical Inventory cards INV 14–16 — the freeze workflow, CC-01)
     2026-07-06  Repack Operator (Repack & Re-kit cards INV 17–18)
     2026-07-06  Returns Operator (Returns & Put-back cards INV 19–21)
     2026-07-06  Disposal Operator + Disposal Approver (Disposal & Scrap cards INV 22–24 — maker-checker pair, CC-07)
   ============================================================================ */
