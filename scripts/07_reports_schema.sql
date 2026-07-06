use dms_11
/* ============================================================================
   WMS (3PL) — SECTION 07: REPORTS  (stored procedures only — no tables)
   ----------------------------------------------------------------------------
   Target engine  : Microsoft SQL Server 2014  (hard constraint — no
                    CREATE OR ALTER / DROP IF EXISTS / STRING_AGG / JSON)
   ⚠ TARGET DB    : the PER-AGENCY WMS database (DMS_xx) — the same DB that ran
                    01/02/05/06. NOT the host identity DB.

   WHY THIS FILE EXISTS
   --------------------
   The Reports section (../docs/06_Reports.md, PHASE_07_REPORTS.md) reads the
   stock + ledger tables created by sections 01–06; it creates NO tables of its
   own. Per ../scripts/README.md, views & stored procedures are added
   step-by-step by the build cards — this file is the canonical home for the
   report procedures, one per report, appended card by card:

     dbo.wmsrpt_soh      Stock on Hand           card RPT-SOH-BACKEND     (01-rpt-soh-backend.md)
     dbo.wmsrpt_txns     Transaction History     card RPT-TXNS-BACKEND    (03-rpt-txns-backend.md)
     dbo.wmsrpt_expiry   Expiry & Aging          card RPT-EXPIRY-BACKEND  (05-rpt-expiry-backend.md)
     dbo.wmsrpt_inbound  Inbound / Receipts      card RPT-INBOUND-BACKEND (07-rpt-inbound-backend.md)
     dbo.wmsrpt_outbound Outbound / Shipments    card RPT-OUTBOUND-BACKEND (09-rpt-outbound-backend.md)
     dbo.wmsrpt_variance Adjustments & Variances card RPT-VARIANCE-BACKEND (11-rpt-variance-backend.md)
     dbo.wmsrpt_utilization Bin Utilization      card RPT-UTIL-BACKEND    (13-rpt-utilization-backend.md)
     dbo.wmsrpt_trace_lots / _plates / _events   card RPT-TRACE-BACKEND   (15-rpt-trace-backend.md)
     dbo.wmsrpt_stockcard  Stock Card / Ledger   card RPT-STOCKCARD-BACKEND (17-rpt-stockcard-backend.md)
     dbo.wmsrpt_statement  Client Statement      card RPT-STATEMENT-BACKEND (19-rpt-statement-backend.md)

   ON-HAND-CHANGING TYPE MAP (shared by wmsrpt_stockcard + wmsrpt_statement —
   the full ck_wmstxn_type enum bucketed; the mock covers only 13 of 22 types):
     IN  (+qty)          : receive, transfer-receive, return
     OUT (-qty)          : dispatch, transfer-ship, transfer-loss, dispose, rtv
     ADJ (qty AS-WRITTEN): adjust, count, repack        ← wmstxn.qty is SIGNED
                           for adjustments (02 schema comment) — NO note-text
                           sign heuristic (the mock's adjSign() is replaced)
     INTERNAL (0)        : putaway, park, move, status, correct, inspect,
                           attach, attach-remove, reprint, refuse, transfer-cancel

   Authored at CARD-AUTHORING time (SDS-ERP-SOLUTION/WMSProject/cards/reporting/);
   executed via the /implement-card SQL gate. Idempotent: each proc is guarded
   with IF OBJECT_ID … DROP PROCEDURE + CREATE — safe to re-run anywhere.

   SCOPE ENFORCEMENT (CC-08 — non-negotiable)
   ------------------------------------------
   Every report proc takes @userid (the host [dbo].[Users].[Id], injected
   SERVER-SIDE from the JWT — never from a request body) and hard-scopes rows:
     - wmsuserprofile.allsites  = 0  → requested site must be in wmsusersite
     - wmsuserprofile.allclients = 0 → client rows filtered by wmsuserclient
   No wmsuserprofile row → the proc returns nothing.

   HOW TO RUN
   ----------
   USE [DMS_xx];   -- your agency WMS database
   -- execute this whole file. Re-run safe. Run AFTER 01/02/05/06 schemas.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* wmsrpt_soh -----------------------------------------------------------------
   SCREEN : erp-rpt-soh.html  (Reports › Stock on Hand; card RPT-SOH-SCREEN).
   PURPOSE: One flat row per ON-HAND license plate (qty > 0 at the site, any
            status) with availability/blocked/expired flags and the free
            (un-reserved) quantity. The FRONTEND does the client→product
            grouping + KPI math; this proc is the single data source.
   RULES  : mirrors mockups/assets/data.js —
            blocked   = status IN (quarantine, hold, damaged, expired)
            expired   = expiry < today (date-based; even while status='available')
            reserved  = SUM(wmsallocation.qty) on outbound orders in a LIVE
                        status ('allocated','picking','picked','partial').
                        NOTE: the mock's lpnAvail/outReserved omits 'partial'
                        (data.js L568) but ordersReserving includes it (L1176);
                        'partial' orders still reserve their remaining
                        allocations, so it is INCLUDED here.
            free      = qty - reserved (floored at 0; only for status='available')
            allocatable = available AND NOT expired AND free > 0
   PERF   : rides ix_wmslpn_site_status_product (02 script — "the worklist /
            SoH / allocation hot path"). */
IF OBJECT_ID(N'dbo.wmsrpt_soh', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_soh;
GO
CREATE PROCEDURE dbo.wmsrpt_soh
    @userid   INT,                        -- host Users.Id (server-injected)
    @siteid   INT,                        -- mandatory site filter
    @clientid INT           = NULL,       -- optional client filter
    @areaid   INT           = NULL,       -- optional storage-area filter
    @q        NVARCHAR(100) = NULL,       -- matches LPN code / lot / product name / SKU
    @status   VARCHAR(20)   = 'onhand'    -- onhand|available|allocatable|blocked|expired
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    /* ---- CC-08 scope resolution -------------------------------------- */
    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile
    WHERE userid = @userid;

    IF @allsites IS NULL RETURN;   -- not a WMS-enabled user → no rows

    IF @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;                    -- requested site out of scope → no rows

    /* ---- the report rows ---------------------------------------------- */
    SELECT
        l.id                AS lpnid,
        l.code              AS lpncode,
        l.lot,
        l.expiry,
        l.status,
        l.qty,
        r.reservedqty,
        CASE WHEN l.status = 'available'
             THEN CASE WHEN l.qty - r.reservedqty < 0 THEN 0
                       ELSE l.qty - r.reservedqty END
             ELSE NULL END  AS freeqty,
        CASE WHEN l.status IN ('quarantine','hold','damaged','expired')
             THEN 1 ELSE 0 END AS isblocked,
        CASE WHEN l.expiry IS NOT NULL AND l.expiry < @today
             THEN 1 ELSE 0 END AS isexpired,
        l.clientid,
        c.name              AS clientname,
        l.productid,
        p.sku,
        p.name              AS productname,
        p.baseuom,
        p.tracklot,
        p.trackexpiry,
        l.locationid,
        loc.structuredcode  AS locationcode,
        a.code              AS areacode,
        a.name              AS areaname
    FROM dbo.wmslpn l
    JOIN dbo.wmsclient  c   ON c.id   = l.clientid
    JOIN dbo.wmsproduct p   ON p.id   = l.productid
    JOIN dbo.wmslocation loc ON loc.id = l.locationid
    LEFT JOIN dbo.wmsstoragearea a ON a.id = loc.areaid
    OUTER APPLY (
        SELECT ISNULL(SUM(al.qty), 0) AS reservedqty
        FROM dbo.wmsallocation al
        JOIN dbo.wmsoutboundline ol ON ol.id = al.outboundlineid
        JOIN dbo.wmsoutbound     o  ON o.id  = ol.outboundid
        WHERE al.lpnid = l.id
          AND o.status IN ('allocated','picking','picked','partial')
    ) r
    WHERE l.qty > 0                              -- on-hand = physically present
      AND l.siteid = @siteid
      AND (@clientid IS NULL OR l.clientid = @clientid)
      AND (@areaid   IS NULL OR loc.areaid = @areaid)
      AND (@allclients = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                      WHERE uc.userid = @userid AND uc.clientid = l.clientid))
      AND (@q IS NULL OR @q = N''
           OR l.code LIKE '%' + @q + '%'
           OR l.lot  LIKE N'%' + @q + N'%'
           OR p.name LIKE N'%' + @q + N'%'
           OR p.sku  LIKE '%' + @q + '%')
      AND (   @status = 'onhand'
           OR (@status = 'available'
               AND l.status = 'available'
               AND NOT (l.expiry IS NOT NULL AND l.expiry < @today))
           OR (@status = 'allocatable'
               AND l.status = 'available'
               AND NOT (l.expiry IS NOT NULL AND l.expiry < @today)
               AND (l.qty - r.reservedqty) > 0)
           OR (@status = 'blocked'
               AND l.status IN ('quarantine','hold','damaged','expired'))
           OR (@status = 'expired'
               AND l.expiry IS NOT NULL AND l.expiry < @today)
          )
    ORDER BY c.name, p.name,
             ISNULL(l.expiry, CONVERT(DATETIME2, '9999-12-31')),
             l.code;
