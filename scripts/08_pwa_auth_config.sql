/* ============================================================================
   WMS PWA (08) — HOST AUTH CONFIG: per-app (PWA) token expirations
   ----------------------------------------------------------------------------
   Target engine  : Microsoft SQL Server 2014  (hard constraint)
   ⚠ TARGET DB    : the HOST AUTH / IDENTITY database (the AU / AuthContext DB —
                    the one holding [dbo].[ERPGlobalConfigs], [dbo].[Users]) —
                    **NOT** the per-agency DMS_xx database and **NOT** the WMS DB.
                    Config is per ENVIRONMENT row: run ONCE per environment.

   WHY THIS FILE EXISTS (card PWA-AUTH-BACKEND, section pwa-foundation)
   --------------------------------------------------------------------
   The scanner PWA authenticates against the same AU module as the ERP, but
   warehouse devices need LONG-LIVED tokens (1 day / 1 week / 1 year — the
   operator must not re-type a password mid-shift or after an offline stretch),
   while the ERP web session keeps its short lifetimes. AU.Auth/JwtManager.cs
   already reads AccessTokenExpiration / RefreshTokenExpiration (minutes) live
   from [dbo].[ERPGlobalConfigs] per EnvironmentName at every token issuance —
   this script adds the PWA-SPECIFIC pair next to them. NULL = fall back to the
   global values (so environments that never configure the PWA keep working).

   Values are MINUTES (same unit as the existing columns):
     1 day = 1440 · 1 week = 10080 · 30 days = 43200 · 1 year = 525600
   Configured from the ERP: General Settings › Authentication & Security ›
   Session (role-management app) — extended by card PWA-AUTH-BACKEND.

   Idempotent: guarded by COL_LENGTH checks; safe to re-run anywhere.

   HOW TO RUN
   ----------
   USE [<your host auth DB>];   -- the AU / identity database of the environment
   -- then execute this file. Re-run safe.
   ============================================================================ */

SET NOCOUNT ON;
GO

/* ---- 1. Columns (minutes; NULL = use the global Access/RefreshTokenExpiration) */
IF COL_LENGTH('dbo.ERPGlobalConfigs', 'PwaAccessTokenExpiration') IS NULL
    ALTER TABLE dbo.ERPGlobalConfigs ADD PwaAccessTokenExpiration INT NULL;
GO
IF COL_LENGTH('dbo.ERPGlobalConfigs', 'PwaRefreshTokenExpiration') IS NULL
    ALTER TABLE dbo.ERPGlobalConfigs ADD PwaRefreshTokenExpiration INT NULL;
GO

/* ---- 2. Seed defaults where unset (access 1 day, refresh 1 week) ------------
   Deliberately conservative starters — raise per client policy from the ERP
   screen (e.g. refresh to 43200/525600 for long-offline sites). */
UPDATE dbo.ERPGlobalConfigs
   SET PwaAccessTokenExpiration = 1440
 WHERE PwaAccessTokenExpiration IS NULL;

UPDATE dbo.ERPGlobalConfigs
   SET PwaRefreshTokenExpiration = 10080
 WHERE PwaRefreshTokenExpiration IS NULL;
GO

/* ---- 3. Verify ---------------------------------------------------------------- */
SELECT Id, EnvironmentName,
       AccessTokenExpiration,    RefreshTokenExpiration,
       PwaAccessTokenExpiration, PwaRefreshTokenExpiration
FROM dbo.ERPGlobalConfigs
ORDER BY EnvironmentName;
GO

/* ============================================================================
   END — idempotent. Applied additions (newest last):
     2026-07-06  PwaAccessTokenExpiration + PwaRefreshTokenExpiration (card PWA-AUTH-BACKEND)
   ============================================================================ */
