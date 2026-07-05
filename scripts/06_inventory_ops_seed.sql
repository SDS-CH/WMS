/* ============================================================================
   WMS (3PL) — INVENTORY OPERATIONS SEED / REFERENCE DATA
   Companion to: 06_inventory_ops_schema.sql  (run the schema FIRST).
   Run order   : 01 schema+seed -> 02 schema+seed -> 05 schema+seed ->
                 06_inventory_ops_schema.sql -> THIS FILE.
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Scope of file : The LAST missing reason-code domain. With it every domain
                   consumed by any WMS screen is seeded:
                     01: status · adjust · correct · return · dispatch
                     02: receipt · refuse · discrepancy
                     05: rtv
                     06: dispose   ← this file

     * 'dispose' — Disposal / scrap reasons on erp-inv-dispose.html +
                   pwa-inv-dispose.html: reasonsFor('dispose', method).
                   Stored on wmsdisposal.reasonid. groupedBy='Method' with
                   group keys scrap|destroy|writeoff — deliberately IDENTICAL
                   to the wmsdisposal.method CHECK values, so the reason
                   dropdown filters by the chosen method with no mapping table.

   Source of truth: DB.reasonDomains 'dispose' in wms/mockups/assets/data.js
   (the edge-case seed block, ~line 1408).

   NOT seeded here (minted by the operational flows, never pre-seeded):
     wmsphysical*, wmscount*, wmsmove, wmstransfer*, wmsadjustment*,
     wmsrepack*, wmsreturn*, wmsdisposal.

   CONVENTIONS (identical to 01/02/05 seed files)
   ----------------------------------------------
   * Idempotent: every INSERT guarded by NOT EXISTS on the business unique key.
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

/* --- Domain (code | label | groupedby) --- */
DECLARE @dom TABLE (code VARCHAR(20), label NVARCHAR(80), groupedby NVARCHAR(40) NULL);
INSERT INTO @dom (code, label, groupedby) VALUES
    ('dispose', N'Disposal / scrap', N'Method');

INSERT INTO dbo.wmsreasondomain (code, label, groupedby)
SELECT s.code, s.label, s.groupedby
FROM @dom s
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreasondomain d WHERE d.code = s.code);
GO

/* --- Groups (domain code | groupkey | label | seq) ---
   Keys MUST match wmsdisposal.method CHECK values: scrap | destroy | writeoff. */
DECLARE @grp TABLE (domaincode VARCHAR(20), groupkey VARCHAR(40), label NVARCHAR(80), seq INT);
INSERT INTO @grp (domaincode, groupkey, label, seq) VALUES
    ('dispose', 'scrap',    N'Scrap',     1),
    ('dispose', 'destroy',  N'Destroy',   2),
    ('dispose', 'writeoff', N'Write-off', 3);

INSERT INTO dbo.wmsreasongroup (domainid, groupkey, label, seq)
SELECT d.id, s.groupkey, s.label, s.seq
FROM @grp s
JOIN dbo.wmsreasondomain d ON d.code = s.domaincode
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreasongroup g WHERE g.domainid = d.id AND g.groupkey = s.groupkey);
GO

/* --- Starter reasons (domain code | groupkey | reasontext | seq) — user-editable
       on erp-md-reasons.html. Source: data.js 'dispose' domain (~1408–1412). --- */
DECLARE @rsn TABLE (domaincode VARCHAR(20), groupkey VARCHAR(40), reasontext NVARCHAR(200), seq INT);
INSERT INTO @rsn (domaincode, groupkey, reasontext, seq) VALUES
    ('dispose','scrap',   N'Damaged beyond repair',       1),
    ('dispose','scrap',   N'Spoiled / contaminated',      2),
    ('dispose','scrap',   N'Failed QA',                   3),
    ('dispose','scrap',   N'Pest / infestation',          4),
    ('dispose','destroy', N'Expired — destroy',           1),
    ('dispose','destroy', N'Recall — destroy',            2),
    ('dispose','destroy', N'Regulatory destruction',      3),
    ('dispose','destroy', N'Client-instructed destruction', 4),
    ('dispose','writeoff',N'Shrinkage / unrecoverable',   1),
    ('dispose','writeoff',N'Lost in warehouse',           2),
    ('dispose','writeoff',N'Insurance write-off',         3);

INSERT INTO dbo.wmsreason (groupid, reasontext, seq, status)
SELECT g.id, s.reasontext, s.seq, 'active'
FROM @rsn s
JOIN dbo.wmsreasondomain d ON d.code = s.domaincode
JOIN dbo.wmsreasongroup  g ON g.domainid = d.id AND g.groupkey = s.groupkey
WHERE NOT EXISTS (SELECT 1 FROM dbo.wmsreason x WHERE x.groupid = g.id AND x.reasontext = s.reasontext);
GO

/* ============================================================================
   END OF INVENTORY OPERATIONS SEED
   ----------------------------------------------------------------------------
   Seeded: wmsreasondomain — 1 (dispose) · wmsreasongroup — 3 (scrap/destroy/
   writeoff) · wmsreason — 11. Re-runnable (NOT EXISTS guards).
   With this file, EVERY reason domain any WMS screen consumes is seeded.
   ============================================================================ */