END
GO

/* wmsrpt_txns ----------------------------------------------------------------
   SCREEN : erp-rpt-txns.html  (Reports › Transaction History / Stock Ledger;
            card RPT-TXNS-SCREEN).
   PURPOSE: The audit / reconciliation backbone — chronological rows from the
            append-only dbo.wmstxn ledger (every stock mutation writes one row;
            BLOCKING_RULES: an action that writes no audit row is a bug).
            Newest first. The FRONTEND computes the KPI buckets
            (in / out / move / adjust) from the returned rows.
   RULES  : mirrors the mock —
            date window : @fromdate/@todate inclusive (ts DATETIME2; @todate
                          bound is < @todate + 1 day). The screen always sends
                          a bounded window (default: last 30 days).
            search @q   : LPN code / ref / note (the mock's haystack).
            client      : wmstxn has NO clientid — the owning client derives
                          from the product (wmsproduct.clientid), like the
                          mock's clientOf(). Rows with NO product cannot be
                          client-attributed: they are returned only to
                          allclients=1 users and excluded when @clientid is set.
            scope CC-08 : allsites=0  → only rows whose siteid is in the user's
                          wmsusersite set (NULL-site rows hidden);
                          allclients=0 → only rows whose derived client is in
                          the user's wmsuserclient set (NULL-product rows hidden).
            row cap     : TOP (@maxrows), newest first (PERFORMANCE_RULES —
                          capped ranges; the screen shows a "range capped"
                          hint when exactly @maxrows rows return).
   PERF   : rides ix_wmstxn_ts (chronological) / ix_wmstxn_type_site. */
IF OBJECT_ID(N'dbo.wmsrpt_txns', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_txns;
GO
CREATE PROCEDURE dbo.wmsrpt_txns
    @userid    INT,                        -- host Users.Id (server-injected)
    @fromdate  DATE          = NULL,       -- inclusive (screen default: today - 30d)
    @todate    DATE          = NULL,       -- inclusive
    @type      VARCHAR(20)   = NULL,       -- one of the ck_wmstxn_type values, or NULL = all
    @siteid    INT           = NULL,       -- optional site filter
    @clientid  INT           = NULL,       -- optional client filter (derived via product)
    @productid INT           = NULL,       -- optional product filter
    @q         NVARCHAR(100) = NULL,       -- matches LPN code / ref / note
    @maxrows   INT           = 5000        -- hard row cap, newest first
AS
BEGIN
    SET NOCOUNT ON;

    /* ---- CC-08 scope resolution -------------------------------------- */
    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile
    WHERE userid = @userid;

    IF @allsites IS NULL RETURN;   -- not a WMS-enabled user → no rows

    IF @siteid IS NOT NULL AND @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;                    -- requested site out of scope → no rows

    /* ---- the ledger rows ---------------------------------------------- */
    SELECT TOP (@maxrows)
        t.id             AS txnid,
        t.code           AS txncode,
        t.ts,
        t.type,
        t.lpnid,
        l.code           AS lpncode,
        t.productid,
        p.sku,
        p.name           AS productname,
        p.clientid,
        c.name           AS clientname,
        t.qty,                                -- signed for adjustments
        t.fromlocationid,
        lf.structuredcode AS fromlocation,
        t.tolocationid,
        lt.structuredcode AS tolocation,
        t.siteid,
        s.name           AS sitename,
        t.userid,
        ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(u.FirstName, N'') + N' ' + ISNULL(u.LastName, N''))), N''),
               u.UserName) AS username,
        t.ref,
        t.note
    FROM dbo.wmstxn t
    LEFT JOIN dbo.wmslpn      l  ON l.id  = t.lpnid
    LEFT JOIN dbo.wmsproduct  p  ON p.id  = t.productid
    LEFT JOIN dbo.wmsclient   c  ON c.id  = p.clientid
    LEFT JOIN dbo.wmslocation lf ON lf.id = t.fromlocationid
    LEFT JOIN dbo.wmslocation lt ON lt.id = t.tolocationid
    LEFT JOIN dbo.wmssite     s  ON s.id  = t.siteid
    LEFT JOIN dbo.[Users]     u  ON u.[Id] = t.userid
    WHERE (@fromdate IS NULL OR t.ts >= @fromdate)
      AND (@todate   IS NULL OR t.ts < DATEADD(DAY, 1, @todate))
      AND (@type      IS NULL OR @type = '' OR t.type = @type)
      AND (@siteid    IS NULL OR t.siteid = @siteid)
      AND (@productid IS NULL OR t.productid = @productid)
      AND (@clientid  IS NULL OR p.clientid = @clientid)
      AND (@allsites = 1
           OR (t.siteid IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.wmsusersite us
                           WHERE us.userid = @userid AND us.siteid = t.siteid)))
      AND (@allclients = 1
           OR (p.clientid IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                           WHERE uc.userid = @userid AND uc.clientid = p.clientid)))
      AND (@q IS NULL OR @q = N''
           OR l.code LIKE '%' + @q + '%'
           OR t.ref  LIKE N'%' + @q + N'%'
           OR t.note LIKE N'%' + @q + N'%')
    ORDER BY t.ts DESC, t.id DESC;
END
GO

