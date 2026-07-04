/* ============================================================================
   WMS (3PL) — MASTER DATA STRUCTURE UPDATES  (migration companion to file 01)
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)

   WHY THIS FILE EXISTS (the update policy)
   ----------------------------------------
   `01_master_data_schema.sql` is the CANONICAL structure: it is edited IN PLACE
   whenever a Master Data table changes, so a fresh environment (e.g. PROD) gets
   the full, current structure from the numbered files alone. But 01's CREATE
   blocks are guarded by IF OBJECT_ID(...) IS NULL — on a database that ALREADY
   executed 01 (the dev environments) an edited CREATE block silently no-ops.

   THIS file carries the same changes as guarded ALTER statements, so an
   already-provisioned database catches up to the canonical structure:

     * Fresh DB  : run 01 (full current structure) -> running this file no-ops.
     * Existing  : run this file -> guarded ALTERs bring the DB up to date.

   Every structural change to an already-shipped 01 table is therefore applied
   TWICE at authoring time: (1) edit the CREATE block in 01, and (2) append a
   dated, guarded UPDATE block here. Constraint names MUST be identical in both
   files so the guards recognise either provisioning path.

   Idempotent and re-run safe: every block is guarded (COL_LENGTH / OBJECT_ID),
   so the file can be executed repeatedly on any environment.

   HOW TO RUN
   ----------
   USE [WMS];  -- (or the per-agency DMS_xx database)
   -- run any time AFTER 01_master_data_schema.sql. Safe to re-run.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   UPDATE 2026-07-03 — wmsproduct.verificationstatus
   ----------------------------------------------------------------------------
   Source : Goods-Reception schema review (02_goods_reception_schema.sql, second
            verification pass). The Receive screen's INLINE product creation is
            role-based (02_Goods_Reception In-Scope): privileged roles create the
            product LIVE ('verified'); other roles create it as 'pending' —
            excluded from normal product pickers until a supervisor / the ERP
            confirms it. wmsproduct had no column to persist that policy.
   Change : ADD verificationstatus VARCHAR(20) NOT NULL DEFAULT 'verified'
            + CHECK ('verified'|'pending'). Existing rows (authored on the
            Products screen) are correctly backfilled 'verified' by the default.
   ============================================================================ */
IF COL_LENGTH(N'dbo.wmsproduct', N'verificationstatus') IS NULL
BEGIN
    ALTER TABLE dbo.wmsproduct
        ADD verificationstatus VARCHAR(20) NOT NULL
            CONSTRAINT df_wmsproduct_verif DEFAULT ('verified');
END
GO

IF OBJECT_ID(N'dbo.ck_wmsproduct_verif', N'C') IS NULL
BEGIN
    ALTER TABLE dbo.wmsproduct WITH CHECK
        ADD CONSTRAINT ck_wmsproduct_verif CHECK (verificationstatus IN ('verified','pending'));
END
GO

/* ============================================================================
   END OF MASTER DATA UPDATES
   ----------------------------------------------------------------------------
   Applied updates (newest last — append new blocks above this footer):
     2026-07-03  wmsproduct.verificationstatus ('verified'|'pending')
   ============================================================================ */
