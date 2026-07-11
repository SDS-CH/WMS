/* ============================================================================
   WMS (3PL) — MASTER DATA SEED / REFERENCE DATA
   Companion to: 01_master_data_schema.sql  (run the schema FIRST).
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Scope of file : Canonical REFERENCE rows that the Master Data screens expect
                   to already exist (as opposed to data a user authors on screen).
                   Schema (CREATE TABLE) lives in 01_master_data_schema.sql; this
                   file only INSERTs reference rows. Keep the two files separate.

   WHY this file exists
   --------------------
   Some Master Data screens DEPEND on reference rows being present before they
   are usable — they consume, not author, them:
     * erp-md-uom.html "Packaging hierarchies" tab — the base-unit dropdown and
       each pack level's UoM dropdown are sourced from wmsuom. With an empty
       wmsuom the packaging editor cannot be used. The mock even hardcodes a
       base-unit list (EA, VIAL, PC, PR, KG, L, M). So the canonical Units of
       Measure are SEED data, not user-authored data.
   The "Units of Measure" tab itself can still author additional units; this file
   only guarantees the canonical base + common set exists.

   NOT seeded here (authored on-screen by the user, per their own CRUD):
     * wmscategory / wmssubcategory  — authored on erp-md-categories.html.
     * wmsconsignee                  — authored on erp-md-consignees.html (needs clients).
     * wmsclient / wmssite / ...      — authored on their own screens.
   ALSO seeded (finalised 2026-07-11 while finishing MD-SITES-SCREEN):
     * wmsdefaultsitelevel — the Zone/Aisle/Rack/Bin template a NEW site's
       addressing levels seed from (an empty template made the site editor
       pre-fill ZERO level rows).

   CONVENTIONS
   -----------
   * Idempotent: every INSERT is guarded by NOT EXISTS on the business "code",
     so the file is safe to re-run.
   * Honors wmsuom constraints: ck_wmsuom_category (Count|Weight|Volume|Length|
     Packaging) and uq_wmsuom_onebase (AT MOST ONE isbase=1 per category — the
     four measurement categories each get exactly one base; Packaging gets none).

   HOW TO RUN
   ----------
   Select your WMS database first (e.g.  USE [WMS];  or the per-agency DMS_<n>),
   run 01_master_data_schema.sql, then run this file.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ----------------------------------------------------------------------------
   wmsuom — Units of Measure (GLOBAL, shared by every client)
   code | name | category | isbase | allowdecimal
   ---------------------------------------------------------------------------- */

/* Count — base = EA (whole counts; no decimals on counted units) */
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'EA')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('EA',   N'Each',        'Count',     1, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'PC')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('PC',   N'Piece',       'Count',     0, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'PR')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('PR',   N'Pair',        'Count',     0, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'VIAL')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('VIAL', N'Vial',        'Count',     0, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'DOZ')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('DOZ',  N'Dozen',       'Count',     0, 0);

/* Weight — base = KG (decimals allowed) */
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'KG')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('KG',   N'Kilogram',    'Weight',    1, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'G')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('G',    N'Gram',        'Weight',    0, 1);

/* Volume — base = L (decimals allowed) */
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'L')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('L',    N'Litre',       'Volume',    1, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'ML')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('ML',   N'Millilitre',  'Volume',    0, 1);

/* Length — base = M (decimals allowed) */
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'M')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('M',    N'Metre',       'Length',    1, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'CM')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('CM',   N'Centimetre',  'Length',    0, 1);

/* Packaging — NO base unit (packs are built into hierarchies; whole only) */
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'BOX')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('BOX',  N'Box',         'Packaging', 0, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'CTN')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('CTN',  N'Carton',      'Packaging', 0, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'CASE')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('CASE', N'Case',        'Packaging', 0, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'TRAY')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('TRAY', N'Tray',        'Packaging', 0, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.wmsuom WHERE code = 'PAL')
    INSERT INTO dbo.wmsuom (code, name, category, isbase, allowdecimal) VALUES ('PAL',  N'Pallet',      'Packaging', 0, 0);
GO