/* wmsrpt_expiry --------------------------------------------------------------
   SCREEN : erp-rpt-expiry.html  (Reports › Expiry & Aging; card RPT-EXPIRY-SCREEN).
   PURPOSE: Expiry-centric stock health — one flat row per ON-HAND plate at the
            site (qty > 0, any status) with the expiry BUCKET, days-to-expiry,
            and AGING (days in stock since the plate's earliest 'receive' txn).
            Returns the FULL site/client/product scope (all buckets, incl.
            'none' = non-expiry products): the screen applies the bucket filter
            client-side because its KPI tiles are computed on the UNBUCKETED
            scope (mock behaviour — KPIs ignore the bucket filter).
   RULES  : mirrors erp-rpt-expiry.html —
            bucket   : 'none'    product doesn't track expiry / no expiry date
                       'expired' days-to-expiry < 0
                       'b30' 0–30 · 'b60' 31–60 · 'b90' 61–90 · 'ok' 90+
            received : MIN(ts) of the plate's wmstxn 'receive' rows (NULL if none)
            agedays  : days from received to today (slow/dead stock ≥ 180 —
                       a SCREEN highlight, not filtered here)
   PERF   : rides ix_wmslpn_site_status_product + ix_wmstxn_lpn. */
IF OBJECT_ID(N'dbo.wmsrpt_expiry', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_expiry;
GO
CREATE PROCEDURE dbo.wmsrpt_expiry
    @userid    INT,                       -- host Users.Id (server-injected)
    @siteid    INT,                       -- mandatory site filter
    @clientid  INT = NULL,                -- optional client filter
    @productid INT = NULL                 -- optional product filter
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    /* ---- CC-08 scope resolution -------------------------------------- */
    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile
    WHERE userid = @userid;

    IF @allsites IS NULL RETURN;

    IF @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;

    /* ---- the report rows ---------------------------------------------- */
    SELECT
        l.id                AS lpnid,
        l.code              AS lpncode,
        l.lot,
        l.expiry,
        CASE WHEN p.trackexpiry = 1 AND l.expiry IS NOT NULL
             THEN DATEDIFF(DAY, @today, CAST(l.expiry AS DATE))
             ELSE NULL END  AS daystoexpiry,
        CASE WHEN p.trackexpiry = 0 OR l.expiry IS NULL THEN 'none'
             WHEN DATEDIFF(DAY, @today, CAST(l.expiry AS DATE)) < 0  THEN 'expired'
             WHEN DATEDIFF(DAY, @today, CAST(l.expiry AS DATE)) <= 30 THEN 'b30'
             WHEN DATEDIFF(DAY, @today, CAST(l.expiry AS DATE)) <= 60 THEN 'b60'
             WHEN DATEDIFF(DAY, @today, CAST(l.expiry AS DATE)) <= 90 THEN 'b90'
             ELSE 'ok' END  AS bucket,
        l.status,
        l.qty,
        l.locationid,
        loc.structuredcode  AS locationcode,
        rcv.receivedat,
        CASE WHEN rcv.receivedat IS NOT NULL
             THEN DATEDIFF(DAY, CAST(rcv.receivedat AS DATE), @today)
             ELSE NULL END  AS agedays,
        l.clientid,
        c.name              AS clientname,
        l.productid,
        p.sku,
        p.name              AS productname,
        p.baseuom,
        p.trackexpiry
    FROM dbo.wmslpn l
    JOIN dbo.wmsclient   c   ON c.id   = l.clientid
    JOIN dbo.wmsproduct  p   ON p.id   = l.productid
    JOIN dbo.wmslocation loc ON loc.id = l.locationid
    OUTER APPLY (
        SELECT MIN(t.ts) AS receivedat
        FROM dbo.wmstxn t
        WHERE t.lpnid = l.id AND t.type = 'receive'
    ) rcv
    WHERE l.qty > 0
      AND l.siteid = @siteid
      AND (@clientid  IS NULL OR l.clientid  = @clientid)
      AND (@productid IS NULL OR l.productid = @productid)
      AND (@allclients = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                      WHERE uc.userid = @userid AND uc.clientid = l.clientid))
    ORDER BY ISNULL(l.expiry, CONVERT(DATETIME2, '9999-12-31')), l.code;
END
GO

/* wmsrpt_inbound -------------------------------------------------------------
   SCREEN : erp-rpt-inbound.html  (Reports › Inbound / Receipts; card
            RPT-INBOUND-SCREEN).
   PURPOSE: Receipt completeness — ONE row per ASN with expected vs received
            rollups, line counts, derived lifecycle status and the over-receipt
            flag. The screen groups by client and computes the KPI tiles from
            the returned (filtered) rows.
   RULES  : mirrors mockups/assets/data.js asnTotals/asnStatus (L548/L554) —
            expected/received : SUM over wmsasnline qty / received
            linescomplete     : lines where received >= qty
            status (DERIVED, never stored) :
                a.state ('cancelled'/'refused') when set — the only persisted
                lifecycle override; else rec <= 0 → 'open';
                every line received >= qty → 'closed'; else 'partial'
            hasover           : any line received > qty (over-receipt tag)
            @status filter    : matches the DERIVED status ('open'|'partial'|
                                'closed'|'cancelled'|'refused'; NULL = all)
            @q                : ASN code OR a line product's name/sku
            @fromdate/@todate : optional window on wmsasn.expectedat ("by
                                period" per 06_Reports; the v1 screen does not
                                expose it — mock parity — params are ready)
   PERF   : ix_wmsasn_site_client + ix_wmsasnline_asn. */
IF OBJECT_ID(N'dbo.wmsrpt_inbound', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_inbound;
GO
CREATE PROCEDURE dbo.wmsrpt_inbound
    @userid   INT,                        -- host Users.Id (server-injected)
    @siteid   INT           = NULL,       -- optional (mock default: all sites)
    @clientid INT           = NULL,       -- optional client filter
    @status   VARCHAR(20)   = NULL,       -- derived status, NULL = all
    @q        NVARCHAR(100) = NULL,       -- ASN code / line product name / SKU
    @fromdate DATE          = NULL,       -- optional window on expectedat
    @todate   DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /* ---- CC-08 scope resolution -------------------------------------- */
    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile
    WHERE userid = @userid;

    IF @allsites IS NULL RETURN;

    IF @siteid IS NOT NULL AND @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;

    SELECT
        x.asnid, x.asncode, x.siteid, x.sitename, x.clientid, x.clientname,
        x.supplierid, x.suppliername, x.deliveryref, x.expectedat, x.note,
        x.lines, x.linescomplete, x.expected, x.received,
        CASE WHEN x.expected - x.received > 0
             THEN x.expected - x.received ELSE 0 END AS outstanding,
        CASE WHEN x.expected > 0
             THEN CAST(ROUND(x.received * 100.0 / x.expected, 0) AS INT)
             ELSE 0 END AS fillpct,
        x.derivedstatus, x.hasover
    FROM (
        SELECT
            a.id            AS asnid,
            a.code          AS asncode,
            a.siteid,
            s.name          AS sitename,
            a.clientid,
            c.name          AS clientname,
            a.supplierid,
            sup.name        AS suppliername,
            a.deliveryref,
            a.expectedat,
            a.note,
            ISNULL(ln.lines, 0)         AS lines,
            ISNULL(ln.linescomplete, 0) AS linescomplete,
            ISNULL(ln.expected, 0)      AS expected,
            ISNULL(ln.received, 0)      AS received,
            CASE WHEN a.state IS NOT NULL          THEN a.state
                 WHEN ISNULL(ln.received, 0) <= 0  THEN 'open'
                 WHEN ISNULL(ln.lines, 0) > 0
                      AND ln.linescomplete = ln.lines THEN 'closed'
                 ELSE 'partial' END     AS derivedstatus,
            ISNULL(ln.hasover, 0)       AS hasover
        FROM dbo.wmsasn a
        JOIN dbo.wmsclient  c   ON c.id  = a.clientid
        JOIN dbo.wmssite    s   ON s.id  = a.siteid
        LEFT JOIN dbo.wmssupplier sup ON sup.id = a.supplierid
        OUTER APPLY (
            SELECT COUNT(*)                                        AS lines,
                   SUM(CASE WHEN al.received >= al.qty THEN 1 ELSE 0 END) AS linescomplete,
                   SUM(al.qty)                                     AS expected,
                   SUM(al.received)                                AS received,
                   MAX(CASE WHEN al.received > al.qty THEN 1 ELSE 0 END)  AS hasover
            FROM dbo.wmsasnline al
            WHERE al.asnid = a.id
        ) ln
        WHERE (@siteid   IS NULL OR a.siteid   = @siteid)
          AND (@clientid IS NULL OR a.clientid = @clientid)
          AND (@fromdate IS NULL OR a.expectedat >= @fromdate)
          AND (@todate   IS NULL OR a.expectedat < DATEADD(DAY, 1, @todate))
          AND (@allsites = 1
               OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                          WHERE us.userid = @userid AND us.siteid = a.siteid))
          AND (@allclients = 1
               OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                          WHERE uc.userid = @userid AND uc.clientid = a.clientid))
          AND (@q IS NULL OR @q = N''
               OR a.code LIKE '%' + @q + '%'
               OR EXISTS (SELECT 1 FROM dbo.wmsasnline al2
                          JOIN dbo.wmsproduct p2 ON p2.id = al2.productid
                          WHERE al2.asnid = a.id
                            AND (p2.name LIKE N'%' + @q + N'%'
                                 OR p2.sku LIKE '%' + @q + '%')))
    ) x
    WHERE (@status IS NULL OR @status = '' OR x.derivedstatus = @status)
    ORDER BY x.clientname, x.asncode;
