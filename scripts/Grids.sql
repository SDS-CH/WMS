/* ============================================================================
   WMS (3PL) — GRID IDENTIFIERS SEED   ([IdentityDb].[dbo].[ERPGridIdentifiers])

   PURPOSE
   -------
   One row per Kendo/Telerik grid used in the WMS Angular module. The shared grid
   component (sds-erp-front/projects/commons/components/kendo-grid) fetches each
   grid's configuration from this table by the grid's `name` — the GridNames enum
   value, e.g. 'wms#Client' (sds-erp-front/projects/commons/constants/grid.names.ts)
   — scoped to the WMS module id. A grid with NO row falls back to the component's
   hardcoded defaults; a grid WITH a row lets admins tune selection, exports, paging
   and persist saved column views/filters per grid.

   TARGET DB
   ---------
   The HOST identity database ([IdentityDb].[dbo].[ERPGridIdentifiers]) — the shared
   admin DB that also holds [ERPModules] / [RoleFamilies] / [Roles], NOT a per-agency
   database. Same target as 00_identity_roles_seed.sql.

   HOW TO RUN
   ----------
   USE [<your identity DB>];   -- e.g. the AU/identity database of the environment
   -- then execute this file. RE-RUN SAFE: every insert is guarded by (GridName + ModuleId).

   ⚠ MAINTENANCE RULE (keep this file in lock-step with the app)
   -------------------------------------------------------------
   EVERY new WMS Kendo grid must get a row here in the SAME pass it is built:
     1. add the grid's name to the GridNames enum (grid.names.ts, `WMS_* = 'wms#<Entity>'`), and
     2. append one VALUES line below (GridName = that enum value; LineIdentifier = the grid's
        key field, usually 'id'; ParentTableName = the entity).
   /implement-card enforces this for every WMS screen card (see the skill's frontend step).

   Id is an IDENTITY column → never inserted here.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---- 0. Resolve the WMS module id (matches 00_identity_roles_seed.sql) ------ */
DECLARE @moduleId INT = (SELECT TOP 1 Id FROM dbo.ERPModules WHERE Module = N'WMS');
IF @moduleId IS NULL
BEGIN
    -- Team-confirmed WMS module id, used when ERPModules has no 'WMS' row yet.
    SET @moduleId = 10;
    PRINT N'WARNING: ERPModules has no ''WMS'' row — falling back to ModuleId = 10 (team-confirmed).';
END
PRINT CONCAT(N'WMS grid identifiers: seeding for ModuleId = ', @moduleId, N'.');

/* ---- 1. Seed one row per WMS grid (idempotent) -----------------------------
   GridName          Screen / component                              LineIdentifier
   wms#Site          master-data/site           (Sites grid)         id
   wms#Client        master-data/client         (Clients grid)       id
   wms#Consignee     master-data/consignee      (Consignees grid)    id
   wms#Supplier      master-data/partners       (Suppliers tab)      id
   wms#Carrier       master-data/partners       (Carriers tab)       id
   wms#Category      master-data/category       (Categories grid)    id
   wms#Uom           master-data/uom            (Units of measure)   id
   wms#Packaging     master-data/uom            (Packaging tab)      id
   wms#Product       master-data/product        (Products grid)      id
   wms#Location      master-data/location       (Locations grid)     id
   wms#PwaLog        pwa-log                     (PWA activity log)   id
   wms#User          master-data/user           (Users & Roles grid) id
   wms#Asn           goods-reception/asn        (ASN worklist grid)  id
   wms#Inspection    goods-reception/inspection (QA worklist grid)   lpnId
   wms#Grn           goods-reception/grn        (GRN list grid)      id
   wms#Putaway          putaway/tasks (open)    (Putaway worklist grid)   lpnId
   wms#PutawayCompleted putaway/tasks (done)    (Putaway history grid)    txnId
   Flags mirror the grid component's defaultSettings (multi-select + selectable +
   Excel/PDF export + 10,20,50,100 paging). CanImportXML = 0: WMS uses the dedicated
   CSV Import flow (MD-IMPORT), not per-grid XML import. Tune any row afterwards. */
;WITH grids (GridName, LineIdentifier, ParentTableName) AS (
    SELECT * FROM (VALUES
        (N'wms#Site',      N'id', N'Site'),
        (N'wms#Client',    N'id', N'Client'),
        (N'wms#Consignee', N'id', N'Consignee'),
        (N'wms#Supplier',  N'id', N'Supplier'),
        (N'wms#Carrier',   N'id', N'Carrier'),
        (N'wms#Category',  N'id', N'Category'),
        (N'wms#Uom',       N'id', N'Uom'),
        (N'wms#Packaging', N'id', N'Packaging'),
        (N'wms#Product',   N'id', N'Product'),
        (N'wms#Location',  N'id', N'Location'),
        (N'wms#PwaLog',    N'id', N'PwaLog'),
        (N'wms#User',      N'id', N'Users'),
        (N'wms#Asn',        N'id',    N'Asn'),
        (N'wms#Inspection', N'lpnId', N'Inspection'),
        (N'wms#Grn',        N'id',    N'Grn'),
        (N'wms#Putaway',          N'lpnId', N'Putaway'),
        (N'wms#PutawayCompleted', N'txnId', N'PutawayCompleted')
    ) v (GridName, LineIdentifier, ParentTableName)
)
INSERT INTO dbo.ERPGridIdentifiers
    (GridName, ModuleId, LineIdentifier, IsMultipleSelect, IsSelectable,
     CanExportExcel, CanExportPDF, CanImportXML, PagesSize, DefaultView,
     ParentTableName, AutogenrateParentID, ChildTableNames,
     SpecialParentCondition, SpecialChildCondition, ForceShowOnlySelectedRow)
SELECT
     g.GridName, @moduleId, g.LineIdentifier, 1, 1,
     1, 1, 0, N'10,20,50,100', N'{}',
     g.ParentTableName, 1, NULL,
     NULL, NULL, NULL
FROM grids g
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.ERPGridIdentifiers e
    WHERE e.GridName = g.GridName AND e.ModuleId = @moduleId
);

PRINT CONCAT(N'WMS grid identifiers seeded. wms#* rows now present for module ', @moduleId, N': ',
    (SELECT COUNT(*) FROM dbo.ERPGridIdentifiers
     WHERE ModuleId = @moduleId AND GridName LIKE N'wms#%'), N' / 13 expected.');
GO