/* ============================================================================
   wmsreasondomain / wmsreasongroup / wmsreason — REASON CODE vocabulary
   SCREEN  : erp-md-reasons.html  (tabs = domains, cards = groups, chips = reasons)
   ----------------------------------------------------------------------------
   WHY seeded: the screen CONSUMES domains + groups (it renders the tabs from
   wmsreasondomain and the group cards from wmsreasongroup) — with empty tables
   the screen has no tabs and is unusable. Domains + groups are therefore FIXED
   reference data (not user-authored). The individual reasons ARE user-editable
   on screen; the starter set below mirrors the mock so the screen is demo-ready.
   Source of truth for the values: DB.reasonDomains in wms/mockups/assets/data.js.
   The mock's empty-string  groupedBy:''  normalises to NULL here (per schema).
   Idempotent: guarded by the business unique keys (code / domainid+groupkey /
   groupid+reasontext). Table variables are scoped per batch — do NOT add GO
   between a DECLARE and its use.
   ---------------------------------------------------------------------------- */

/* --- Domains (code | label | groupedby) --- */
DECLARE @dom TABLE (code VARCHAR(20), label NVARCHAR(80), groupedby NVARCHAR(40) NULL);
INSERT INTO @dom (code, label, groupedby) VALUES
    ('status',   N'Stock status change',  N'Target status'),
    ('adjust',   N'Quantity adjustment',  N'Direction'),
    ('correct',  N'Attribute correction', NULL),
    ('return',   N'Returns / put-back',   NULL),
    ('dispatch', N'Ad-hoc dispatch',      NULL);

INSERT INTO dbo.wmsreasondomain (code, label, groupedby)
SELECT s.code, s.label, s.groupedby
FROM @dom s
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreasondomain d WHERE d.code = s.code);
GO

/* --- Groups (domain code | groupkey | label | seq) --- */
DECLARE @grp TABLE (domaincode VARCHAR(20), groupkey VARCHAR(40), label NVARCHAR(80), seq INT);
INSERT INTO @grp (domaincode, groupkey, label, seq) VALUES
    ('status',  'available',  N'→ Available (release)', 1),
    ('status',  'quarantine', N'→ Quarantine',          2),
    ('status',  'hold',       N'→ Hold',                3),
    ('status',  'damaged',    N'→ Damaged',             4),
    ('status',  'expired',    N'→ Expired',             5),
    ('adjust',  'increase',   N'Increase (+)',          1),
    ('adjust',  'decrease',   N'Decrease (−)',          2),
    ('correct', 'all',        N'All corrections',       1),
    ('return',  'all',        N'All returns',           1),
    ('dispatch','all',        N'All ad-hoc dispatches', 1);

INSERT INTO dbo.wmsreasongroup (domainid, groupkey, label, seq)
SELECT d.id, s.groupkey, s.label, s.seq
FROM @grp s
JOIN dbo.wmsreasondomain d ON d.code = s.domaincode
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreasongroup g WHERE g.domainid = d.id AND g.groupkey = s.groupkey);
GO

/* --- Starter reasons (domain code | groupkey | reasontext | seq) — user-editable on screen --- */
DECLARE @rsn TABLE (domaincode VARCHAR(20), groupkey VARCHAR(40), reasontext NVARCHAR(200), seq INT);
INSERT INTO @rsn (domaincode, groupkey, reasontext, seq) VALUES
    -- status / available
    ('status','available',N'Inspection passed — release',1),
    ('status','available',N'Hold lifted — release',2),
    ('status','available',N'Re-graded as good',3),
    ('status','available',N'Released by QA',4),
    ('status','available',N'Recount confirmed good',5),
    -- status / quarantine
    ('status','quarantine',N'Failed inspection',1),
    ('status','quarantine',N'Recall / quality hold',2),
    ('status','quarantine',N'Suspected contamination',3),
    ('status','quarantine',N'Awaiting QA decision',4),
    ('status','quarantine',N'Pending supplier investigation',5),
    -- status / hold
    ('status','hold',N'Customer / commercial hold',1),
    ('status','hold',N'Documentation / paperwork hold',2),
    ('status','hold',N'Recall / quality hold',3),
    ('status','hold',N'Awaiting QA decision',4),
    ('status','hold',N'Legal / customs hold',5),
    ('status','hold',N'Awaiting client instruction',6),
    ('status','hold',N'Credit / payment hold',7),
    -- status / damaged
    ('status','damaged',N'Damage found',1),
    ('status','damaged',N'Crushed / broken in handling',2),
    ('status','damaged',N'Spoilage / temperature excursion',3),
    ('status','damaged',N'Contaminated',4),
    -- status / expired
    ('status','expired',N'Shelf-life / expiry date passed',1),
    ('status','expired',N'Use-by date passed',2),
    ('status','expired',N'Failed stability re-test',3),
    ('status','expired',N'Short-dated — withdrawn per client',4),
    -- adjust / increase
    ('adjust','increase',N'Found stock',1),
    ('adjust','increase',N'Count correction (up)',2),
    ('adjust','increase',N'Receiving under-count',3),
    ('adjust','increase',N'Conversion gain',4),
    -- adjust / decrease
    ('adjust','decrease',N'Loss / shrinkage',1),
    ('adjust','decrease',N'Damage write-off',2),
    ('adjust','decrease',N'Count correction (down)',3),
    ('adjust','decrease',N'Receiving over-count',4),
    ('adjust','decrease',N'Sample / destructive test',5),
    -- correct / all
    ('correct','all',N'Wrong lot keyed',1),
    ('correct','all',N'Wrong expiry keyed',2),
    ('correct','all',N'Wrong serial captured',3),
    ('correct','all',N'Wrong product',4),
    ('correct','all',N'Wrong owning client',5),
    ('correct','all',N'Data-entry error',6),
    -- return / all
    ('return','all',N'Customer return — unused',1),
    ('return','all',N'Customer refused delivery',2),
    ('return','all',N'Over-pick put-back',3),
    ('return','all',N'Damaged in transit',4),
    ('return','all',N'Wrong item shipped',5),
    -- dispatch / all
    ('dispatch','all',N'Customer collection — no ERP order',1),
    ('dispatch','all',N'ERP / system unavailable',2),
    ('dispatch','all',N'Emergency / urgent shipment',3),
    ('dispatch','all',N'Phone / email order — key later',4),
    ('dispatch','all',N'Sales order not yet in system',5);

