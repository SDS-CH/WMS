/* ============================================================================
   WMS (3PL) — STOCK-OUT SEED / REFERENCE DATA
   Companion to: 05_stock_out_schema.sql  (run the schema FIRST).
   Run order   : 01_master_data_schema.sql -> 01_master_data_seed.sql ->
                 02_goods_reception_schema.sql -> 02_goods_reception_seed.sql ->
                 05_stock_out_schema.sql -> THIS FILE.
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Scope of file : Canonical REFERENCE rows the Stock-Out screens CONSUME
                   (rather than data a user authors on screen).

   WHY this file exists
   --------------------
   ONE reason-code domain is read live by the Stock-Out screens but is not yet
   seeded anywhere (01 seeds status/adjust/correct/return/dispatch; 02 seeds
   receipt/refuse/discrepancy; the 02 seed header explicitly leaves 'rtv' to
   "the section that first consumes it" — this one):

     * 'rtv' — Return-to-vendor / client reasons on erp-so-rtv.html +
               pwa-so-rtv.html: reasonsFor('rtv'). Stored on wmsrtv.reasonid.
               Single shared list. The screen also appends a local
               'Other (see note)' option — promoted here to master data so the
               FK resolves when it is chosen (same posture as the 02 seed's
               'discrepancy' Other).

   NOTE: the ad-hoc dispatch justifications ('dispatch' domain, consumed by
   pwa-so-dispatch + stored on wmsoutbound.adhocreasonid) were already seeded
   by 01_master_data_seed.sql — NOT duplicated here. The 'dispose' domain
   belongs to the Inventory-Ops seed (06).

   NOT seeded here (minted by the operational flow, never pre-seeded):
     wmsoutbound / wmsoutboundline, wmsallocation(+serial),
     wmsshipment / wmsshipmentline(+serial), wmsrtv / wmsrtvline(+serial) —
     created by the Orders / Allocation / Dispatch / RTV flows at runtime.
     Consignees and carriers are user-authored Master Data (Section 01 screens).

   CONVENTIONS (identical to 01/02 seed files)
   -------------------------------------------
   * Idempotent: every INSERT is guarded by NOT EXISTS on the business unique
     key (domain.code · group(domainid,groupkey) · reason(groupid,reasontext)).
   * Table variables are scoped per batch — do NOT add GO between a DECLARE and
     its use.

   HOW TO RUN
   ----------
   Select your WMS database first (e.g.  USE [WMS];  or the per-agency DMS_<n>),
   then run the files in the order listed at the top.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   wmsreasondomain / wmsreasongroup / wmsreason — Stock-Out reason vocabulary
   (adds the 'rtv' domain on top of 01's base set + 02's receiving set)
   ============================================================================ */

/* --- Domain (code | label | groupedby) --- */
DECLARE @dom TABLE (code VARCHAR(20), label NVARCHAR(80), groupedby NVARCHAR(40) NULL);
INSERT INTO @dom (code, label, groupedby) VALUES
    ('rtv', N'Return to vendor / client', NULL);   -- single shared list

INSERT INTO dbo.wmsreasondomain (code, label, groupedby)
SELECT s.code, s.label, s.groupedby
FROM @dom s
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreasondomain d WHERE d.code = s.code);
GO

/* --- Group (domain code | groupkey | label | seq) --- */
DECLARE @grp TABLE (domaincode VARCHAR(20), groupkey VARCHAR(40), label NVARCHAR(80), seq INT);
INSERT INTO @grp (domaincode, groupkey, label, seq) VALUES
    ('rtv', 'all', N'All RTV', 1);

INSERT INTO dbo.wmsreasongroup (domainid, groupkey, label, seq)
SELECT d.id, s.groupkey, s.label, s.seq
FROM @grp s
JOIN dbo.wmsreasondomain d ON d.code = s.domaincode
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreasongroup g WHERE g.domainid = d.id AND g.groupkey = s.groupkey);
GO

/* --- Starter reasons (domain code | groupkey | reasontext | seq) — user-editable
       on erp-md-reasons.html. Source: DB.reasonDomains 'rtv' in data.js, plus the
       screen-local 'Other (see note)' promoted to master data. --- */
DECLARE @rsn TABLE (domaincode VARCHAR(20), groupkey VARCHAR(40), reasontext NVARCHAR(200), seq INT);
INSERT INTO @rsn (domaincode, groupkey, reasontext, seq) VALUES
    ('rtv','all',N'Defective — return to supplier',   1),
    ('rtv','all',N'Recall — return to supplier',      2),
    ('rtv','all',N'Expired — return to client',       3),
    ('rtv','all',N'Wrong goods — return to supplier', 4),
    ('rtv','all',N'Client recall / withdrawal',       5),
    ('rtv','all',N'Over-delivery returned',           6),
    ('rtv','all',N'Other (see note)',                 7);

INSERT INTO dbo.wmsreason (groupid, reasontext, seq, status)
SELECT g.id, s.reasontext, s.seq, 'active'
FROM @rsn s
JOIN dbo.wmsreasondomain d ON d.code = s.domaincode
JOIN dbo.wmsreasongroup  g ON g.domainid = d.id AND g.groupkey = s.groupkey
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreason x WHERE x.groupid = g.id AND x.reasontext = s.reasontext);
GO

/* ============================================================================
   END OF STOCK-OUT SEED
   ----------------------------------------------------------------------------
   Seeded: Reason codes consumed by the Stock-Out screens
     wmsreasondomain — 1 : rtv
     wmsreasongroup  — 1 : rtv{all}
     wmsreason       — 7 : rtv(6 from data.js + 'Other (see note)')
   Re-runnable: each INSERT is guarded by NOT EXISTS on the business unique key.

   No operational rows are seeded — outbound orders, allocations, shipments /
   delivery notes and RTVs are all minted by the Stock-Out flow.
   ============================================================================ */