END
GO

/* wmsrpt_outbound ------------------------------------------------------------
   SCREEN : erp-rpt-outbound.html  (Reports › Outbound / Shipments; card
            RPT-OUTBOUND-SCREEN).
   PURPOSE: Fulfilment performance — ONE row per outbound order with ordered /
            allocated / shipped / remaining rollups, the short flag and the
            client's remainder policy. The screen groups by client and computes
            the KPI tiles from the returned rows.
   RULES  : mirrors mockups/assets/data.js outTotals (L612) — per NON-CANCELLED
            line: req = qty, EXCEPT full-stock-out orders where req = the line's
            LIVE allocated qty (qty is NULL by design); allc = SUM of live
            wmsallocation rows (they are DELETED at dispatch — an allocated
            column of 0 on a dispatched order is correct); ship = cumulative
            wmsoutboundline.shipped; remaining = max(0, req - ship);
            short = any line allc < req. Fulfilment tag = SCREEN logic
            (short-closed / complete / back-ordered / short stock) from
            status + shortclosed + these rollups.
            allowbackorder (wmsclient) = the client's remainder policy shown on
            the group header ('back-order' vs 'short-close').
            @status matches wmsoutbound.status; 'cancelled' orders return only
            when @status IS NULL (mock: visible under All, own badge).
   PERF   : ix_wmsoutbound_site_status + ix_wmsoutboundline_outbound +
            ix_wmsallocation_line. */
IF OBJECT_ID(N'dbo.wmsrpt_outbound', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_outbound;
GO
CREATE PROCEDURE dbo.wmsrpt_outbound
    @userid   INT,                        -- host Users.Id (server-injected)
    @fromdate DATE          = NULL,       -- window on createdat (screen default: last 30d)
    @todate   DATE          = NULL,
    @clientid INT           = NULL,
    @siteid   INT           = NULL,
    @status   VARCHAR(20)   = NULL        -- wmsoutbound.status, NULL = all
AS
BEGIN
    SET NOCOUNT ON;

    /* ---- CC-08 scope resolution -------------------------------------- */
    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile
    WHERE userid = @userid;

    IF @allsites IS NULL RETURN;

    IF @siteid IS NOT NULL AND @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;

    SELECT
        o.id             AS outboundid,
        o.code           AS outboundcode,
        o.ref,
        o.createdat,
        o.status,
        o.shortclosed,
        o.fullstockout,
        o.dispatchedat,
        o.note,
        o.clientid,
        c.name           AS clientname,
        c.allowbackorder,
        o.siteid,
        s.name           AS sitename,
        ISNULL(t.linecount, 0)  AS lines,
        ISNULL(t.req, 0)        AS ordered,
        ISNULL(t.allc, 0)       AS allocated,
        ISNULL(t.ship, 0)       AS shipped,
        CASE WHEN ISNULL(t.req,0) - ISNULL(t.ship,0) > 0
             THEN ISNULL(t.req,0) - ISNULL(t.ship,0) ELSE 0 END AS remaining,
        ISNULL(t.short, 0)      AS isshort
    FROM dbo.wmsoutbound o
    JOIN dbo.wmsclient c ON c.id = o.clientid
    JOIN dbo.wmssite   s ON s.id = o.siteid
    OUTER APPLY (
        SELECT COUNT(*)     AS linecount,
               SUM(lr.req)  AS req,
               SUM(lr.allc) AS allc,
               SUM(lr.ship) AS ship,
               MAX(CASE WHEN lr.allc < lr.req THEN 1 ELSE 0 END) AS short
        FROM (
            SELECT CASE WHEN o.fullstockout = 1 THEN ISNULL(al.allc, 0)
                        ELSE ISNULL(ol.qty, 0) END AS req,
                   ISNULL(al.allc, 0) AS allc,
                   ol.shipped         AS ship
            FROM dbo.wmsoutboundline ol
            OUTER APPLY (
                SELECT SUM(a.qty) AS allc
                FROM dbo.wmsallocation a
                WHERE a.outboundlineid = ol.id
            ) al
            WHERE ol.outboundid = o.id
              AND ol.cancelled = 0          -- cancelled lines excluded from totals
        ) lr
    ) t
    WHERE (@fromdate IS NULL OR o.createdat >= @fromdate)
      AND (@todate   IS NULL OR o.createdat < DATEADD(DAY, 1, @todate))
      AND (@clientid IS NULL OR o.clientid = @clientid)
      AND (@siteid   IS NULL OR o.siteid   = @siteid)
      AND (@status   IS NULL OR @status = '' OR o.status = @status)
      AND (@allsites = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                      WHERE us.userid = @userid AND us.siteid = o.siteid))
      AND (@allclients = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                      WHERE uc.userid = @userid AND uc.clientid = o.clientid))
    ORDER BY c.name, o.createdat DESC, o.code;
END
GO

/* wmsrpt_variance ------------------------------------------------------------
   SCREEN : erp-rpt-variance.html  (Reports › Adjustments & Variances; card
            RPT-VARIANCE-SCREEN).
   PURPOSE: The inventory-accuracy / shrinkage feed — a NORMALIZED UNION of the
            four variance sources, newest first:
              'adjustment'  wmsadjustment kind='qty'  (signed delta)
              'correction'  wmsadjustment kind='correct' (variance 0 + a
                            field-change summary built via FOR XML PATH)
              'count'       wmscountline rows where counted <> system
              'physical'    wmsphysicalline counted rows where counted <> system
            The screen builds its Reason dropdown from the returned rows and
            filters reason CLIENT-SIDE (mock parity); KPIs use the normalized
            "applied" bit.
   RULES  : dates = ISNULL(postedat, createdat) / count: ISNULL(approvedat,
            countedat, createdat) / physical: ISNULL(closedat, createdat).
            applied (NORMALIZED — ⚠ deliberate fix of a mock inconsistency:
            the mock's applied-list ['posted','approved'] misses physicals):
              adjustment/correction → status = 'posted'
              count                 → status = 'approved'
              physical              → status = 'closed' AND abandoned = 0
            pending: adjustment 'pending' · count 'counted'/'pending-approval'
            · physical 'open'/'frozen'.
            Client attribution: adjustments carry clientid; count/physical
            lines derive it from the product (productid is NOT NULL on both).
   PERF   : ix_wmsadjustment_site_status · ix_wmscountline_loc ·
            ix_wmsphysicalline_loc. */
