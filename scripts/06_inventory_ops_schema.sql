use dms_11
go
/* ============================================================================
   WMS (3PL) — DATABASE SCHEMA
   SECTION 06: INVENTORY OPERATIONS  —  THE LAST TABLE SET
               (tables only — NO views, NO procedures)
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Module        : WMS — client-owned stock in a 3PL warehouse
   Run order     : AFTER 01 (master data), 02 (goods reception + shared core)
                   AND 05 (stock-out — wmsreturn FKs wmsoutbound). Then run
                   06_inventory_ops_seed.sql (the 'dispose' reason domain).

   WHY THIS FILE IS "THE LAST SCRIPT"
   ----------------------------------
   With this file every WMS section has its DDL:
     01 Master Data (29) · 02 Goods Reception + shared core (16) ·
     03 Putaway (0 — operates on 02's tables) · 04 Stock visibility (0 — SoH is
     DERIVED from wmslpn, per the locked Phase-0 decision) · 05 Stock-Out (10) ·
     06 THIS FILE (18) · 07 Reports (0 — reads wmstxn/wmslpn).
   The shared 02 CHECKs already carry every value these tables emit
   (wmslpn.status 'disposed'/'lost'; wmstxn.type 'move','transfer-ship',
   'transfer-receive','transfer-loss','transfer-cancel','adjust','correct',
   'count','status','repack','return','dispose','park') — this file ADDS TABLES
   ONLY and never ALTERs a shipped CHECK.

   CROSS-SECTION CONSUMERS (why parts of this file are needed OUTSIDE Inv-Ops)
   ---------------------------------------------------------------------------
   * GROUP A (wmsphysical*) is the **freeze guard's data (CC-01)**: Putaway
     slotting (card PUT-02), Stock-Out allocation (card SO-06), dispatch
     re-validation (C1), Move and Transfer-ship all refuse a location inside an
     ACTIVE FROZEN stock-take. `IFreezeService` resolves it with ONE query:
       a location L is frozen ⇔ EXISTS (wmsphysical p JOIN wmsphysicallocation
       pl ON pl.physicalid = p.id WHERE p.status = 'frozen' AND pl.locationid = L)
     (the take's scope is DEFINITIVE in its wmsphysicallocation rows — a
     site-scope take enumerates every location at freeze time).
   * GROUP B (wmscount*) receives the **"stock not found at pick"** auto-raised
     sheets (F8): the Stock-Out dispatch/express commits mint a single-line
     pending-approval count with source='pick-not-found' (flagCountForMissing).
   * GROUP G (wmsreturn*) closes the outbound loop (put-back / customer return
     → stock re-enters via direct restock or the Putaway queue).

   TABLE GROUPS (18)
   -----------------
     GROUP A — Physical Inventory (freeze→count→post):
               wmsphysical, wmsphysicallocation, wmsphysicalline
     GROUP B — Cycle Count (no freeze, approval-gated):
               wmscount, wmscountlocation, wmscountline
     GROUP C — Stock Move (intra-site, immediate):        wmsmove
     GROUP D — Transfer Order (inter-site, in-transit):   wmstransfer, wmstransferline
     GROUP E — Adjustment / Correction (approval-gated):  wmsadjustment, wmsadjustmentchange
     GROUP F — Repack / Split / Merge / Re-kit:           wmsrepack, wmsrepacksource, wmsrepackoutput
     GROUP G — Return / Put-back:                         wmsreturn, wmsreturnline, wmsreturnlineserial
     GROUP H — Disposal / scrap-out (terminal):           wmsdisposal

   KEY DESIGN DECISIONS
   --------------------
   * Serials: return lines capture serials BEFORE a plate exists →
     wmsreturnlineserial (mirrors wmsreceiptlineserial). Transfers move WHOLE
     plates (partial → Repack first) and repack outputs mint NEW plates — in
     both cases serials stay on / move to wmslpnserial, so NO transfer/repack
     serial child tables (documented decision; count serial-level capture is a
     flagged production gap in DATA_MODEL — same posture here).
   * "Found" stock on a count/physical line = lpnid NULL (no system plate);
     posting mints a plate recorded in mintedlpnid. A counted-0 line on a
     system plate = "missing" (plate zeroed at post).
   * Maker-checker (F13): approval-gated documents (count, adjustment,
     disposal) must be approved by a DIFFERENT user than the raiser — an APP
     rule (compare approvedby vs createdby), not DDL.
   * wmsmove uses COMPOSITE location FKs (locationid, siteid) so both ends are
     DDL-bound to the move's own site (intra-site by construction).
   * Blocking rules (BLOCKING_RULES.md rows: Move / Transfer / Count Approval /
     Physical Inventory / Repack / Returns) are APP LOGIC at commit; the DDL
     persists what they decide.

   CONVENTIONS HONOURED (identical to 01/02/05)
   --------------------------------------------
   * Lower-case wms-prefixed tables; id INT IDENTITY(1,1) PK; business ids
     (PHY-, CNT-, MOV-, TRF-, ADJ-, RPK-, RET-, DSP-) in a unique "code" column.
   * DECIMAL(18,3) qtys · DATETIME2 dates · VARCHAR+CHECK enums · audit columns
     on aggregate roots only · user refs INT, NOT FK-bound ([dbo].[Users]) ·
     IF OBJECT_ID guards, NO DROPs, no 2016+ features.

   HOW TO RUN
   ----------
   USE [WMS];  -- (or the per-agency DMS_xx database)
   -- run 01, 02, 05 schema files first, then this file, then 06_inventory_ops_seed.sql.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   GROUP A — PHYSICAL INVENTORY  (freeze → count → reconcile → unfreeze)
   ============================================================================ */