INSERT INTO dbo.wmsreason (groupid, reasontext, seq, status)
SELECT g.id, s.reasontext, s.seq, 'active'
FROM @rsn s
JOIN dbo.wmsreasondomain d ON d.code = s.domaincode
JOIN dbo.wmsreasongroup  g ON g.domainid = d.id AND g.groupkey = s.groupkey
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreason x WHERE x.groupid = g.id AND x.reasontext = s.reasontext);
GO

/* ----------------------------------------------------------------------------
   wmsdefaultsitelevel — the DEFAULT addressing template for NEW sites
   (Zone -> Aisle -> Rack -> Bin), read by the site editor's new-site seed and
   its "Reset to default" action. Flagged by the Sites cards; finalised
   2026-07-11 (MD-SITES-SCREEN finish pass — an empty template made a new
   site's location structure start EMPTY). Idempotent on levelorder
   (uq_wmsdefaultsitelevel_order).
   ---------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.wmsdefaultsitelevel WHERE levelorder = 1)
    INSERT INTO dbo.wmsdefaultsitelevel (levelorder, levelname) VALUES (1, N'Zone');
IF NOT EXISTS (SELECT 1 FROM dbo.wmsdefaultsitelevel WHERE levelorder = 2)
    INSERT INTO dbo.wmsdefaultsitelevel (levelorder, levelname) VALUES (2, N'Aisle');
IF NOT EXISTS (SELECT 1 FROM dbo.wmsdefaultsitelevel WHERE levelorder = 3)
    INSERT INTO dbo.wmsdefaultsitelevel (levelorder, levelname) VALUES (3, N'Rack');
IF NOT EXISTS (SELECT 1 FROM dbo.wmsdefaultsitelevel WHERE levelorder = 4)
    INSERT INTO dbo.wmsdefaultsitelevel (levelorder, levelname) VALUES (4, N'Bin');
GO

/* ============================================================================
   END OF MASTER DATA SEED
   ----------------------------------------------------------------------------
   Seeded: wmsdefaultsitelevel — the 4-level default addressing template
     (1 Zone · 2 Aisle · 3 Rack · 4 Bin), idempotent on levelorder.
   Seeded: wmsuom — 16 canonical units
     Count(5): EA*, PC, PR, VIAL, DOZ   Weight(2): KG*, G   Volume(2): L*, ML
     Length(2): M*, CM                  Packaging(5): BOX, CTN, CASE, TRAY, PAL
     (* = the single base unit for its measurement category)
   Seeded: Reason codes (erp-md-reasons.html skeleton + starter reasons)
     wmsreasondomain — 5  : status, adjust, correct, return, dispatch
     wmsreasongroup  — 11 : status{available,quarantine,hold,damaged,expired},
                            adjust{increase,decrease}, correct/return/dispatch{all}
     wmsreason       — 50 : the mock's starter reason set (user-editable on screen)
   Re-runnable: each INSERT is guarded by NOT EXISTS on the business unique key
     (uom.code · domain.code · group(domainid,groupkey) · reason(groupid,reasontext)).
   ============================================================================ */
