/* ============================================================================
   WMS (3PL) — SECTION 08: PWA FOUNDATION SCHEMA  (action / debug log)
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Target DB     : the per-agency WMS database (same DB as sections 01–06;
                   e.g. DMS_11) — run AFTER 01/02 (no FK dependencies, but the
                   log references their ids logically).
   Sources       : SDS-ERP-SOLUTION/WMSProject/cards/pwa-foundation/_progress.md
                   (kickoff requirement 6: every PWA action logged & traceable,
                   with an ERP debug screen) · cards 05 (ingest) / 06 (screen).

   WHAT THIS IS
   ------------
   The server-side landing table for the scanner PWA's action trail. EVERY
   action the device performs — sign-ins, navigation, mutating calls (whether
   executed online or queued offline and synced later), sync flushes, errors —
   is captured on the device and shipped up in batches. When a warehouse
   reports "the app did something wrong at 10:40", the ERP log screen (card 06)
   filters this table by user/device/time and shows exactly what happened,
   including the failed requests and their payloads.

   Design rules honored (README conventions):
   - lower-case wms-prefixed table, id INT IDENTITY PK, no FK binding to the
     host Users table (logical reference only — a log INSERT must never fail
     on referential grounds).
   - APPEND-ONLY: no update/delete path in the app; housekeeping purge is a
     later ops concern (see note at the end).
   - SQL 2014: payloads are NVARCHAR(MAX) JSON strings (no native JSON type).
   - Idempotent ingest: (deviceid, entryid) is the client-generated identity of
     an entry — the batched ingest endpoint skips duplicates on retransmission
     (an offline queue may re-send a batch after a timeout), enforced by the
     filtered unique index below.
   ============================================================================ */

SET NOCOUNT ON;
GO

/* ---- wmsactionlog — one row per PWA action/event ---------------------------- */
IF OBJECT_ID(N'dbo.wmsactionlog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsactionlog (
        id             INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_wmsactionlog PRIMARY KEY,

        /* client-generated identity (idempotent re-send guard) */
        entryid        VARCHAR(50)   NOT NULL,  -- uuid minted on the device per entry
        deviceid       VARCHAR(100)  NOT NULL,  -- installation id (uuid persisted on the device)

        /* who / where / when */
        userid         INT           NOT NULL,  -- host [dbo].[Users].Id — STAMPED SERVER-SIDE from the JWT, never trusted from the client
        username       VARCHAR(100)  NULL,      -- denormalized for fast log reading
        sessionid      VARCHAR(50)   NULL,      -- login-session correlation (uuid per sign-in)
        appversion     VARCHAR(30)   NULL,
        clientid       INT           NULL,      -- wmsclient.id context (logical ref)
        siteid         INT           NULL,      -- wmssite.id context (logical ref)
        occurredat     DATETIME2     NOT NULL,  -- device-side moment the action happened
        receivedat     DATETIME2     NOT NULL CONSTRAINT df_wmsactionlog_receivedat DEFAULT SYSUTCDATETIME(),

        /* what */
        category       VARCHAR(20)   NOT NULL CONSTRAINT ck_wmsactionlog_category
                         CHECK (category IN ('auth','nav','action','sync','error','debug')),
        action         VARCHAR(80)   NOT NULL,  -- dotted verb, e.g. 'auth.login', 'receive.submit', 'sync.flush'
        origin         VARCHAR(10)   NOT NULL CONSTRAINT df_wmsactionlog_origin DEFAULT 'online'
                         CONSTRAINT ck_wmsactionlog_origin CHECK (origin IN ('online','offline')),
        outcome        VARCHAR(20)   NOT NULL CONSTRAINT df_wmsactionlog_outcome DEFAULT 'ok'
                         CONSTRAINT ck_wmsactionlog_outcome
                         CHECK (outcome IN ('ok','fail','queued','synced','conflict')),

        /* diagnostics */
        httpstatus     INT           NULL,      -- of the underlying API call, when there was one
        durationms     INT           NULL,
        correlationid  VARCHAR(50)   NULL,      -- ties a queued action to its later sync result rows
        payload        NVARCHAR(MAX) NULL,      -- JSON string (request body / event detail)
        errormessage   NVARCHAR(2000) NULL
    );

    /* duplicate-batch guard: one row per device entry */
    CREATE UNIQUE INDEX ux_wmsactionlog_device_entry ON dbo.wmsactionlog (deviceid, entryid);

    /* read paths of the ERP log screen (card 06) */
    CREATE INDEX ix_wmsactionlog_occurredat ON dbo.wmsactionlog (occurredat DESC);
    CREATE INDEX ix_wmsactionlog_user       ON dbo.wmsactionlog (userid, occurredat DESC);
    CREATE INDEX ix_wmsactionlog_device     ON dbo.wmsactionlog (deviceid, occurredat DESC);
    CREATE INDEX ix_wmsactionlog_corr       ON dbo.wmsactionlog (correlationid) WHERE correlationid IS NOT NULL;
END
GO

/* ============================================================================
   END — 1 table. Idempotent (IF OBJECT_ID guard); re-run safe.
   Housekeeping: the log grows unbounded by design in v1 — a retention purge
   (e.g. DELETE < 90 days, keeping 'error' rows longer) is a deliberate later
   ops card, NOT silently included here.
   Applied additions (newest last):
     2026-07-06  wmsactionlog (cards PWA-ACTIONLOG-BACKEND / ERP-PWA-LOG-SCREEN)
   ============================================================================ */
