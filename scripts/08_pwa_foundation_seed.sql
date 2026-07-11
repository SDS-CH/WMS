/* ============================================================================
   WMS (3PL) — SECTION 08: PWA FOUNDATION SEED  (action-log retention policy)
   Companion to: 08_pwa_foundation_schema.sql  (run the schema FIRST — and the
   01 schema, which owns dbo.wmssetting).
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Target DB     : the per-agency WMS database (e.g. DMS_11) — same DB as the
                   01/08 schema scripts.
   Source        : card PWA-LOG-RETENTION (closes the retention note left in
                   the 08 DDL footer).

   WHY this file exists
   --------------------
   wmsactionlog is append-only and grows with every scan on every device. The
   retention purge (POST /Wmsactionlog/purge) trims it on a policy the admin
   controls via two wmssetting rows:
     * pwalog.retentionDays      — routine rows older than this are purged
                                   (category <> 'error' AND outcome NOT IN
                                   ('fail','conflict')). Default 90.
     * pwalog.errorRetentionDays — ALL rows older than this are purged,
                                   including error/fail/conflict trails —
                                   support revisits those longest. Default 365.
   The purge endpoint falls back to the same 90/365 defaults when a row is
   missing or non-numeric — this seed makes the policy VISIBLE and editable
   wherever wmssetting rows are administered.

   CONVENTIONS
   -----------
   * Idempotent: every INSERT is guarded by NOT EXISTS on settingkey
     (uq_wmssetting_settingkey is the backstop) — safe to re-run; an existing
     row's admin-edited value is NEVER overwritten.

   HOW TO RUN
   ----------
   Select your WMS database first (e.g.  USE [DMS_11];), make sure
   01_master_data_schema.sql (wmssetting) has run, then run this file.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ----------------------------------------------------------------------------
   wmssetting — action-log retention policy (card PWA-LOG-RETENTION)
   ---------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM dbo.wmssetting WHERE settingkey = 'pwalog.retentionDays')
    INSERT INTO dbo.wmssetting (settingkey, settingvalue, valuetype, description)
    VALUES ('pwalog.retentionDays', N'90', 'int',
            N'PWA action log: routine rows (category <> error, outcome not fail/conflict) older than this many days are removed by the retention purge. Default 90.');

IF NOT EXISTS (SELECT 1 FROM dbo.wmssetting WHERE settingkey = 'pwalog.errorRetentionDays')
    INSERT INTO dbo.wmssetting (settingkey, settingvalue, valuetype, description)
    VALUES ('pwalog.errorRetentionDays', N'365', 'int',
            N'PWA action log: ALL rows older than this many days are removed by the retention purge, including error/fail/conflict trails. Default 365.');
GO

/* ============================================================================
   END — 2 wmssetting rows. Idempotent (NOT EXISTS guards); re-run safe.
   Applied additions (newest last):
     2026-07-11  pwalog.retentionDays / pwalog.errorRetentionDays  (card PWA-LOG-RETENTION)
   ============================================================================ */
