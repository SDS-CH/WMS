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
                 N'Quality Inspector')
  AND (f.Name IS NULL OR f.Name NOT IN (N'WMS - Master Data', N'WMS - Goods Reception'));

/* ---- 2. Role Families ------------------------------------------------------- */
DECLARE @fam TABLE (Name NVARCHAR(100), Description NVARCHAR(300));
INSERT INTO @fam (Name, Description) VALUES
    (N'WMS - Master Data',      N'WMS warehouse master data administration (sites, partners, clients, products, locations, …)'),
    (N'WMS - Goods Reception',  N'WMS inbound flow (ASN, receiving, inspection, GRN, refusals)');

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
    (N'WMS - Goods Reception', N'Quality Inspector',  N'Formal QC decision on to-inspect plates — accept/reject/partial split with dispositions (quarantine/hold/damaged) and mandatory reject reasons (cards 19/21). Kept distinct from Receiving Operator for segregation of duties.');

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
   END — seeded (idempotent): 2 role families · 14 roles.
   NOT seeded: UserRoles/GroupRoles assignments (host admin) · fr-FR translators.
   Applied additions (newest last — append future cards' roles above the summary):
     2026-07-03  initial registry — 10 Master Data roles + ASN Manager + Refuse Delivery
     2026-07-03  Receiving Operator (Receive-page cards 09–17)
     2026-07-03  Quality Inspector (Inspect-page cards 18–21)
   ============================================================================ */