IF OBJECT_ID(N'dbo.wmsrpt_variance', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_variance;
GO
CREATE PROCEDURE dbo.wmsrpt_variance
    @userid   INT,                        -- host Users.Id (server-injected)
    @fromdate DATE        = NULL,         -- window on the per-source event date
    @todate   DATE        = NULL,
    @type     VARCHAR(20) = NULL,         -- adjustment|correction|count|physical, NULL = all
    @clientid INT         = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /* ---- CC-08 scope resolution -------------------------------------- */
    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile
    WHERE userid = @userid;

    IF @allsites IS NULL RETURN;

    SELECT *
    FROM (
        /* 1) quantity adjustments ------------------------------------- */
        SELECT 'adjustment'  AS source,
               a.code        AS ref,
               ISNULL(a.postedat, a.createdat) AS eventdate,
               a.clientid, c.name AS clientname,
               a.siteid,   s.name AS sitename,
               a.productid, p.sku, p.name AS productname,
               l.code AS lpncode, l.lot,
               CASE WHEN a.dir = 'decrease' THEN -ISNULL(a.delta,0)
                    ELSE ISNULL(a.delta,0) END AS variance,
               ISNULL(r.reasontext, ISNULL(a.reasontext, N'—')) AS reason,
               CAST(NULL AS NVARCHAR(MAX)) AS changesummary,
               a.status,
               CASE WHEN a.status = 'posted' THEN 1 ELSE 0 END AS applied,
               CAST(NULL AS NVARCHAR(80)) AS locationcode
        FROM dbo.wmsadjustment a
        JOIN dbo.wmsclient  c ON c.id = a.clientid
        JOIN dbo.wmssite    s ON s.id = a.siteid
        JOIN dbo.wmsproduct p ON p.id = a.productid
        JOIN dbo.wmslpn     l ON l.id = a.lpnid
        LEFT JOIN dbo.wmsreason r ON r.id = a.reasonid
        WHERE a.kind = 'qty'

        UNION ALL

        /* 2) attribute corrections ------------------------------------ */
        SELECT 'correction', a.code, ISNULL(a.postedat, a.createdat),
               a.clientid, c.name, a.siteid, s.name,
               a.productid, p.sku, p.name,
               l.code, l.lot,
               CAST(0 AS DECIMAL(18,3)),
               ISNULL(r.reasontext, ISNULL(a.reasontext, N'—')),
               STUFF((SELECT N', ' + ch.field + N': ' + ISNULL(ch.fromvalue, N'')
                             + N' -> ' + ISNULL(ch.tovalue, N'')
                      FROM dbo.wmsadjustmentchange ch
                      WHERE ch.adjustmentid = a.id
                      FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'),
                     1, 2, N''),
               a.status,
               CASE WHEN a.status = 'posted' THEN 1 ELSE 0 END,
               CAST(NULL AS NVARCHAR(80))
        FROM dbo.wmsadjustment a
        JOIN dbo.wmsclient  c ON c.id = a.clientid
        JOIN dbo.wmssite    s ON s.id = a.siteid
        JOIN dbo.wmsproduct p ON p.id = a.productid
        JOIN dbo.wmslpn     l ON l.id = a.lpnid
        LEFT JOIN dbo.wmsreason r ON r.id = a.reasonid
        WHERE a.kind = 'correct'

        UNION ALL

        /* 3) cycle-count variances (one row per plate line with a delta) */
        SELECT 'count', cnt.code,
               ISNULL(cnt.approvedat, ISNULL(cnt.countedat, cnt.createdat)),
               p.clientid, c.name, cnt.siteid, s.name,
               cl.productid, p.sku, p.name,
               l.code, cl.lot,
               cl.countedqty - cl.systemqty,
               N'Cycle-count variance',
               CAST(NULL AS NVARCHAR(MAX)),
               cnt.status,
               CASE WHEN cnt.status = 'approved' THEN 1 ELSE 0 END,
               loc.structuredcode
        FROM dbo.wmscountline cl
        JOIN dbo.wmscountlocation cloc ON cloc.id = cl.countlocationid
        JOIN dbo.wmscount    cnt ON cnt.id = cloc.countid
        JOIN dbo.wmslocation loc ON loc.id = cloc.locationid
        JOIN dbo.wmsproduct  p   ON p.id   = cl.productid
        JOIN dbo.wmsclient   c   ON c.id   = p.clientid
        JOIN dbo.wmssite     s   ON s.id   = cnt.siteid
        LEFT JOIN dbo.wmslpn l   ON l.id   = cl.lpnid
        WHERE cl.countedqty <> cl.systemqty

        UNION ALL

        /* 4) physical-inventory variances (counted lines with a delta) - */
        SELECT 'physical', ph.code,
               ISNULL(ph.closedat, ph.createdat),
               p.clientid, c.name, ph.siteid, s.name,
               pl.productid, p.sku, p.name,
               l.code, pl.lot,
               pl.countedqty - pl.systemqty,
               N'Stock-take variance',
               CAST(NULL AS NVARCHAR(MAX)),
               ph.status,
               CASE WHEN ph.status = 'closed' AND ph.abandoned = 0
                    THEN 1 ELSE 0 END,
               loc.structuredcode
        FROM dbo.wmsphysicalline pl
        JOIN dbo.wmsphysicallocation ploc ON ploc.id = pl.physicallocationid
        JOIN dbo.wmsphysical ph  ON ph.id  = ploc.physicalid
        JOIN dbo.wmslocation loc ON loc.id = ploc.locationid
        JOIN dbo.wmsproduct  p   ON p.id   = pl.productid
        JOIN dbo.wmsclient   c   ON c.id   = p.clientid
        JOIN dbo.wmssite     s   ON s.id   = ph.siteid
        LEFT JOIN dbo.wmslpn l   ON l.id   = pl.lpnid
        WHERE pl.countedqty IS NOT NULL
          AND pl.countedqty <> pl.systemqty
    ) v
    WHERE (@fromdate IS NULL OR v.eventdate >= @fromdate)
      AND (@todate   IS NULL OR v.eventdate < DATEADD(DAY, 1, @todate))
      AND (@type     IS NULL OR @type = '' OR v.source = @type)
      AND (@clientid IS NULL OR v.clientid = @clientid)
      AND (@allsites = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                      WHERE us.userid = @userid AND us.siteid = v.siteid))
      AND (@allclients = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                      WHERE uc.userid = @userid AND uc.clientid = v.clientid))
    ORDER BY v.eventdate DESC, v.ref;
END
GO