/* wmsphysical ------------------------------------------------------------------
   SCREEN : erp-inv-physical.html + pwa-inv-physical.html.
   PURPOSE: A stock-take event over a whole SITE or one AREA. Lifecycle
            open -> frozen -> closed. While status='frozen' every location in
            its wmsphysicallocation rows is LOCKED — Putaway, Move,
            Transfer-ship and Allocation refuse it (CC-01; the cross-section
            IFreezeService query in the header). "scope"='area' pins the take
            to storageareaid; either way the location rows are enumerated at
            creation and are the definitive scope. Post (only when every
            location is counted) corrects each plate to countedqty, then
            unfreezes (status='closed'). Abandon unfreezes with NO corrections
            (abandoned=1, still 'closed'). "assignee" = work-item owner (CC-09).
            No overlapping active takes per location (app rule at creation). */
IF OBJECT_ID(N'dbo.wmsphysical', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsphysical (
        id             INT IDENTITY(1,1) NOT NULL,
        code           VARCHAR(40)   NOT NULL,   -- business key e.g. 'PHY-7001'
        siteid         INT           NOT NULL,
        scope          VARCHAR(10)   NOT NULL CONSTRAINT df_wmsphysical_scope DEFAULT ('site'),
        storageareaid  INT           NULL,        -- set when scope='area'
        status         VARCHAR(20)   NOT NULL CONSTRAINT df_wmsphysical_status DEFAULT ('open'),
        abandoned      BIT           NOT NULL CONSTRAINT df_wmsphysical_abandoned DEFAULT (0),
        frozenat       DATETIME2     NULL,        -- when the freeze was applied
        closedat       DATETIME2     NULL,
        closedby       INT           NULL,        -- -> [dbo].[Users].[Id]
        assignee       INT           NULL,        -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        note           NVARCHAR(400) NULL,
        createdby      INT           NULL,
        createdat      DATETIME2     NULL,
        editby         INT           NULL,
        edittime       DATETIME2     NULL,
        CONSTRAINT pk_wmsphysical PRIMARY KEY (id),
        CONSTRAINT uq_wmsphysical_code UNIQUE (code),
        CONSTRAINT ck_wmsphysical_scope  CHECK (scope IN ('site','area')),
        CONSTRAINT ck_wmsphysical_status CHECK (status IN ('open','frozen','closed')),
        -- an area-scope take MUST name its area; a site-scope take must not (no ambiguous scope).
        CONSTRAINT ck_wmsphysical_areascope CHECK (
            (scope = 'area' AND storageareaid IS NOT NULL) OR
            (scope = 'site' AND storageareaid IS NULL)),
        CONSTRAINT fk_wmsphysical_site FOREIGN KEY (siteid) REFERENCES dbo.wmssite (id),
        -- composite FK: the take's area must belong to the take's OWN site (uq_wmsstoragearea_idsite in 01).
        CONSTRAINT fk_wmsphysical_area FOREIGN KEY (storageareaid, siteid) REFERENCES dbo.wmsstoragearea (id, siteid)
    );
    CREATE INDEX ix_wmsphysical_site_status ON dbo.wmsphysical (siteid, status);
END
GO

/* wmsphysicallocation ------------------------------------------------------------
   PURPOSE: One location inside a take — the DEFINITIVE freeze scope and the
            per-bin count progress ('pending' -> 'counted'; Post is gated until
            none are pending). ix on locationid serves the hot IFreezeService
            lookup. Pure child table — no audit columns. */
IF OBJECT_ID(N'dbo.wmsphysicallocation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsphysicallocation (
        id          INT           IDENTITY(1,1) NOT NULL,
        physicalid  INT           NOT NULL,
        locationid  INT           NOT NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmsphysicallocation_status DEFAULT ('pending'),
        countedby   INT           NULL,        -- -> [dbo].[Users].[Id]
        countedat   DATETIME2     NULL,
        CONSTRAINT pk_wmsphysicallocation PRIMARY KEY (id),
        CONSTRAINT uq_wmsphysicallocation UNIQUE (physicalid, locationid),
        CONSTRAINT ck_wmsphysicallocation_status CHECK (status IN ('pending','counted')),
        CONSTRAINT fk_wmsphysicallocation_physical FOREIGN KEY (physicalid) REFERENCES dbo.wmsphysical (id),
        CONSTRAINT fk_wmsphysicallocation_location FOREIGN KEY (locationid) REFERENCES dbo.wmslocation (id)
    );
    CREATE INDEX ix_wmsphysicallocation_location ON dbo.wmsphysicallocation (locationid);  -- IFreezeService hot path
END
GO

/* wmsphysicalline ----------------------------------------------------------------
   PURPOSE: One plate expected/counted at a take location. lpnid NULL = a FOUND
            line (stock physically present with no system plate — posting mints
            one, recorded in mintedlpnid). countedqty NULL until counted; a
            counted 0 on a system plate = MISSING (plate zeroed at post).
            Pure child table. */
IF OBJECT_ID(N'dbo.wmsphysicalline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsphysicalline (
        id                  INT           IDENTITY(1,1) NOT NULL,
        physicallocationid  INT           NOT NULL,
        lpnid               INT           NULL,        -- NULL = found line (no system plate)
        productid           INT           NOT NULL,
        lot                 NVARCHAR(60)  NULL,
        systemqty           DECIMAL(18,3) NOT NULL CONSTRAINT df_wmsphysicalline_sys DEFAULT (0),
        countedqty          DECIMAL(18,3) NULL,        -- NULL until counted
        mintedlpnid         INT           NULL,        -- plate minted at post for a found line
        CONSTRAINT pk_wmsphysicalline PRIMARY KEY (id),
        CONSTRAINT fk_wmsphysicalline_loc     FOREIGN KEY (physicallocationid) REFERENCES dbo.wmsphysicallocation (id),
        CONSTRAINT fk_wmsphysicalline_lpn     FOREIGN KEY (lpnid)              REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsphysicalline_product FOREIGN KEY (productid)          REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsphysicalline_minted  FOREIGN KEY (mintedlpnid)        REFERENCES dbo.wmslpn (id)
    );
    CREATE INDEX ix_wmsphysicalline_loc ON dbo.wmsphysicalline (physicallocationid);
    CREATE INDEX ix_wmsphysicalline_lpn ON dbo.wmsphysicalline (lpnid);
END
GO

/* ============================================================================
   GROUP B — CYCLE COUNT  (no freeze; one sheet = one approval decision)
   ============================================================================ */

/* wmscount ---------------------------------------------------------------------
   SCREEN : erp-inv-count.html + pwa-inv-count.html; ALSO auto-raised by the
            Stock-Out dispatch/express "Stock not found at pick" flow (F8 —
            flagCountForMissing) with source='pick-not-found'.
   PURPOSE: One count SHEET spanning one or many locations (no freeze — the
            frozen full take is GROUP A). variance = countedqty − systemqty per
            line; ONE approval corrects stock across every location on the
            sheet (approve sets each plate qty = countedqty; found lines mint;
            missing lines zero). Lifecycle counted -> pending-approval ->
            approved | rejected. Maker-checker: approver ≠ counter (app rule).
            Bulk-approve is gated by the largest plate-level |Δ| (app rule). */
IF OBJECT_ID(N'dbo.wmscount', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmscount (
        id          INT           IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'CNT-9001'
        siteid      INT           NOT NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmscount_status DEFAULT ('counted'),
        source      VARCHAR(30)   NULL,        -- NULL = manual | 'pick-not-found' (F8 auto-raise)
        countedby   INT           NULL,        -- -> [dbo].[Users].[Id]
        countedat   DATETIME2     NULL,
        approvedby  INT           NULL,        -- -> [dbo].[Users].[Id] (≠ countedby — app rule F13)
        approvedat  DATETIME2     NULL,
        assignee    INT           NULL,        -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        note        NVARCHAR(400) NULL,
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmscount PRIMARY KEY (id),
        CONSTRAINT uq_wmscount_code UNIQUE (code),
        CONSTRAINT ck_wmscount_status CHECK (status IN ('counted','pending-approval','approved','rejected')),
        CONSTRAINT fk_wmscount_site FOREIGN KEY (siteid) REFERENCES dbo.wmssite (id)
    );
    CREATE INDEX ix_wmscount_site_status ON dbo.wmscount (siteid, status);
END
GO

/* wmscountlocation ---------------------------------------------------------------
   PURPOSE: One counted location on a sheet (a sheet covers many bins — model
            change of 2026-06-17). Pure child table. */
IF OBJECT_ID(N'dbo.wmscountlocation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmscountlocation (
        id          INT  IDENTITY(1,1) NOT NULL,
        countid     INT  NOT NULL,
        locationid  INT  NOT NULL,
        CONSTRAINT pk_wmscountlocation PRIMARY KEY (id),
        CONSTRAINT uq_wmscountlocation UNIQUE (countid, locationid),
        CONSTRAINT fk_wmscountlocation_count    FOREIGN KEY (countid)    REFERENCES dbo.wmscount (id),
        CONSTRAINT fk_wmscountlocation_location FOREIGN KEY (locationid) REFERENCES dbo.wmslocation (id)
    );
END
GO

/* wmscountline -------------------------------------------------------------------
   PURPOSE: One plate count at a bin. lpnid NULL + found=1 = FOUND stock (needs
            product + qty>0; approve mints a plate -> mintedlpnid); counted 0 on
            a system plate = missing (zeroed at approve). Serial-level counting
            is a flagged production gap (DATA_MODEL) — quantities only here.
            Pure child table. */
IF OBJECT_ID(N'dbo.wmscountline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmscountline (
        id               INT           IDENTITY(1,1) NOT NULL,
        countlocationid  INT           NOT NULL,
        lpnid            INT           NULL,        -- NULL = found line
        productid        INT           NOT NULL,
        lot              NVARCHAR(60)  NULL,
        systemqty        DECIMAL(18,3) NOT NULL CONSTRAINT df_wmscountline_sys DEFAULT (0),
        countedqty       DECIMAL(18,3) NOT NULL,
        found            BIT           NOT NULL CONSTRAINT df_wmscountline_found DEFAULT (0),
        mintedlpnid      INT           NULL,        -- plate minted at approve for a found line
        CONSTRAINT pk_wmscountline PRIMARY KEY (id),
        CONSTRAINT fk_wmscountline_loc     FOREIGN KEY (countlocationid) REFERENCES dbo.wmscountlocation (id),
        CONSTRAINT fk_wmscountline_lpn     FOREIGN KEY (lpnid)           REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmscountline_product FOREIGN KEY (productid)       REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmscountline_minted  FOREIGN KEY (mintedlpnid)     REFERENCES dbo.wmslpn (id)
    );
    CREATE INDEX ix_wmscountline_loc ON dbo.wmscountline (countlocationid);
    CREATE INDEX ix_wmscountline_lpn ON dbo.wmscountline (lpnid);
END
GO

/* ============================================================================
   GROUP C — STOCK MOVE  (intra-site relocation; immediate, no approval)
   ============================================================================ */

/* wmsmove ----------------------------------------------------------------------
   SCREEN : erp-inv-transfer.html (Move tab) + pwa-inv-move.html.
   PURPOSE: location -> location within ONE site; posting sets wmslpn.loc and
            logs a 'move' wmstxn. A PARTIAL move splits first (child plate
            minted — conservation), then the child moves. COMPOSITE FKs bind
            BOTH ends to the move's own site — intra-site by construction.
            Guards (app, BLOCKING_RULES): same site different location, qty
            0<q≤plate, not in-transit, neither end frozen, destination passes
            capacity + segregation. */
IF OBJECT_ID(N'dbo.wmsmove', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsmove (
        id              INT           IDENTITY(1,1) NOT NULL,
        code            VARCHAR(40)   NOT NULL,   -- business key e.g. 'MOV-6001'
        siteid          INT           NOT NULL,
        lpnid           INT           NOT NULL,   -- the plate moved (post-split child on partials)
        productid       INT           NOT NULL,
        qty             DECIMAL(18,3) NOT NULL,
        fromlocationid  INT           NOT NULL,
        tolocationid    INT           NOT NULL,
        status          VARCHAR(20)   NOT NULL CONSTRAINT df_wmsmove_status DEFAULT ('done'),
        movedby         INT           NULL,        -- -> [dbo].[Users].[Id]
        movedat         DATETIME2     NULL,
        note            NVARCHAR(400) NULL,
        createdby       INT           NULL,
        createdat       DATETIME2     NULL,
        editby          INT           NULL,
        edittime        DATETIME2     NULL,
        CONSTRAINT pk_wmsmove PRIMARY KEY (id),
        CONSTRAINT uq_wmsmove_code UNIQUE (code),
        CONSTRAINT ck_wmsmove_status CHECK (status IN ('done')),
        CONSTRAINT fk_wmsmove_site    FOREIGN KEY (siteid)    REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsmove_lpn     FOREIGN KEY (lpnid)     REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsmove_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id),
        -- composite FKs: both ends MUST belong to the move's site (intra-site by DDL).
        CONSTRAINT fk_wmsmove_fromloc FOREIGN KEY (fromlocationid, siteid) REFERENCES dbo.wmslocation (id, siteid),
        CONSTRAINT fk_wmsmove_toloc   FOREIGN KEY (tolocationid, siteid)   REFERENCES dbo.wmslocation (id, siteid)
    );
    CREATE INDEX ix_wmsmove_site ON dbo.wmsmove (siteid);
    CREATE INDEX ix_wmsmove_lpn  ON dbo.wmsmove (lpnid);
END
GO

/* ============================================================================
   GROUP D — TRANSFER ORDER  (inter-site, with an in-transit state)
   ============================================================================ */

/* wmstransfer ------------------------------------------------------------------
   SCREEN : erp-inv-transfer.html + pwa-inv-transfer.html.
   PURPOSE: Site A -> Site B, whole plates only (partials go through Repack
            first). draft -> in-transit (Ship: plates -> 'in-transit',
            'transfer-ship' txns) -> received (per line: plate site/loc set,
            'available', 'transfer-receive' txn) | cancelled (draft only).
            Receive destinations pass capacity + segregation + not-frozen (the
            shared checks). "assignee" = work-item owner (keys off fromsite). */
IF OBJECT_ID(N'dbo.wmstransfer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmstransfer (
        id            INT           IDENTITY(1,1) NOT NULL,
        code          VARCHAR(40)   NOT NULL,   -- business key e.g. 'TRF-8001'
        clientid      INT           NULL,        -- stock owner (single-client transfers in v1)
        fromsiteid    INT           NOT NULL,
        tositeid      INT           NOT NULL,
        status        VARCHAR(20)   NOT NULL CONSTRAINT df_wmstransfer_status DEFAULT ('draft'),
        shippedat     DATETIME2     NULL,
        shippedby     INT           NULL,        -- -> [dbo].[Users].[Id]
        receivedat    DATETIME2     NULL,
        receivedby    INT           NULL,        -- -> [dbo].[Users].[Id]
        cancelreason  NVARCHAR(200) NULL,
        cancelledby   INT           NULL,        -- -> [dbo].[Users].[Id]
        cancelledat   DATETIME2     NULL,
        assignee      INT           NULL,        -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        note          NVARCHAR(400) NULL,
        createdby     INT           NULL,
        createdat     DATETIME2     NULL,
        editby        INT           NULL,
        edittime      DATETIME2     NULL,
        CONSTRAINT pk_wmstransfer PRIMARY KEY (id),
        CONSTRAINT uq_wmstransfer_code UNIQUE (code),
        CONSTRAINT ck_wmstransfer_status CHECK (status IN ('draft','in-transit','received','cancelled')),
        CONSTRAINT ck_wmstransfer_sites  CHECK (fromsiteid <> tositeid),
        CONSTRAINT fk_wmstransfer_client   FOREIGN KEY (clientid)   REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmstransfer_fromsite FOREIGN KEY (fromsiteid) REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmstransfer_tosite   FOREIGN KEY (tositeid)   REFERENCES dbo.wmssite (id)
    );
    CREATE INDEX ix_wmstransfer_fromsite ON dbo.wmstransfer (fromsiteid, status);
    CREATE INDEX ix_wmstransfer_tosite   ON dbo.wmstransfer (tositeid, status);
END
GO

/* wmstransferline ----------------------------------------------------------------
   PURPOSE: One WHOLE plate on a transfer. lot/expiry are display snapshots (the
            plate carries the truth and its serials — no serial child here, see
            header decision). "recvlocationid" = the destination bin chosen per
            line at receipt (must belong to tositeid — app rule). "lostqty" =
            in-transit loss written off at receive ('transfer-loss' txn; plate
            -> 'lost' when the whole plate vanished). Pure child table. */
IF OBJECT_ID(N'dbo.wmstransferline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmstransferline (
        id              INT           IDENTITY(1,1) NOT NULL,
        transferid      INT           NOT NULL,
        [lineno]          INT           NOT NULL,
        lpnid           INT           NOT NULL,
        productid       INT           NOT NULL,
        qty             DECIMAL(18,3) NOT NULL,    -- whole-plate qty at ship
        lot             NVARCHAR(60)  NULL,
        expiry          DATETIME2     NULL,
        recvlocationid  INT           NULL,        -- destination bin (chosen at receive)
        lostqty         DECIMAL(18,3) NOT NULL CONSTRAINT df_wmstransferline_lost DEFAULT (0),
        CONSTRAINT pk_wmstransferline PRIMARY KEY (id),
        CONSTRAINT uq_wmstransferline_lineno UNIQUE (transferid, [lineno]),
        CONSTRAINT uq_wmstransferline_lpn    UNIQUE (transferid, lpnid),
        CONSTRAINT fk_wmstransferline_transfer FOREIGN KEY (transferid)     REFERENCES dbo.wmstransfer (id),
        CONSTRAINT fk_wmstransferline_lpn      FOREIGN KEY (lpnid)          REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmstransferline_product  FOREIGN KEY (productid)      REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmstransferline_recvloc  FOREIGN KEY (recvlocationid) REFERENCES dbo.wmslocation (id)
    );
    CREATE INDEX ix_wmstransferline_transfer ON dbo.wmstransferline (transferid);
    CREATE INDEX ix_wmstransferline_lpn      ON dbo.wmstransferline (lpnid);
END
GO

/* ============================================================================
   GROUP E — ADJUSTMENT / CORRECTION  (approval-gated; two kinds, one table)
   ============================================================================ */

/* wmsadjustment ----------------------------------------------------------------
   SCREEN : erp-inv-adjust.html (ERP-only — back-office, not dispatched).
   PURPOSE: kind='qty' (quantity delta, dir increase|decrease, posting sets
            plate qty = afterqty) | kind='correct' (attribute correction —
            child wmsadjustmentchange rows; posting writes each field to the
            plate). pending -> posted | rejected; approval applies the
            mutation, reject applies nothing; approver ≠ raiser (F13, app).
            Production note (DATA_MODEL): before-values snapshot at raise time
            — RE-VALIDATE against live qty at approval. Reasons from the
            'adjust'/'correct' domains (seeded in 01). */
IF OBJECT_ID(N'dbo.wmsadjustment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsadjustment (
        id          INT           IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'ADJ-5001'
        kind        VARCHAR(10)   NOT NULL,   -- 'qty' | 'correct'
        clientid    INT           NOT NULL,
        siteid      INT           NOT NULL,
        lpnid       INT           NOT NULL,   -- target plate
        productid   INT           NOT NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmsadjustment_status DEFAULT ('pending'),
        reasonid    INT           NULL,        -- -> wmsreason ('adjust' or 'correct' domain)
        reasontext  NVARCHAR(200) NULL,        -- free-text fallback
        note        NVARCHAR(400) NULL,
        dir         VARCHAR(10)   NULL,        -- qty kind: 'increase' | 'decrease'
        beforeqty   DECIMAL(18,3) NULL,        -- qty kind: snapshot at raise
        delta       DECIMAL(18,3) NULL,        -- qty kind: unsigned delta
        afterqty    DECIMAL(18,3) NULL,        -- qty kind: posting writes this to the plate
        approvedby  INT           NULL,        -- -> [dbo].[Users].[Id] (≠ createdby — app rule F13)
        postedat    DATETIME2     NULL,        -- set when approved (posted)
        createdby   INT           NULL,        -- the raiser
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmsadjustment PRIMARY KEY (id),
        CONSTRAINT uq_wmsadjustment_code UNIQUE (code),
        CONSTRAINT ck_wmsadjustment_kind   CHECK (kind IN ('qty','correct')),
        CONSTRAINT ck_wmsadjustment_status CHECK (status IN ('pending','posted','rejected')),
        CONSTRAINT ck_wmsadjustment_dir    CHECK (dir IS NULL OR dir IN ('increase','decrease')),
        -- a qty adjustment must carry its numbers + direction:
        CONSTRAINT ck_wmsadjustment_qtykind CHECK (kind <> 'qty'
            OR (dir IS NOT NULL AND beforeqty IS NOT NULL AND delta IS NOT NULL AND afterqty IS NOT NULL)),
        CONSTRAINT fk_wmsadjustment_client  FOREIGN KEY (clientid)  REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsadjustment_site    FOREIGN KEY (siteid)    REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsadjustment_lpn     FOREIGN KEY (lpnid)     REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsadjustment_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsadjustment_reason  FOREIGN KEY (reasonid)  REFERENCES dbo.wmsreason (id)
    );
    CREATE INDEX ix_wmsadjustment_site_status ON dbo.wmsadjustment (siteid, status, clientid);
    CREATE INDEX ix_wmsadjustment_lpn ON dbo.wmsadjustment (lpnid);
END
GO

/* wmsadjustmentchange --------------------------------------------------------------
   PURPOSE: One field change on a kind='correct' adjustment ({field, from, to}).
            Flag-driven fields only (lot/expiry/serial when the product tracks
            them — app rule). Values stored as text (they print on the approval
            screen verbatim). Pure child table. */
IF OBJECT_ID(N'dbo.wmsadjustmentchange', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsadjustmentchange (
        id            INT            IDENTITY(1,1) NOT NULL,
        adjustmentid  INT            NOT NULL,
        field         VARCHAR(20)    NOT NULL,
        fromvalue     NVARCHAR(200)  NULL,
        tovalue       NVARCHAR(200)  NULL,
        CONSTRAINT pk_wmsadjustmentchange PRIMARY KEY (id),
        CONSTRAINT ck_wmsadjustmentchange_field CHECK (field IN ('lot','expiry','serial','product','client')),
        CONSTRAINT fk_wmsadjustmentchange_adj FOREIGN KEY (adjustmentid) REFERENCES dbo.wmsadjustment (id)
    );
    CREATE INDEX ix_wmsadjustmentchange_adj ON dbo.wmsadjustmentchange (adjustmentid);
END
GO

/* ============================================================================
   GROUP F — REPACK / SPLIT / MERGE / RE-KIT  (conversion with genealogy)
   ============================================================================ */

/* wmsrepack --------------------------------------------------------------------
   SCREEN : erp-inv-repack.html + pwa-inv-repack.html.
   PURPOSE: A conversion job: source plate(s) CONSUMED, output plate(s) CREATED
            (wmslpn rows minted, parentlpnid genealogy + lot/expiry/serials
            carried). kind: split (1->N) | merge (N->1, same product+lot+expiry
            only) | repack (1->1 new packaging) | rekit. Jobs post immediately
            (status 'confirmed'). Conservation: Σ(outputs)+remainder == source
            (app rule). 'repack' wmstxn per job. clientid is denormalised from
            the source plates for scoping filters (CC-08). */
IF OBJECT_ID(N'dbo.wmsrepack', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsrepack (
        id           INT           IDENTITY(1,1) NOT NULL,
        code         VARCHAR(40)   NOT NULL,   -- business key e.g. 'RPK-7000'
        kind         VARCHAR(10)   NOT NULL,   -- 'split' | 'merge' | 'repack' | 'rekit'
        clientid     INT           NULL,        -- denormalised from the source plates
        siteid       INT           NOT NULL,
        status       VARCHAR(20)   NOT NULL CONSTRAINT df_wmsrepack_status DEFAULT ('confirmed'),
        performedby  INT           NULL,        -- -> [dbo].[Users].[Id]
        performedat  DATETIME2     NULL,
        note         NVARCHAR(400) NULL,
        createdby    INT           NULL,
        createdat    DATETIME2     NULL,
        editby       INT           NULL,
        edittime     DATETIME2     NULL,
        CONSTRAINT pk_wmsrepack PRIMARY KEY (id),
        CONSTRAINT uq_wmsrepack_code UNIQUE (code),
        CONSTRAINT ck_wmsrepack_kind   CHECK (kind IN ('split','merge','repack','rekit')),
        CONSTRAINT ck_wmsrepack_status CHECK (status IN ('confirmed')),
        CONSTRAINT fk_wmsrepack_client FOREIGN KEY (clientid) REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsrepack_site   FOREIGN KEY (siteid)   REFERENCES dbo.wmssite (id)
    );
    CREATE INDEX ix_wmsrepack_site ON dbo.wmsrepack (siteid);
END
GO

/* wmsrepacksource -----------------------------------------------------------------
   PURPOSE: One consumed source plate (split reduces it, consuming only at 0;
            merge/repack/rekit consume outright — status 'consumed').
            Pure child table. */
IF OBJECT_ID(N'dbo.wmsrepacksource', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsrepacksource (
        id         INT           IDENTITY(1,1) NOT NULL,
        repackid   INT           NOT NULL,
        lpnid      INT           NOT NULL,
        productid  INT           NOT NULL,
        qty        DECIMAL(18,3) NOT NULL,    -- base units consumed from this plate
        CONSTRAINT pk_wmsrepacksource PRIMARY KEY (id),
        CONSTRAINT uq_wmsrepacksource_lpn UNIQUE (repackid, lpnid),
        CONSTRAINT fk_wmsrepacksource_repack  FOREIGN KEY (repackid)  REFERENCES dbo.wmsrepack (id),
        CONSTRAINT fk_wmsrepacksource_lpn     FOREIGN KEY (lpnid)     REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsrepacksource_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id)
    );
    CREATE INDEX ix_wmsrepacksource_repack ON dbo.wmsrepacksource (repackid);
    CREATE INDEX ix_wmsrepacksource_lpn    ON dbo.wmsrepacksource (lpnid);
END
GO

/* wmsrepackoutput -----------------------------------------------------------------
   PURPOSE: One created output plate (the minted wmslpn row carries the live
            stock + serials; this row is the job's record of what was created
            where). lot/expiry echo what was stamped on the output.
            Pure child table. */
IF OBJECT_ID(N'dbo.wmsrepackoutput', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsrepackoutput (
        id          INT           IDENTITY(1,1) NOT NULL,
        repackid    INT           NOT NULL,
        lpnid       INT           NOT NULL,   -- the minted plate
        productid   INT           NOT NULL,
        qty         DECIMAL(18,3) NOT NULL,
        lot         NVARCHAR(60)  NULL,
        expiry      DATETIME2     NULL,
        locationid  INT           NULL,        -- where the output was placed
        note        NVARCHAR(200) NULL,
        CONSTRAINT pk_wmsrepackoutput PRIMARY KEY (id),
        CONSTRAINT uq_wmsrepackoutput_lpn UNIQUE (repackid, lpnid),
        CONSTRAINT fk_wmsrepackoutput_repack   FOREIGN KEY (repackid)   REFERENCES dbo.wmsrepack (id),
        CONSTRAINT fk_wmsrepackoutput_lpn      FOREIGN KEY (lpnid)      REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsrepackoutput_product  FOREIGN KEY (productid)  REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsrepackoutput_location FOREIGN KEY (locationid) REFERENCES dbo.wmslocation (id)
    );
    CREATE INDEX ix_wmsrepackoutput_repack ON dbo.wmsrepackoutput (repackid);
    CREATE INDEX ix_wmsrepackoutput_lpn    ON dbo.wmsrepackoutput (lpnid);
END
GO

/* ============================================================================
   GROUP G — RETURN / PUT-BACK  (stock re-entering inventory)
   ============================================================================ */

/* wmsreturn --------------------------------------------------------------------
   SCREEN : erp-inv-returns.html + pwa-inv-returns.html.
   PURPOSE: kind='putback' (over-pick / unused) | 'customer' (post-dispatch
            return). Processing mints a plate per line ('return' txn), routed
            by the line's disposition. "refoutboundid" links the source
            outbound order (FK — 05 runs before this file); reftext is the
            free-text fallback for unlinked references. RMA credit/billing is
            OUT of scope — physical re-entry only. */
IF OBJECT_ID(N'dbo.wmsreturn', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreturn (
        id             INT           IDENTITY(1,1) NOT NULL,
        code           VARCHAR(40)   NOT NULL,   -- business key e.g. 'RET-9001'
        kind           VARCHAR(10)   NOT NULL,   -- 'putback' | 'customer'
        clientid       INT           NOT NULL,
        siteid         INT           NOT NULL,
        refoutboundid  INT           NULL,        -- source outbound order
        reftext        NVARCHAR(60)  NULL,        -- free-text reference fallback
        status         VARCHAR(20)   NOT NULL CONSTRAINT df_wmsreturn_status DEFAULT ('open'),
        closedat       DATETIME2     NULL,
        closedby       INT           NULL,        -- -> [dbo].[Users].[Id]
        assignee       INT           NULL,        -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        note           NVARCHAR(400) NULL,
        createdby      INT           NULL,
        createdat      DATETIME2     NULL,
        editby         INT           NULL,
        edittime       DATETIME2     NULL,
        CONSTRAINT pk_wmsreturn PRIMARY KEY (id),
        CONSTRAINT uq_wmsreturn_code UNIQUE (code),
        CONSTRAINT ck_wmsreturn_kind   CHECK (kind IN ('putback','customer')),
        CONSTRAINT ck_wmsreturn_status CHECK (status IN ('open','closed')),
        CONSTRAINT fk_wmsreturn_client   FOREIGN KEY (clientid)      REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsreturn_site     FOREIGN KEY (siteid)        REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsreturn_outbound FOREIGN KEY (refoutboundid) REFERENCES dbo.wmsoutbound (id)
    );
    CREATE INDEX ix_wmsreturn_site_status ON dbo.wmsreturn (siteid, status, clientid);
    CREATE INDEX ix_wmsreturn_outbound    ON dbo.wmsreturn (refoutboundid);
END
GO

/* wmsreturnline -------------------------------------------------------------------
   PURPOSE: One returned product line. Disposition routes the minted plate:
            'restock-direct' (available at tolocationid — passes the shared
            capacity + segregation checks) | 'restock-putaway' (to-putaway at
            inbound staging -> the directed-Putaway queue) | 'quarantine' |
            'damaged' (blocked plate at the quarantine location). Genealogy
            carried; mintedlpnid = the created plate. Serials captured before
            the plate exists live in wmsreturnlineserial. Pure child table. */
IF OBJECT_ID(N'dbo.wmsreturnline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreturnline (
        id            INT           IDENTITY(1,1) NOT NULL,
        returnid      INT           NOT NULL,
        [lineno]        INT           NOT NULL,
        productid     INT           NOT NULL,
        qty           DECIMAL(18,3) NOT NULL,
        lot           NVARCHAR(60)  NULL,
        expiry        DATETIME2     NULL,
        reasonid      INT           NULL,        -- -> wmsreason ('return' domain, seeded in 01)
        reasontext    NVARCHAR(200) NULL,
        disposition   VARCHAR(20)   NULL,        -- required at processing (app rule)
        tolocationid  INT           NULL,        -- restock-direct: the chosen bin
        mintedlpnid   INT           NULL,        -- the plate created at processing
        CONSTRAINT pk_wmsreturnline PRIMARY KEY (id),
        CONSTRAINT uq_wmsreturnline_lineno UNIQUE (returnid, [lineno]),
        CONSTRAINT ck_wmsreturnline_disp CHECK (disposition IS NULL OR disposition IN
            ('restock-direct','restock-putaway','quarantine','damaged')),
        CONSTRAINT fk_wmsreturnline_return  FOREIGN KEY (returnid)     REFERENCES dbo.wmsreturn (id),
        CONSTRAINT fk_wmsreturnline_product FOREIGN KEY (productid)    REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsreturnline_reason  FOREIGN KEY (reasonid)     REFERENCES dbo.wmsreason (id),
        CONSTRAINT fk_wmsreturnline_toloc   FOREIGN KEY (tolocationid) REFERENCES dbo.wmslocation (id),
        CONSTRAINT fk_wmsreturnline_minted  FOREIGN KEY (mintedlpnid)  REFERENCES dbo.wmslpn (id)
    );
    CREATE INDEX ix_wmsreturnline_return ON dbo.wmsreturnline (returnid);
END
GO

/* wmsreturnlineserial ---------------------------------------------------------------
   PURPOSE: Serials captured on a return line BEFORE its plate is minted (same
            posture as wmsreceiptlineserial); processing slices them onto the
            minted plate's wmslpnserial. Pure child table. */
IF OBJECT_ID(N'dbo.wmsreturnlineserial', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreturnlineserial (
        id            INT          IDENTITY(1,1) NOT NULL,
        returnlineid  INT          NOT NULL,
        serial        VARCHAR(80)  NOT NULL,
        CONSTRAINT pk_wmsreturnlineserial PRIMARY KEY (id),
        CONSTRAINT uq_wmsreturnlineserial UNIQUE (returnlineid, serial),
        CONSTRAINT fk_wmsreturnlineserial_line FOREIGN KEY (returnlineid) REFERENCES dbo.wmsreturnline (id)
    );
END
GO

/* ============================================================================
   GROUP H — DISPOSAL / SCRAP-OUT  (approval-gated, terminal)
   ============================================================================ */

/* wmsdisposal ------------------------------------------------------------------
   SCREEN : erp-inv-dispose.html + pwa-inv-dispose.html (floor raises, ERP
            approves — maker-checker F13).
   PURPOSE: Scrap / destroy / write-off a (usually blocked or expired) plate —
            TERMINAL. pending -> posted (approve: plate qty decremented, status
            'disposed' at 0, 'dispose' txn) | rejected (nothing). "method"
            values match the 'dispose' reason-domain group keys
            (06_inventory_ops_seed.sql) so the reason dropdown is
            reasonsFor('dispose', method). Approver ≠ raiser (app rule). */
IF OBJECT_ID(N'dbo.wmsdisposal', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsdisposal (
        id          INT           IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'DSP-7001'
        clientid    INT           NOT NULL,
        siteid      INT           NOT NULL,
        lpnid       INT           NOT NULL,   -- target plate
        productid   INT           NOT NULL,
        qty         DECIMAL(18,3) NOT NULL,
        method      VARCHAR(10)   NOT NULL,   -- 'scrap' | 'destroy' | 'writeoff' (= dispose domain group keys)
        reasonid    INT           NULL,        -- -> wmsreason ('dispose' domain)
        reasontext  NVARCHAR(200) NULL,
        note        NVARCHAR(400) NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmsdisposal_status DEFAULT ('pending'),
        approvedby  INT           NULL,        -- -> [dbo].[Users].[Id] (≠ createdby — app rule F13)
        postedat    DATETIME2     NULL,
        assignee    INT           NULL,        -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        createdby   INT           NULL,        -- the raiser
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmsdisposal PRIMARY KEY (id),
        CONSTRAINT uq_wmsdisposal_code UNIQUE (code),
        CONSTRAINT ck_wmsdisposal_method CHECK (method IN ('scrap','destroy','writeoff')),
        CONSTRAINT ck_wmsdisposal_status CHECK (status IN ('pending','posted','rejected')),
        CONSTRAINT fk_wmsdisposal_client  FOREIGN KEY (clientid)  REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsdisposal_site    FOREIGN KEY (siteid)    REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsdisposal_lpn     FOREIGN KEY (lpnid)     REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsdisposal_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsdisposal_reason  FOREIGN KEY (reasonid)  REFERENCES dbo.wmsreason (id)
    );
    CREATE INDEX ix_wmsdisposal_site_status ON dbo.wmsdisposal (siteid, status, clientid);
    CREATE INDEX ix_wmsdisposal_lpn ON dbo.wmsdisposal (lpnid);
END
GO

/* ============================================================================
   END OF INVENTORY OPERATIONS SCHEMA — THE LAST TABLE SET
   ----------------------------------------------------------------------------
   WMS tables created (18):
     Physical Inventory : wmsphysical, wmsphysicallocation, wmsphysicalline
     Cycle Count        : wmscount, wmscountlocation, wmscountline
     Move               : wmsmove
     Transfer           : wmstransfer, wmstransferline
     Adjustment         : wmsadjustment, wmsadjustmentchange
     Repack             : wmsrepack, wmsrepacksource, wmsrepackoutput
     Return             : wmsreturn, wmsreturnline, wmsreturnlineserial
     Disposal           : wmsdisposal

   Referenced (01): wmsclient, wmssite, wmsstoragearea, wmslocation, wmsproduct,
     wmsreason. Referenced (02): wmslpn. Referenced (05): wmsoutbound.
   Referenced logically (NOT FK-bound): [dbo].[Users] (all *by / assignee).
   Every posting APPENDS to wmstxn — all event types already in 02's CHECK.

   CROSS-SECTION UNBLOCKED BY THIS FILE:
     * IFreezeService (Putaway card 02 · Stock-Out card 06 · dispatch C1) can
       now be implemented FOR REAL (query in the header) — no stub needed.
       Until the Inventory-Ops screens create takes, the query simply returns
       "not frozen" — the same runtime behaviour as the stub, but real.
     * The Stock-Out "stock not found at pick" flow (F8) has its landing tables
       (wmscount* with source='pick-not-found').

   RECONCILIATION (2026-07-05): authored field-by-field against DATA_MODEL.md
   §Physical/§Count/§Move/§Transfer/§Adjustment/§Repack/§Return (+ the
   disposal/edge-case block in data.js: disposeCreate/Approve, rtvIssue's
   sibling flows, flagCountForMissing, frozenTakeFor) and COMMON_DATABASE_RULES
   .md's array→child-table map. NOT yet executed on a live SQL 2014 instance.
   ============================================================================ */