/* wmsrpt_utilization ----------------------------------------------------------
   SCREEN : erp-rpt-utilization.html  (Reports › Bin / Location Utilization;
            card RPT-UTIL-SCREEN).
   PURPOSE: Slotting health — ONE row per STORAGE bin at the site (EMPTY bins
            included) with live occupancy (plates / units / weight) against the
            bin's declared capacity limits and the tightest-limit fill %.
            Returns the FULL site/area scope: the screen applies the
            utilization filter (occupied/empty/near/full) client-side because
            its KPI tiles are computed on the unfiltered scope (mock parity).
   RULES  : mirrors mockups/assets/data.js binLoad (L655) + the screen's
            fillPct (L85) —
            load     : plates with qty > 0 at the bin, EXCLUDING 'in-transit'
                       (physically gone); weight = qty × product.weightkg
                       (NULL weight counts 0, mock unitWeight fallback)
            fillpct  : MAX over the DECLARED limits only (units/maxunits,
                       weight/maxweightkg, plates/maxlpns) × 100; NULL when the
                       bin declares no limit ("unbounded")
            status   : SCREEN logic (empty / ok / near ≥80 / full ≥100 / over)
            ⚠ CLIENT SCOPE DEVIATION (deliberate, documented): bin load counts
            ALL plates regardless of the caller's client scope — space
            occupancy is a physical/ops metric, not client-owned data (no
            client identity is returned). Only SITE scope applies (CC-08).
   PERF   : ix_wmslocation_siteid + ix_wmslpn_location. */
IF OBJECT_ID(N'dbo.wmsrpt_utilization', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_utilization;
GO
CREATE PROCEDURE dbo.wmsrpt_utilization
    @userid INT,                          -- host Users.Id (server-injected)
    @siteid INT,                          -- mandatory site filter
    @areaid INT = NULL                    -- optional storage-area filter
AS
BEGIN
    SET NOCOUNT ON;

    /* ---- CC-08 scope resolution (site only — see header note) -------- */
    DECLARE @allsites BIT;
    SELECT @allsites = allsites
    FROM dbo.wmsuserprofile
    WHERE userid = @userid;

    IF @allsites IS NULL RETURN;

    IF @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;

    SELECT u.*
    FROM (
        SELECT
            loc.id              AS locationid,
            loc.code            AS locationsysid,
            loc.structuredcode  AS locationcode,
            loc.status          AS locationstatus,
            a.code              AS areacode,
            a.name              AS areaname,
            ISNULL(ld.plates, 0)   AS plates,
            ISNULL(ld.units, 0)    AS units,
            ISNULL(ld.weightkg, 0) AS weightkg,
            loc.maxunits,
            loc.maxweightkg,
            loc.maxlpns,
            CASE WHEN loc.maxunits IS NULL AND loc.maxweightkg IS NULL AND loc.maxlpns IS NULL
                 THEN NULL
                 ELSE CAST(ROUND((
                     SELECT MAX(ratio) FROM (VALUES
                         (CASE WHEN loc.maxunits    IS NOT NULL AND loc.maxunits    > 0
                               THEN ISNULL(ld.units, 0)    / loc.maxunits    ELSE NULL END),
                         (CASE WHEN loc.maxweightkg IS NOT NULL AND loc.maxweightkg > 0
                               THEN ISNULL(ld.weightkg, 0) / loc.maxweightkg ELSE NULL END),
                         (CASE WHEN loc.maxlpns     IS NOT NULL AND loc.maxlpns     > 0
                               THEN CAST(ISNULL(ld.plates, 0) AS DECIMAL(18,3)) / loc.maxlpns ELSE NULL END)
                     ) AS x(ratio)) * 100, 0) AS INT)
                 END AS fillpct
        FROM dbo.wmslocation loc
        LEFT JOIN dbo.wmsstoragearea a ON a.id = loc.areaid
        OUTER APPLY (
            SELECT COUNT(*)                                   AS plates,
                   SUM(l.qty)                                 AS units,
                   SUM(l.qty * ISNULL(p.weightkg, 0))         AS weightkg
            FROM dbo.wmslpn l
            JOIN dbo.wmsproduct p ON p.id = l.productid
            WHERE l.locationid = loc.id
              AND l.qty > 0
              AND l.status <> 'in-transit'   -- physically gone still takes no space
        ) ld
        WHERE loc.type = 'storage'
          AND loc.siteid = @siteid
          AND (@areaid IS NULL OR loc.areaid = @areaid)
    ) u
    ORDER BY CASE WHEN u.fillpct IS NULL THEN -1 ELSE u.fillpct END DESC,
             u.locationcode;
END
GO

/* wmsrpt_trace_lots ------------------------------------------------------------
   SCREEN : erp-rpt-trace.html (the Lot dropdown) + erp-rpt-stockcard.html (the
            Lot/batch dropdown) — shared lookup.
   PURPOSE: Distinct lots present on plates (any qty, incl. history plates),
            optionally narrowed by product. CC-08 scoped. */
IF OBJECT_ID(N'dbo.wmsrpt_trace_lots', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_trace_lots;
GO
CREATE PROCEDURE dbo.wmsrpt_trace_lots
    @userid    INT,
    @productid INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile WHERE userid = @userid;
    IF @allsites IS NULL RETURN;

    SELECT DISTINCT l.lot, l.productid, p.sku, p.name AS productname
    FROM dbo.wmslpn l
    JOIN dbo.wmsproduct p ON p.id = l.productid
    WHERE l.lot IS NOT NULL AND l.lot <> N''
      AND (@productid IS NULL OR l.productid = @productid)
      AND (@allsites = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                      WHERE us.userid = @userid AND us.siteid = l.siteid))
      AND (@allclients = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                      WHERE uc.userid = @userid AND uc.clientid = l.clientid))
    ORDER BY l.lot;
END
GO

/* wmsrpt_trace_plates ----------------------------------------------------------
   SCREEN : erp-rpt-trace.html (Reports › Lot / Serial Traceability; card
            RPT-TRACE-SCREEN) — the "Plates carrying this lot / serial" panel +
            the subject header + KPIs.
   PURPOSE: The plates matching a trace subject: @mode='lot' → plates whose lot
            equals @lot (split/repack children inherit the lot, so genealogy is
            covered by the match itself); @mode='serial' → plates having a
            wmslpnserial row matching @serial (substring, mock parity). Includes
            zero-qty (fully issued) plates — a recall must see history.
   NOTE   : wmsrpt_trace_events applies the SAME subject predicate — keep the
            two WHERE clauses in sync when editing. */
IF OBJECT_ID(N'dbo.wmsrpt_trace_plates', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_trace_plates;
GO
CREATE PROCEDURE dbo.wmsrpt_trace_plates
    @userid    INT,
    @mode      VARCHAR(10),               -- 'lot' | 'serial'
    @productid INT           = NULL,      -- optional narrowing (lot mode)
    @lot       NVARCHAR(60)  = NULL,
    @serial    VARCHAR(80)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile WHERE userid = @userid;
    IF @allsites IS NULL RETURN;
    IF (@mode = 'lot'    AND (@lot    IS NULL OR @lot    = N'')) RETURN;
    IF (@mode = 'serial' AND (@serial IS NULL OR @serial = ''))  RETURN;

    SELECT
        l.id   AS lpnid,
        l.code AS lpncode,
        l.lot,
        l.expiry,
        l.status,
        l.qty,
        l.parentlpnid,
        pl.code AS parentlpncode,          -- genealogy hint (split/repack source)
        l.clientid,  c.name AS clientname,
        l.productid, p.sku, p.name AS productname, p.baseuom,
        l.siteid,    s.name AS sitename,
        l.locationid, loc.structuredcode AS locationcode
    FROM dbo.wmslpn l
    JOIN dbo.wmsclient   c   ON c.id   = l.clientid
    JOIN dbo.wmsproduct  p   ON p.id   = l.productid
    JOIN dbo.wmssite     s   ON s.id   = l.siteid
    JOIN dbo.wmslocation loc ON loc.id = l.locationid
    LEFT JOIN dbo.wmslpn pl  ON pl.id  = l.parentlpnid
    WHERE ((@mode = 'lot'
            AND l.lot = @lot
            AND (@productid IS NULL OR l.productid = @productid))
        OR (@mode = 'serial'
            AND EXISTS (SELECT 1 FROM dbo.wmslpnserial ls
                        WHERE ls.lpnid = l.id
                          AND ls.serial LIKE '%' + @serial + '%')))
      AND (@allsites = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                      WHERE us.userid = @userid AND us.siteid = l.siteid))
      AND (@allclients = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                      WHERE uc.userid = @userid AND uc.clientid = l.clientid))
    ORDER BY l.code;
END
GO

/* wmsrpt_trace_events ----------------------------------------------------------
   SCREEN : erp-rpt-trace.html — the Event timeline (chronological ASC).
   PURPOSE: Every wmstxn row of the subject's plates (same predicate as
            wmsrpt_trace_plates — keep in sync). Recall walk: receive →
            putaway → move → … → dispatch/return. */
IF OBJECT_ID(N'dbo.wmsrpt_trace_events', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_trace_events;
GO
CREATE PROCEDURE dbo.wmsrpt_trace_events
    @userid    INT,
    @mode      VARCHAR(10),               -- 'lot' | 'serial'
    @productid INT           = NULL,
    @lot       NVARCHAR(60)  = NULL,
    @serial    VARCHAR(80)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile WHERE userid = @userid;
    IF @allsites IS NULL RETURN;
    IF (@mode = 'lot'    AND (@lot    IS NULL OR @lot    = N'')) RETURN;
    IF (@mode = 'serial' AND (@serial IS NULL OR @serial = ''))  RETURN;

    SELECT
        t.id   AS txnid,
        t.code AS txncode,
        t.ts,
        t.type,
        t.lpnid,
        l.code AS lpncode,
        t.qty,
        lf.structuredcode AS fromlocation,
        lt.structuredcode AS tolocation,
        t.siteid, s.name AS sitename,
        ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(u.FirstName, N'') + N' ' + ISNULL(u.LastName, N''))), N''),
               u.UserName) AS username,
        t.ref,
        t.note
    FROM dbo.wmstxn t
    JOIN dbo.wmslpn l ON l.id = t.lpnid
    LEFT JOIN dbo.wmslocation lf ON lf.id = t.fromlocationid
    LEFT JOIN dbo.wmslocation lt ON lt.id = t.tolocationid
    LEFT JOIN dbo.wmssite     s  ON s.id  = t.siteid
    LEFT JOIN dbo.[Users]     u  ON u.[Id] = t.userid
    WHERE ((@mode = 'lot'
            AND l.lot = @lot
            AND (@productid IS NULL OR l.productid = @productid))
        OR (@mode = 'serial'
            AND EXISTS (SELECT 1 FROM dbo.wmslpnserial ls
                        WHERE ls.lpnid = l.id
                          AND ls.serial LIKE '%' + @serial + '%')))
      AND (@allsites = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                      WHERE us.userid = @userid AND us.siteid = l.siteid))
      AND (@allclients = 1
           OR EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                      WHERE uc.userid = @userid AND uc.clientid = l.clientid))
    ORDER BY t.ts ASC, t.id ASC;
END
GO

/* wmsrpt_stockcard ------------------------------------------------------------
   SCREEN : erp-rpt-stockcard.html  (Reports › Stock Card / Product Ledger;
            card RPT-STOCKCARD-SCREEN).
   PURPOSE: The FULL chronological ledger of ONE product (optionally one lot /
            one site) with a signed delta and a RUNNING BALANCE per row,
            anchored to live on-hand: opening = onhand_now − Σ(deltas), so the
            forward walk ends exactly at current stock (mock parity). The
            screen's date / direction filters are DISPLAY-side — the balance
            needs the full history, so this proc takes NO date params.
   RULES  : deltas per the ON-HAND-CHANGING TYPE MAP in this file's header.
            ⚠ Improvement over the mock: adjust/count/repack rows use the
            SIGNED wmstxn.qty (the 02-schema convention) — the mock's
            note-text adjSign() heuristic is NOT reproduced.
            Ledger rows keyed by productid; rows with a plate outside the
            lot/site scope are excluded, rows with NO plate (doc-level) stay
            (mock parity). openingbalance / currentonhand repeat on every row
            (single result set — the screen reads them off row 1).
   PERF   : ix_wmstxn_lpn + ix_wmslpn_site_status_product; one product's
            history — bounded in practice (PERFORMANCE_RULES). */
IF OBJECT_ID(N'dbo.wmsrpt_stockcard', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_stockcard;
GO
CREATE PROCEDURE dbo.wmsrpt_stockcard
    @userid    INT,
    @productid INT,                       -- mandatory
    @lot       NVARCHAR(60) = NULL,       -- optional single-lot ledger
    @siteid    INT          = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile WHERE userid = @userid;
    IF @allsites IS NULL RETURN;

    /* the product's owning client must be in scope */
    IF @allclients = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsproduct p
                       JOIN dbo.wmsuserclient uc ON uc.clientid = p.clientid
                       WHERE p.id = @productid AND uc.userid = @userid)
        RETURN;
    IF @siteid IS NOT NULL AND @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;

    /* current on-hand over the scope plates (incl. any status — mock parity) */
    DECLARE @onhand DECIMAL(18,3) =
        (SELECT ISNULL(SUM(l.qty), 0)
         FROM dbo.wmslpn l
         WHERE l.productid = @productid
           AND (@lot    IS NULL OR ISNULL(l.lot, N'') = @lot)
           AND (@siteid IS NULL OR l.siteid = @siteid)
           AND (@allsites = 1
                OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                           WHERE us.userid = @userid AND us.siteid = l.siteid)));

    /* the ledger with signed deltas */
    SELECT
        x.*,
        @onhand                                       AS currentonhand,
        @onhand - SUM(x.delta) OVER ()                AS openingbalance,
        (@onhand - SUM(x.delta) OVER ())
          + SUM(x.delta) OVER (ORDER BY x.ts, x.txnid
                               ROWS UNBOUNDED PRECEDING) AS runningbalance
    FROM (
        SELECT
            t.id   AS txnid,
            t.code AS txncode,
            t.ts,
            t.type,
            CASE WHEN t.type IN ('receive','transfer-receive','return')            THEN 'in'
                 WHEN t.type IN ('dispatch','transfer-ship','transfer-loss','dispose','rtv') THEN 'out'
                 WHEN t.type IN ('adjust','count','repack')                        THEN 'adj'
                 ELSE 'internal' END AS direction,
            CASE WHEN t.type IN ('receive','transfer-receive','return')            THEN  ISNULL(t.qty, 0)
                 WHEN t.type IN ('dispatch','transfer-ship','transfer-loss','dispose','rtv') THEN -ISNULL(t.qty, 0)
                 WHEN t.type IN ('adjust','count','repack')                        THEN  ISNULL(t.qty, 0)  -- SIGNED by convention
                 ELSE 0 END AS delta,
            t.qty,
            t.lpnid,
            l.code AS lpncode,
            l.lot  AS lpnlot,
            lf.structuredcode AS fromlocation,
            lt.structuredcode AS tolocation,
            t.siteid, s.name AS sitename,
            ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(u.FirstName, N'') + N' ' + ISNULL(u.LastName, N''))), N''),
                   u.UserName) AS username,
            t.ref,
            t.note
        FROM dbo.wmstxn t
        LEFT JOIN dbo.wmslpn      l  ON l.id  = t.lpnid
        LEFT JOIN dbo.wmslocation lf ON lf.id = t.fromlocationid
        LEFT JOIN dbo.wmslocation lt ON lt.id = t.tolocationid
        LEFT JOIN dbo.wmssite     s  ON s.id  = t.siteid
        LEFT JOIN dbo.[Users]     u  ON u.[Id] = t.userid
        WHERE t.productid = @productid
          /* plate-scoped rows must match the lot/site narrowing; plate-less rows stay */
          AND (t.lpnid IS NULL
               OR ((@lot    IS NULL OR ISNULL(l.lot, N'') = @lot)
                   AND (@siteid IS NULL OR l.siteid = @siteid)
                   AND (@allsites = 1
                        OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                                   WHERE us.userid = @userid AND us.siteid = l.siteid))))
    ) x
    ORDER BY x.ts ASC, x.txnid ASC;
END
GO

/* wmsrpt_statement ------------------------------------------------------------
   SCREEN : erp-rpt-statement.html  (Reports › Client Stock Statement; card
            RPT-STATEMENT-SCREEN).
   PURPOSE: The 3PL accountability statement — ONE row per product of ONE
            client: opening → receipts → issues → adjustments → closing over a
            period. Closing = LIVE on-hand (qty > 0, excluding 'in-transit' —
            mock parity); opening is DERIVED (closing − rec + iss − adj) so
            every line reconciles by construction. All-zero lines are skipped.
   RULES  : buckets per the ON-HAND-CHANGING TYPE MAP in this file's header —
            Receipts = IN types · Issues = OUT types (as positive numbers) ·
            Adjustments = ADJ types with SIGNED qty (no note heuristic).
            Site filter: LPNs by siteid; txn rows with a NULL siteid pass a
            site filter (mock parity — doc-level events can't be site-pinned).
   PERF   : ix_wmsproduct_clientid + ix_wmstxn_ts. */
IF OBJECT_ID(N'dbo.wmsrpt_statement', N'P') IS NOT NULL
    DROP PROCEDURE dbo.wmsrpt_statement;
GO
CREATE PROCEDURE dbo.wmsrpt_statement
    @userid   INT,
    @clientid INT,                        -- mandatory
    @siteid   INT  = NULL,
    @fromdate DATE = NULL,                -- period (screen default: month start)
    @todate   DATE = NULL                 -- inclusive; NULL = today
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @allsites BIT, @allclients BIT;
    SELECT @allsites = allsites, @allclients = allclients
    FROM dbo.wmsuserprofile WHERE userid = @userid;
    IF @allsites IS NULL RETURN;

    IF @allclients = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsuserclient uc
                       WHERE uc.userid = @userid AND uc.clientid = @clientid)
        RETURN;
    IF @siteid IS NOT NULL AND @allsites = 0
       AND NOT EXISTS (SELECT 1 FROM dbo.wmsusersite us
                       WHERE us.userid = @userid AND us.siteid = @siteid)
        RETURN;

    SELECT
        x.productid, x.sku, x.productname, x.baseuom,
        x.closing - x.receipts + x.issues - x.adjustments AS opening,
        x.receipts,
        x.issues,
        x.adjustments,
        x.closing
    FROM (
        SELECT
            p.id   AS productid,
            p.sku,
            p.name AS productname,
            p.baseuom,
            ISNULL(oh.closing, 0)   AS closing,
            ISNULL(tx.receipts, 0)  AS receipts,
            ISNULL(tx.issues, 0)    AS issues,
            ISNULL(tx.adjustments, 0) AS adjustments
        FROM dbo.wmsproduct p
        OUTER APPLY (
            SELECT SUM(l.qty) AS closing
            FROM dbo.wmslpn l
            WHERE l.productid = p.id
              AND l.clientid  = @clientid
              AND l.qty > 0
              AND l.status <> 'in-transit'
              AND (@siteid IS NULL OR l.siteid = @siteid)
              AND (@allsites = 1
                   OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                              WHERE us.userid = @userid AND us.siteid = l.siteid))
        ) oh
        OUTER APPLY (
            SELECT
                SUM(CASE WHEN t.type IN ('receive','transfer-receive','return')
                         THEN ISNULL(t.qty, 0) ELSE 0 END) AS receipts,
                SUM(CASE WHEN t.type IN ('dispatch','transfer-ship','transfer-loss','dispose','rtv')
                         THEN ISNULL(t.qty, 0) ELSE 0 END) AS issues,
                SUM(CASE WHEN t.type IN ('adjust','count','repack')
                         THEN ISNULL(t.qty, 0) ELSE 0 END) AS adjustments   -- SIGNED by convention
            FROM dbo.wmstxn t
            WHERE t.productid = p.id
              AND (@fromdate IS NULL OR t.ts >= @fromdate)
              AND (@todate   IS NULL OR t.ts < DATEADD(DAY, 1, @todate))
              AND (t.siteid IS NULL                       -- doc-level rows pass (mock parity)
                   OR ((@siteid IS NULL OR t.siteid = @siteid)
                       AND (@allsites = 1
                            OR EXISTS (SELECT 1 FROM dbo.wmsusersite us
                                       WHERE us.userid = @userid AND us.siteid = t.siteid))))
        ) tx
        WHERE p.clientid = @clientid
    ) x
    WHERE NOT (x.closing = 0 AND x.receipts = 0 AND x.issues = 0 AND x.adjustments = 0
               AND x.closing - x.receipts + x.issues - x.adjustments = 0)
    ORDER BY x.productname;
END
GO

/* ============================================================================
   END — report procedures (idempotent). Applied additions (append newest last):
     2026-07-06  dbo.wmsrpt_soh         (Stock on Hand — card RPT-SOH-BACKEND)
     2026-07-06  dbo.wmsrpt_txns        (Transaction History — card RPT-TXNS-BACKEND)
     2026-07-06  dbo.wmsrpt_expiry      (Expiry & Aging — card RPT-EXPIRY-BACKEND)
     2026-07-06  dbo.wmsrpt_inbound     (Inbound / Receipts — card RPT-INBOUND-BACKEND)
     2026-07-06  dbo.wmsrpt_outbound    (Outbound / Shipments — card RPT-OUTBOUND-BACKEND)
     2026-07-06  dbo.wmsrpt_variance    (Adjustments & Variances — card RPT-VARIANCE-BACKEND)
     2026-07-06  dbo.wmsrpt_utilization (Bin / Location Utilization — card RPT-UTIL-BACKEND)
     2026-07-06  dbo.wmsrpt_trace_lots + _plates + _events (Traceability — card RPT-TRACE-BACKEND)
     2026-07-06  dbo.wmsrpt_stockcard   (Stock Card / Product Ledger — card RPT-STOCKCARD-BACKEND)
     2026-07-06  dbo.wmsrpt_statement   (Client Stock Statement — card RPT-STATEMENT-BACKEND)
   ============================================================================ */
