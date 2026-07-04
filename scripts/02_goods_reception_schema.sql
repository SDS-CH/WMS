/* ============================================================================
   WMS (3PL) — DATABASE SCHEMA
   SECTION 02: GOODS RECEPTION  +  SHARED OPERATIONAL CORE
               (tables only — NO views, NO procedures)
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Module        : WMS — client-owned stock in a 3PL warehouse
   Run order     : AFTER 01_master_data_schema.sql (every table here FKs back to
                   Master Data — clients, sites, products, locations, suppliers,
                   carriers, reason codes, packaging levels, UoM).

   WHY THIS FILE COVERS MORE THAN "RECEIVING"
   ------------------------------------------
   Goods Reception is the FIRST stock-creating process. The act of receiving
   mints the records the WHOLE downstream warehouse runs on:
     * the License Plate (wmslpn) — the stock-bearing handling unit, and
     * the transaction ledger (wmstxn) — the append-only "every movement" log.
   Because of that, this file deliberately creates the **shared operational
   core** (GROUP A) alongside the Goods-Reception tables (GROUP B):

     GROUP A — Shared operational core (created here, reused everywhere)
       wmslpn, wmslpnserial          ← the stock record + explicit serial rows
       wmstxn                         ← append-only audit ledger (every movement)
       wmsattachment                  ← EDM-backed photo justification (polymorphic)

     GROUP B — Goods Reception
       wmsasn, wmsasnline             ← inbound order / ASN (status DERIVED)
       wmsreceipt, wmsreceiptline,    ← the physical receive event (what arrived;
         wmsreceiptlineserial            + serials captured on a draft line)
       wmspallet, wmspalletline,      ← mixed/aggregate pallet (decomposes at putaway)
         wmspalletlineserial
       wmsinspection                  ← formal QC accept/reject decision
       wmsgrn, wmsgrnline             ← Goods Received Note (one per receipt)
       wmsrefusal                     ← delivery refused at the door (NO stock minted)

   ANALYSIS OF THE ADJACENT SECTIONS (per the request to look ahead)
   -----------------------------------------------------------------
   * PUTAWAY (Section 03) needs **NO new tables**. Its worklist is derived
     (wmslpn WHERE status='to-putaway'  +  wmspallet WHERE status='to-putaway'),
     its history is the ledger (wmstxn WHERE type='putaway'), and every placement
     mutates wmslpn (status→available, loc=bin) / decomposes a wmspallet into child
     wmslpn rows + writes a wmstxn. Capacity & client-area segregation are enforced
     in app logic against wmslocation limits — not as DDL. The shared core below is
     therefore designed to serve the full LPN lifecycle so Putaway never alters it.
   * STOCK-OUT (Section 04/05) and INVENTORY OPS (Section 05) DO need their own
     tables (wmsoutbound / wmsoutboundline / wmsallocation / wmsshipment*, plus
     move/transfer/count/physical/repack/return/adjustment). They build on this
     same wmslpn + wmstxn core and are scripted in their own files (05_/06_). The
     wmslpn.status CHECK and the wmstxn.type CHECK below already include their
     values so those scripts add tables only — never ALTER these.

   CONVENTIONS HONOURED (identical to 01_master_data_schema.sql)
   -------------------------------------------------------------
   * Table names lower-case, prefixed "wms"; column names lower-case, no spaces.
   * Every table has id INT IDENTITY(1,1) PRIMARY KEY. Human/business ids
     (LPN-…, ASN-…, RCV-…, GRN-…, PLT-…, INS-…, REF-…, TXN-…) are a separate
     unique "code" business-key column — NEVER the PK.
   * Quantities/weights DECIMAL(18,3); packaging factors DECIMAL(18,4); dates
     DATETIME2; enums = VARCHAR guarded by CHECK (values match DATA_MODEL.md).
   * No JSON / OPENJSON, no temporal tables, no 2016+ features (SQL 2014).
   * Audit columns (createdby/createdat/editby/edittime) on aggregate roots only;
     pure child/link tables omit them (written within the parent's unit of work).
   * USER references (createdby/editby/<role>by/assignee/userid) are INT and point
     at [dbo].[Users].[Id] LOGICALLY — NOT FK-bound (same posture as 01: lets host
     users deactivate without blocking, and removes a load-order dependency on the
     host identity table).
   * Re-run safe: every CREATE guarded by IF OBJECT_ID(...) IS NULL; NO DROPs.

   IMAGE / PHOTO UPLOADS (per the explicit instruction)
   ----------------------------------------------------
   Images are NOT stored as rows-per-image business tables. A single polymorphic
   wmsattachment table references a document already held in the EDM system by its
   DOCID, and denormalises just enough metadata (docname / doctype) to render a
   list WITHOUT joining to EDM, plus a generated docthumbnail so a grid never has
   to download the full asset on every view. See wmsattachment.

   HOW TO RUN
   ----------
   USE [WMS];  -- (or the per-agency DMS_xx database)
   -- run 01_master_data_schema.sql first, then this file, then the seed files.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   GROUP B.1 — INBOUND ORDER / ASN  (created first: no dependency on the core)
   ============================================================================ */

/* wmsasn ---------------------------------------------------------------------
   SCREEN : erp-gr-asn.html (list + create/edit). Read by erp-gr-receipt.html
            (Receive against ASN) and pwa-gr-receive.html.
   PURPOSE: Advance Shipment Notice header — the expected inbound for a client at
            a site, from an optional supplier. The lifecycle status
            (open -> partial -> closed) is DERIVED from the lines' received-vs-
            expected and is NEVER stored (asnStatus()). The ONLY persisted state
            is the explicit lifecycle override in "state": a delivery refused at
            the door (-> 'refused', via wmsrefusal) or a voided ASN (-> 'cancelled');
            NULL means "live, status is derived". "assignee" carries the optional
            work-item owner for the receiving queue (CC-09). The VOID/cancel path
            (cancelAsn — erp-gr-asn.html "Void ASN" modal) records its reason + note +
            actor + timestamp in the cancel* columns; the mock's void reason list is
            screen-local (VOID_REASONS), so it is stored as free text rather than an FK
            (promote to a 'void' reason domain later if it must be configurable). Refusal
            reason capture lives on wmsrefusal instead (it also carries supplier/carrier
            return detail). */
IF OBJECT_ID(N'dbo.wmsasn', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsasn (
        id           INT IDENTITY(1,1) NOT NULL,
        code         VARCHAR(40)   NOT NULL,   -- business key e.g. 'ASN-3001'
        clientid     INT           NOT NULL,
        siteid       INT           NOT NULL,
        supplierid   INT           NULL,       -- source of the goods (optional)
        state        VARCHAR(20)   NULL,       -- NULL = live (derived) | 'cancelled' | 'refused'
        deliveryref  NVARCHAR(80)  NULL,       -- supplier delivery-note ref (expected)
        expectedat   DATETIME2     NULL,       -- expected arrival
        assignee     INT           NULL,       -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        note         NVARCHAR(400) NULL,
        cancelreason NVARCHAR(200) NULL,       -- void/cancel reason (set when state='cancelled')
        cancelnote   NVARCHAR(400) NULL,       -- optional free-text detail for the void
        cancelledby  INT           NULL,       -- -> [dbo].[Users].[Id] (who voided it)
        cancelledat  DATETIME2     NULL,       -- when it was voided
        createdby    INT           NULL,
        createdat    DATETIME2     NULL,
        editby       INT           NULL,
        edittime     DATETIME2     NULL,
        CONSTRAINT pk_wmsasn PRIMARY KEY (id),
        CONSTRAINT uq_wmsasn_code UNIQUE (code),
        CONSTRAINT ck_wmsasn_state CHECK (state IS NULL OR state IN ('cancelled','refused')),
        CONSTRAINT fk_wmsasn_client   FOREIGN KEY (clientid)   REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsasn_site     FOREIGN KEY (siteid)     REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsasn_supplier FOREIGN KEY (supplierid) REFERENCES dbo.wmssupplier (id)
    );
    CREATE INDEX ix_wmsasn_site_client ON dbo.wmsasn (siteid, clientid);
    CREATE INDEX ix_wmsasn_supplier    ON dbo.wmsasn (supplierid);
END
GO

/* wmsasnline -----------------------------------------------------------------
   SCREEN : erp-gr-asn.html (expected lines) + erp-gr-receipt.html (each line is
            pre-filled with its OUTSTANDING remainder = qty - received).
   PURPOSE: One expected product line on an ASN. "qty" = expected base units;
            "received" = base units received so far across one or more receipts
            (the running total maintained as each receipt posts — it is what
            asnStatus()/asnTotals() derive open/partial/closed from). A "Close ASN
            short" at receipt sets qty := received on undelivered lines (cancels
            the remainder). */
IF OBJECT_ID(N'dbo.wmsasnline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsasnline (
        id          INT IDENTITY(1,1) NOT NULL,
        asnid       INT           NOT NULL,
        [lineno]      INT           NOT NULL,   -- 1-based position on the ASN
        productid   INT           NOT NULL,
        qty         DECIMAL(18,3) NOT NULL,   -- expected base units
        received    DECIMAL(18,3) NOT NULL CONSTRAINT df_wmsasnline_received DEFAULT (0),
        uomid       INT           NULL,        -- optional expected UoM / pack level label
        note        NVARCHAR(200) NULL,
        CONSTRAINT pk_wmsasnline PRIMARY KEY (id),
        CONSTRAINT uq_wmsasnline_lineno UNIQUE (asnid, [lineno]),
        CONSTRAINT fk_wmsasnline_asn     FOREIGN KEY (asnid)     REFERENCES dbo.wmsasn (id),
        CONSTRAINT fk_wmsasnline_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsasnline_uom     FOREIGN KEY (uomid)     REFERENCES dbo.wmsuom (id)
    );
    CREATE INDEX ix_wmsasnline_asn     ON dbo.wmsasnline (asnid);
    CREATE INDEX ix_wmsasnline_product ON dbo.wmsasnline (productid);
END
GO

/* ============================================================================
   GROUP B.2 — MIXED / AGGREGATE PALLET  (built at receive, decomposed at putaway)
   (created before wmsreceiptline + wmslpn: both reference it)
   ============================================================================ */

/* wmspallet ------------------------------------------------------------------
   SCREEN : erp-gr-receipt.html ("add to pallet" / "close pallet") + pwa-gr-receive
            .html. Decomposed on erp-pa-tasks.html / PWA putaway (Section 03).
   PURPOSE: A TRANSIENT aggregate handling unit (PLT-…) carrying MANY product/lot
            lines under one license plate, built post-hoc during receiving. It is
            deliberately NOT stock: it holds wmspalletline rows, not wmslpn rows.
            At putaway it DECOMPOSES into one homogeneous child wmslpn per line
            (decomposePalletLine) so persistent stock stays one-product-per-LPN;
            the pallet flips to 'closed' when its last line is placed. "asnref"
            keys it to the ASN it was received against (per spec). "assignee" =
            the putaway work-item owner (status-derived queue, CC-09). */
IF OBJECT_ID(N'dbo.wmspallet', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmspallet (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)  NOT NULL,    -- business key e.g. 'PLT-00001' (SSCC in prod)
        clientid    INT          NOT NULL,
        siteid      INT          NOT NULL,
        status      VARCHAR(20)  NOT NULL CONSTRAINT df_wmspallet_status DEFAULT ('to-putaway'),
        locationid  INT          NOT NULL,    -- staging (wait/put) location it sits in
        asnref      VARCHAR(40)  NULL,         -- the ASN code it was received against
        assignee    INT          NULL,         -- -> [dbo].[Users].[Id]
        createdby   INT          NULL,
        createdat   DATETIME2    NULL,
        editby      INT          NULL,
        edittime    DATETIME2    NULL,
        CONSTRAINT pk_wmspallet PRIMARY KEY (id),
        CONSTRAINT uq_wmspallet_code UNIQUE (code),
        CONSTRAINT ck_wmspallet_status CHECK (status IN ('to-putaway','closed')),
        CONSTRAINT fk_wmspallet_client FOREIGN KEY (clientid) REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmspallet_site   FOREIGN KEY (siteid)   REFERENCES dbo.wmssite (id),
        -- composite FK: the pallet's staging location must belong to the pallet's site.
        CONSTRAINT fk_wmspallet_location FOREIGN KEY (locationid, siteid) REFERENCES dbo.wmslocation (id, siteid)
    );
    CREATE INDEX ix_wmspallet_site_status ON dbo.wmspallet (siteid, status, clientid);
END
GO

/* ============================================================================
   GROUP B.3 — THE RECEIVE EVENT  (what physically arrived)
   ============================================================================ */

/* wmsreceipt -----------------------------------------------------------------
   SCREEN : erp-gr-receipt.html (the receive confirm) + pwa-gr-receive.html.
   PURPOSE: ONE physical receive event ("Receipt — what actually arrived"). An ASN
            may be received over several receipts (multi-session); each is its own
            wmsreceipt and yields its own GRN (one GRN per physical receipt). A
            blind receipt has asnid NULL. "deliveryref" is the supplier note ref
            used by the duplicate-receipt guard (receiptRefSeen). "closedshort" =
            this receipt force-closed the ASN's undelivered remainder. The lines
            (what arrived, with condition + discrepancy) live in wmsreceiptline. */
IF OBJECT_ID(N'dbo.wmsreceipt', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreceipt (
        id           INT IDENTITY(1,1) NOT NULL,
        code         VARCHAR(40)   NOT NULL,   -- business key e.g. 'RCV-00001'
        clientid     INT           NOT NULL,
        siteid       INT           NOT NULL,
        asnid        INT           NULL,        -- NULL = blind receipt (no prior ASN)
        supplierid   INT           NULL,
        deliveryref  NVARCHAR(80)  NULL,        -- supplier delivery-note ref (duplicate guard)
        receivedby   INT           NULL,        -- -> [dbo].[Users].[Id]
        receivedat   DATETIME2     NULL,
        closedshort  BIT           NOT NULL CONSTRAINT df_wmsreceipt_closedshort DEFAULT (0),
        status       VARCHAR(20)   NOT NULL CONSTRAINT df_wmsreceipt_status DEFAULT ('confirmed'),
        note         NVARCHAR(400) NULL,
        createdby    INT           NULL,
        createdat    DATETIME2     NULL,
        editby       INT           NULL,
        edittime     DATETIME2     NULL,
        CONSTRAINT pk_wmsreceipt PRIMARY KEY (id),
        CONSTRAINT uq_wmsreceipt_code UNIQUE (code),
        CONSTRAINT ck_wmsreceipt_status CHECK (status IN ('draft','confirmed')),
        CONSTRAINT fk_wmsreceipt_client   FOREIGN KEY (clientid)   REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsreceipt_site     FOREIGN KEY (siteid)     REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsreceipt_asn      FOREIGN KEY (asnid)      REFERENCES dbo.wmsasn (id),
        CONSTRAINT fk_wmsreceipt_supplier FOREIGN KEY (supplierid) REFERENCES dbo.wmssupplier (id)
    );
    CREATE INDEX ix_wmsreceipt_site_client ON dbo.wmsreceipt (siteid, clientid);
    CREATE INDEX ix_wmsreceipt_asn         ON dbo.wmsreceipt (asnid);
    CREATE INDEX ix_wmsreceipt_deliveryref ON dbo.wmsreceipt (deliveryref);
END
GO

/* wmsreceiptline -------------------------------------------------------------
   SCREEN : erp-gr-receipt.html (each captured lot/condition line) + PWA receive.
   PURPOSE: ONE received lot line on a receipt — the unit of traceability. A single
            receipt may carry many lines (mixed lots / split conditions). Captures:
              * adaptive quantity  : "enteredqty" in the chosen pack level
                (enteredpackaginglevelid; NULL = base unit) with the cumulative
                "enteredfactor"; "qty" is the resolved BASE-unit quantity.
              * traceability        : lot, expiry (serials live on the minted LPN).
              * condition routing   : 'good' -> to-putaway · 'hold' -> to-inspect ·
                'damaged' -> quarantine. A non-good condition REQUIRES a reason
                (conditionreasonid -> wmsreason).
              * discrepancy vs ASN  : when the received qty != the ASN line's
                outstanding remainder, "discrepancyqty" (signed: + over / - short)
                and a MANDATORY "discrepancyreasonid". "overreceiptapproved" gates
                an over-receipt beyond +10% of outstanding (supervisor approval).
              * off-ASN extras      : "offasn" = 1 (asnlineid NULL) — an unexpected
                item added at receive; it does not count toward ASN line completion.
              * label model         : 'single' (one LPN) | 'split' (N LPNs per-each
                /per-pack — the chosen pack level persists in splitpackaginglevelid,
                NULL = per each/base) | 'pallet' (deferred onto a mixed pallet).
              * draft serials       : serials captured before Confirm live in
                wmsreceiptlineserial (no plate exists yet on a status='draft'
                receipt); Confirm slices them onto the minted plates' wmslpnserial.
            The minted plate(s) link BACK here via wmslpn.receiptlineid; a line
            deferred to a pallet has no LPN at receipt (the wmspalletline links via
            its receiptlineid). conservation: Σ(minted/pallet base) == qty. */
IF OBJECT_ID(N'dbo.wmsreceiptline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreceiptline (
        id                      INT IDENTITY(1,1) NOT NULL,
        receiptid               INT           NOT NULL,
        [lineno]                  INT           NOT NULL,   -- 1-based on the receipt
        asnlineid               INT           NULL,        -- NULL when offasn=1
        productid               INT           NOT NULL,
        enteredqty              DECIMAL(18,3) NOT NULL,    -- qty in the chosen pack level
        enteredpackaginglevelid INT           NULL,        -- chosen pack level (NULL = base unit)
        enteredfactor           DECIMAL(18,4) NOT NULL CONSTRAINT df_wmsreceiptline_factor DEFAULT (1),
        qty                     DECIMAL(18,3) NOT NULL,    -- resolved BASE units (= enteredqty * enteredfactor)
        lot                     NVARCHAR(60)  NULL,
        expiry                  DATETIME2     NULL,
        condition               VARCHAR(20)   NOT NULL CONSTRAINT df_wmsreceiptline_condition DEFAULT ('good'),
        conditionreasonid       INT           NULL,        -- required when condition <> 'good'
        discrepancyqty          DECIMAL(18,3) NULL,         -- signed: +over / -short vs ASN outstanding
        discrepancyreasonid     INT           NULL,         -- required when discrepancyqty <> 0
        overreceiptapproved     BIT           NOT NULL CONSTRAINT df_wmsreceiptline_ovr DEFAULT (0),
        offasn                  BIT           NOT NULL CONSTRAINT df_wmsreceiptline_offasn DEFAULT (0),
        labelmodel              VARCHAR(20)   NOT NULL CONSTRAINT df_wmsreceiptline_label DEFAULT ('single'),
        splitpackaginglevelid   INT           NULL,        -- labelmodel='split': pack level split by (NULL = per each/base)
        note                    NVARCHAR(200) NULL,
        CONSTRAINT pk_wmsreceiptline PRIMARY KEY (id),
        CONSTRAINT uq_wmsreceiptline_lineno UNIQUE (receiptid, [lineno]),
        CONSTRAINT ck_wmsreceiptline_condition CHECK (condition IN ('good','hold','damaged')),
        CONSTRAINT ck_wmsreceiptline_label     CHECK (labelmodel IN ('single','split','pallet')),
        CONSTRAINT fk_wmsreceiptline_receipt   FOREIGN KEY (receiptid)               REFERENCES dbo.wmsreceipt (id),
        CONSTRAINT fk_wmsreceiptline_asnline   FOREIGN KEY (asnlineid)               REFERENCES dbo.wmsasnline (id),
        CONSTRAINT fk_wmsreceiptline_product   FOREIGN KEY (productid)               REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsreceiptline_packlevel FOREIGN KEY (enteredpackaginglevelid) REFERENCES dbo.wmspackaginglevel (id),
        CONSTRAINT fk_wmsreceiptline_splitlvl  FOREIGN KEY (splitpackaginglevelid)   REFERENCES dbo.wmspackaginglevel (id),
        CONSTRAINT fk_wmsreceiptline_condrsn   FOREIGN KEY (conditionreasonid)       REFERENCES dbo.wmsreason (id),
        CONSTRAINT fk_wmsreceiptline_discrsn   FOREIGN KEY (discrepancyreasonid)     REFERENCES dbo.wmsreason (id)
    );
    CREATE INDEX ix_wmsreceiptline_receipt ON dbo.wmsreceiptline (receiptid);
    CREATE INDEX ix_wmsreceiptline_product ON dbo.wmsreceiptline (productid);
    CREATE INDEX ix_wmsreceiptline_asnline ON dbo.wmsreceiptline (asnlineid);
END
GO

/* wmsreceiptlineserial ---------------------------------------------------------
   PURPOSE: Serials captured on a receipt line BEFORE Confirm mints any plate —
            the persistence a DRAFT receipt (wmsreceipt.status='draft') needs so a
            resumed draft still carries its captured serials. On Confirm they slice
            onto the minted plates (wmslpnserial) exactly as entered; the rows here
            then remain as the as-captured record of the receive event.
            Pure child table — no audit columns. */
IF OBJECT_ID(N'dbo.wmsreceiptlineserial', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreceiptlineserial (
        id             INT IDENTITY(1,1) NOT NULL,
        receiptlineid  INT          NOT NULL,
        serial         VARCHAR(80)  NOT NULL,
        CONSTRAINT pk_wmsreceiptlineserial PRIMARY KEY (id),
        CONSTRAINT uq_wmsreceiptlineserial UNIQUE (receiptlineid, serial),
        CONSTRAINT fk_wmsreceiptlineserial_line FOREIGN KEY (receiptlineid) REFERENCES dbo.wmsreceiptline (id)
    );
END
GO

/* wmspalletline --------------------------------------------------------------
   SCREEN : erp-gr-receipt.html (the pallet manifest as lines are added) + putaway.
   PURPOSE: ONE product/lot line on a mixed pallet (one deferred received line).
            "qty" is the OPEN remainder — decomposePalletLine decrements it as each
            (possibly partial) line is placed at putaway; the pallet closes when no
            open line remains. "receiptlineid" carries the genealogy back to the
            receive event so the child LPNs minted at putaway stay fully traceable.
            Serials (where the product tracks them) live in wmspalletlineserial. */
IF OBJECT_ID(N'dbo.wmspalletline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmspalletline (
        id            INT IDENTITY(1,1) NOT NULL,
        palletid      INT           NOT NULL,
        [lineno]        INT           NOT NULL,
        receiptlineid INT           NULL,        -- source received line (genealogy)
        productid     INT           NOT NULL,
        qty           DECIMAL(18,3) NOT NULL,     -- OPEN remainder (decremented at decomposition)
        lot           NVARCHAR(60)  NULL,
        expiry        DATETIME2     NULL,
        CONSTRAINT pk_wmspalletline PRIMARY KEY (id),
        CONSTRAINT uq_wmspalletline_lineno UNIQUE (palletid, [lineno]),
        CONSTRAINT fk_wmspalletline_pallet      FOREIGN KEY (palletid)      REFERENCES dbo.wmspallet (id),
        CONSTRAINT fk_wmspalletline_receiptline FOREIGN KEY (receiptlineid) REFERENCES dbo.wmsreceiptline (id),
        CONSTRAINT fk_wmspalletline_product     FOREIGN KEY (productid)     REFERENCES dbo.wmsproduct (id)
    );
    CREATE INDEX ix_wmspalletline_pallet  ON dbo.wmspalletline (palletid);
    CREATE INDEX ix_wmspalletline_product ON dbo.wmspalletline (productid);
END
GO

/* wmspalletlineserial --------------------------------------------------------
   PURPOSE: Explicit unique serial rows carried by a mixed-pallet line for a
            serial-tracked product (sliced onto each child LPN at decomposition).
            Pure child table — no audit columns. */
IF OBJECT_ID(N'dbo.wmspalletlineserial', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmspalletlineserial (
        id            INT IDENTITY(1,1) NOT NULL,
        palletlineid  INT          NOT NULL,
        serial        VARCHAR(80)  NOT NULL,
        CONSTRAINT pk_wmspalletlineserial PRIMARY KEY (id),
        CONSTRAINT uq_wmspalletlineserial UNIQUE (palletlineid, serial),
        CONSTRAINT fk_wmspalletlineserial_line FOREIGN KEY (palletlineid) REFERENCES dbo.wmspalletline (id)
    );
END
GO

/* ============================================================================
   GROUP A.1 — LICENSE PLATE (the stock-bearing record) + serials
   (created after the receive tables it links back to; self-FK for genealogy)
   ============================================================================ */

/* wmslpn ---------------------------------------------------------------------
   SCREEN : minted on erp-gr-receipt.html / pwa-gr-receive.html (receive) and at
            pallet decomposition; the worklist source for putaway (status=
            'to-putaway') and inspection (status='to-inspect'); mutated by every
            downstream operational screen. Labels print/reprint from this row
            (erp-gr-labels.html, pwa-gr-lpn.html, pwa-gr-reprint.html).
   PURPOSE: THE handling unit and the primary stock-bearing record. One row = one
            homogeneous plate of a single product/lot/expiry at one location.
            Stock-on-hand is DERIVED, not stored: SoH = rows WHERE status='available'
            grouped by product/lot/location (no balances table — DATA_MODEL §LPN).
            "status" drives the whole lifecycle and the blocked set
            (quarantine/hold/damaged/expired are excluded from allocation).
            GENEALOGY: "parentlpnid" self-references the source plate when this
            plate was minted by an inspection split, a putaway split, or a repack
            (conservation + lot/expiry/serial carried). "receiptid"/"receiptlineid"
            tie a received plate to its receive event; "palletid" is set on a child
            minted from a mixed pallet at putaway. "assignee" = work-item owner for
            the status-derived putaway/inspect queues (CC-09). Capacity & client-
            area segregation are enforced in APP LOGIC at putaway (against
            wmslocation limits + wmsareaclient) — never as a master-data block. */
IF OBJECT_ID(N'dbo.wmslpn', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmslpn (
        id            INT IDENTITY(1,1) NOT NULL,
        code          VARCHAR(40)   NOT NULL,   -- business key e.g. 'LPN-00012' (SSCC in prod)
        clientid      INT           NOT NULL,
        siteid        INT           NOT NULL,
        productid     INT           NOT NULL,
        qty           DECIMAL(18,3) NOT NULL,    -- BASE units on the plate
        lot           NVARCHAR(60)  NULL,        -- present when the product tracks lot
        expiry        DATETIME2     NULL,        -- present when the product tracks expiry (drives FEFO)
        status        VARCHAR(20)   NOT NULL,
        locationid    INT           NOT NULL,    -- current location (within the site)
        parentlpnid   INT           NULL,        -- genealogy: source plate of a split/inspection/repack child
        palletid      INT           NULL,        -- set when minted from a mixed pallet at putaway
        receiptid     INT           NULL,        -- the receive event that minted it (NULL for repack/return/found)
        receiptlineid INT           NULL,        -- the received line that minted it
        assignee      INT           NULL,        -- -> [dbo].[Users].[Id] (putaway/inspect queue owner)
        createdby     INT           NULL,
        createdat     DATETIME2     NULL,
        editby        INT           NULL,
        edittime      DATETIME2     NULL,
        CONSTRAINT pk_wmslpn PRIMARY KEY (id),
        CONSTRAINT uq_wmslpn_code UNIQUE (code),
        -- full lifecycle enum (covers receiving, putaway, stock-out, inventory-ops, transfer, repack):
        --   'disposed' = scrapped/destroyed (Section 05 disposal — terminal, qty 0);
        --   'lost'     = in-transit loss/shrinkage (Section 06 transfer short — terminal).
        -- Both are downstream terminal states, listed here so later scripts add tables, never ALTER this CHECK.
        CONSTRAINT ck_wmslpn_status CHECK (status IN
            ('to-inspect','to-putaway','available','allocated','picked','dispatched',
             'in-transit','consumed','hold','quarantine','damaged','expired',
             'disposed','lost')),
        -- composite-FK target so wmstxn / downstream stock tables can pin a plate to its site if needed.
        CONSTRAINT uq_wmslpn_idsite UNIQUE (id, siteid),
        CONSTRAINT fk_wmslpn_client      FOREIGN KEY (clientid)      REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmslpn_site        FOREIGN KEY (siteid)        REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmslpn_product     FOREIGN KEY (productid)     REFERENCES dbo.wmsproduct (id),
        -- composite FK: an LPN's current location MUST belong to the LPN's site.
        CONSTRAINT fk_wmslpn_location    FOREIGN KEY (locationid, siteid) REFERENCES dbo.wmslocation (id, siteid),
        CONSTRAINT fk_wmslpn_parent      FOREIGN KEY (parentlpnid)   REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmslpn_pallet      FOREIGN KEY (palletid)      REFERENCES dbo.wmspallet (id),
        CONSTRAINT fk_wmslpn_receipt     FOREIGN KEY (receiptid)     REFERENCES dbo.wmsreceipt (id),
        CONSTRAINT fk_wmslpn_receiptline FOREIGN KEY (receiptlineid) REFERENCES dbo.wmsreceiptline (id)
    );
    -- the worklist / SoH / allocation hot path: filter by site + status (+ product).
    CREATE INDEX ix_wmslpn_site_status_product ON dbo.wmslpn (siteid, status, productid);
    CREATE INDEX ix_wmslpn_client     ON dbo.wmslpn (clientid);
    CREATE INDEX ix_wmslpn_location   ON dbo.wmslpn (locationid);
    CREATE INDEX ix_wmslpn_parent     ON dbo.wmslpn (parentlpnid);
    CREATE INDEX ix_wmslpn_pallet     ON dbo.wmslpn (palletid);
    CREATE INDEX ix_wmslpn_receipt    ON dbo.wmslpn (receiptid);
END
GO

/* wmslpnserial ---------------------------------------------------------------
   PURPOSE: Explicit, unique serial rows for a serial-tracked plate — closes
            DATA_MODEL gap #2 (the mock seeds a display range like 'SN-301…360';
            production stores one row per unit). Count of rows must equal the
            plate's base qty (enforced in app logic). Serials slice onto child
            plates on split / inspection / putaway (genealogy). uq is per-plate;
            cross-plate uniqueness per product/client is an app-level rule (a
            serial legitimately moves between plates as stock is split/merged).
            Pure child table — no audit columns. */
IF OBJECT_ID(N'dbo.wmslpnserial', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmslpnserial (
        id      INT IDENTITY(1,1) NOT NULL,
        lpnid   INT          NOT NULL,
        serial  VARCHAR(80)  NOT NULL,
        CONSTRAINT pk_wmslpnserial PRIMARY KEY (id),
        CONSTRAINT uq_wmslpnserial UNIQUE (lpnid, serial),
        CONSTRAINT fk_wmslpnserial_lpn FOREIGN KEY (lpnid) REFERENCES dbo.wmslpn (id)
    );
    CREATE INDEX ix_wmslpnserial_serial ON dbo.wmslpnserial (serial);
END
GO

/* ============================================================================
   GROUP B.4 — INSPECTION  (formal QC accept/reject for to-inspect plates)
   ============================================================================ */

/* wmsinspection --------------------------------------------------------------
   SCREEN : erp-gr-inspect.html + pwa-gr-inspect.html.
   PURPOSE: The persisted formal QC decision for a plate flagged 'to-inspect' at
            receipt. Quantity-based accept/reject (inspectionSplit): "acceptedqty"
            releases to to-putaway (-> the accepted plate keeps the id or becomes
            "acceptedlpnid"); the "rejectedqty" shortfall splits to a blocked
            "disposition" (quarantine|hold|damaged) on a child plate
            ("rejectedlpnid"), excluded from available stock. The reject reason
            list is DRIVEN BY the disposition, pulled live from Master Data ›
            Reason Codes (the 'status' domain group = the target status), hence
            reasonid -> wmsreason. Whole-accept / whole-reject keep the plate's id
            (one of accepted/rejected ids equals lpnid); a partial conserves
            quantity (accepted+rejected = originalqty) and carries genealogy.
            Each accept/reject also writes an 'inspect' row to wmstxn. */
IF OBJECT_ID(N'dbo.wmsinspection', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsinspection (
        id            INT IDENTITY(1,1) NOT NULL,
        code          VARCHAR(40)   NOT NULL,   -- business key e.g. 'INS-00001'
        lpnid         INT           NOT NULL,   -- the inspected (to-inspect) plate
        clientid      INT           NOT NULL,
        siteid        INT           NOT NULL,
        productid     INT           NOT NULL,
        originalqty   DECIMAL(18,3) NOT NULL,
        acceptedqty   DECIMAL(18,3) NOT NULL CONSTRAINT df_wmsinspection_acc DEFAULT (0),
        rejectedqty   DECIMAL(18,3) NOT NULL CONSTRAINT df_wmsinspection_rej DEFAULT (0),
        disposition   VARCHAR(20)   NULL,        -- NULL when whole-accept; else quarantine|hold|damaged
        reasonid      INT           NULL,        -- required when rejectedqty > 0
        acceptedlpnid INT           NULL,        -- the to-putaway plate (NULL when whole-reject)
        rejectedlpnid INT           NULL,        -- the blocked child plate (NULL when whole-accept)
        inspectedby   INT           NULL,        -- -> [dbo].[Users].[Id]
        inspectedat   DATETIME2     NULL,
        note          NVARCHAR(400) NULL,
        status        VARCHAR(20)   NOT NULL CONSTRAINT df_wmsinspection_status DEFAULT ('decided'),
        createdby     INT           NULL,
        createdat     DATETIME2     NULL,
        editby        INT           NULL,
        edittime      DATETIME2     NULL,
        CONSTRAINT pk_wmsinspection PRIMARY KEY (id),
        CONSTRAINT uq_wmsinspection_code UNIQUE (code),
        CONSTRAINT ck_wmsinspection_disp   CHECK (disposition IS NULL OR disposition IN ('quarantine','hold','damaged')),
        CONSTRAINT ck_wmsinspection_status CHECK (status IN ('pending','decided')),
        CONSTRAINT fk_wmsinspection_lpn      FOREIGN KEY (lpnid)         REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsinspection_client   FOREIGN KEY (clientid)      REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsinspection_site     FOREIGN KEY (siteid)        REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsinspection_product  FOREIGN KEY (productid)     REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsinspection_reason   FOREIGN KEY (reasonid)      REFERENCES dbo.wmsreason (id),
        CONSTRAINT fk_wmsinspection_acclpn   FOREIGN KEY (acceptedlpnid) REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsinspection_rejlpn   FOREIGN KEY (rejectedlpnid) REFERENCES dbo.wmslpn (id)
    );
    CREATE INDEX ix_wmsinspection_site ON dbo.wmsinspection (siteid);
    CREATE INDEX ix_wmsinspection_lpn  ON dbo.wmsinspection (lpnid);
END
GO

/* ============================================================================
   GROUP B.5 — GOODS RECEIVED NOTE  (client document, one per physical receipt)
   ============================================================================ */

/* wmsgrn ---------------------------------------------------------------------
   SCREEN : erp-gr-grn.html (view/print).
   PURPOSE: The confirmation document issued to the client — ONE per physical
            receipt (a multi-delivery ASN yields several GRNs), hence the 1:1
            link to wmsreceipt (uq on receiptid). Header is a snapshot for the
            printed document; the immutable line snapshot is wmsgrnline. */
IF OBJECT_ID(N'dbo.wmsgrn', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsgrn (
        id           INT IDENTITY(1,1) NOT NULL,
        code         VARCHAR(40)   NOT NULL,   -- business key e.g. 'GRN-4001'
        receiptid    INT           NOT NULL,   -- 1:1 — one GRN per physical receipt
        clientid     INT           NOT NULL,
        siteid       INT           NOT NULL,
        asnid        INT           NULL,
        supplierid   INT           NULL,
        deliveryref  NVARCHAR(80)  NULL,
        grndate      DATETIME2     NULL,
        status       VARCHAR(20)   NOT NULL CONSTRAINT df_wmsgrn_status DEFAULT ('issued'),
        issuedby     INT           NULL,        -- -> [dbo].[Users].[Id] (who generated the GRN)
        receivedby   INT           NULL,        -- -> [dbo].[Users].[Id] (printed "Received by" signature line)
        inspectedby  INT           NULL,        -- -> [dbo].[Users].[Id] (printed "Inspected by" signature line)
        note         NVARCHAR(400) NULL,
        createdby    INT           NULL,
        createdat    DATETIME2     NULL,
        editby       INT           NULL,
        edittime     DATETIME2     NULL,
        CONSTRAINT pk_wmsgrn PRIMARY KEY (id),
        CONSTRAINT uq_wmsgrn_code UNIQUE (code),
        CONSTRAINT uq_wmsgrn_receipt UNIQUE (receiptid),
        -- lifecycle of the client document: issued (generated) -> sent (emailed to the client).
        CONSTRAINT ck_wmsgrn_status CHECK (status IN ('issued','sent')),
        CONSTRAINT fk_wmsgrn_receipt  FOREIGN KEY (receiptid)  REFERENCES dbo.wmsreceipt (id),
        CONSTRAINT fk_wmsgrn_client   FOREIGN KEY (clientid)   REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsgrn_site     FOREIGN KEY (siteid)     REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsgrn_asn      FOREIGN KEY (asnid)      REFERENCES dbo.wmsasn (id),
        CONSTRAINT fk_wmsgrn_supplier FOREIGN KEY (supplierid) REFERENCES dbo.wmssupplier (id)
    );
    CREATE INDEX ix_wmsgrn_site_client ON dbo.wmsgrn (siteid, clientid);
    CREATE INDEX ix_wmsgrn_asn         ON dbo.wmsgrn (asnid);
END
GO

/* wmsgrnline -----------------------------------------------------------------
   PURPOSE: Immutable line snapshot printed on the GRN (product, qty, lot, expiry,
            condition, line remark, and the LPN it landed on). A snapshot —
            deliberately stored rather than re-derived from the receipt line, so a
            reprinted GRN always reproduces exactly what was confirmed ("note"
            snapshots the receipt line's remark — the printed document renders a
            per-line Notes column). Pure child table. */
IF OBJECT_ID(N'dbo.wmsgrnline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsgrnline (
        id          INT IDENTITY(1,1) NOT NULL,
        grnid       INT           NOT NULL,
        [lineno]      INT           NOT NULL,
        productid   INT           NOT NULL,
        qty         DECIMAL(18,3) NOT NULL,
        lot         NVARCHAR(60)  NULL,
        expiry      DATETIME2     NULL,
        condition   VARCHAR(20)   NOT NULL CONSTRAINT df_wmsgrnline_condition DEFAULT ('good'),
        note        NVARCHAR(200) NULL,         -- line remark snapshot (the printed doc's Notes column)
        lpnid       INT           NULL,         -- the plate this line landed on (NULL = deferred to pallet)
        CONSTRAINT pk_wmsgrnline PRIMARY KEY (id),
        CONSTRAINT uq_wmsgrnline_lineno UNIQUE (grnid, [lineno]),
        CONSTRAINT ck_wmsgrnline_condition CHECK (condition IN ('good','hold','damaged')),
        CONSTRAINT fk_wmsgrnline_grn     FOREIGN KEY (grnid)     REFERENCES dbo.wmsgrn (id),
        CONSTRAINT fk_wmsgrnline_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsgrnline_lpn     FOREIGN KEY (lpnid)     REFERENCES dbo.wmslpn (id)
    );
    CREATE INDEX ix_wmsgrnline_grn ON dbo.wmsgrnline (grnid);
END
GO

/* ============================================================================
   GROUP B.6 — DELIVERY REFUSAL  (refused at the door — NO stock minted)
   ============================================================================ */

/* wmsrefusal -----------------------------------------------------------------
   SCREEN : erp-gr-receipt.html ("Refuse delivery" path) — edge-case card P02-S07.
   PURPOSE: A reasoned record that a delivery was refused at the door — the goods
            never entered the warehouse, so NO wmslpn is minted and NO stock moves.
            Optionally flips the linked ASN to state='refused'. The refusal reason
            comes from Master Data › Reason Codes ('refuse' domain), hence
            reasonid -> wmsreason. A 'refuse' row is still written to wmstxn for
            the audit trail (qty 0, no plate). */
IF OBJECT_ID(N'dbo.wmsrefusal', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsrefusal (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'REF-0001'
        clientid    INT           NULL,
        siteid      INT           NULL,
        asnid       INT           NULL,
        supplierid  INT           NULL,
        carrierid   INT           NULL,
        reasonid    INT           NULL,        -- -> wmsreason ('refuse' domain)
        reasontext  NVARCHAR(200) NULL,        -- free-text fallback / detail
        note        NVARCHAR(400) NULL,
        refusedby   INT           NULL,        -- -> [dbo].[Users].[Id]
        refusedat   DATETIME2     NULL,
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmsrefusal PRIMARY KEY (id),
        CONSTRAINT uq_wmsrefusal_code UNIQUE (code),
        CONSTRAINT fk_wmsrefusal_client   FOREIGN KEY (clientid)   REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsrefusal_site     FOREIGN KEY (siteid)     REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsrefusal_asn      FOREIGN KEY (asnid)      REFERENCES dbo.wmsasn (id),
        CONSTRAINT fk_wmsrefusal_supplier FOREIGN KEY (supplierid) REFERENCES dbo.wmssupplier (id),
        CONSTRAINT fk_wmsrefusal_carrier  FOREIGN KEY (carrierid)  REFERENCES dbo.wmscarrier (id),
        CONSTRAINT fk_wmsrefusal_reason   FOREIGN KEY (reasonid)   REFERENCES dbo.wmsreason (id)
    );
    CREATE INDEX ix_wmsrefusal_site ON dbo.wmsrefusal (siteid);
    CREATE INDEX ix_wmsrefusal_asn  ON dbo.wmsrefusal (asnid);
END
GO

/* ============================================================================
   GROUP A.2 — TRANSACTION LEDGER  (append-only "every movement" log)
   ============================================================================ */

/* wmstxn ---------------------------------------------------------------------
   SCREEN : written by EVERY stock-mutating action across all sections (logTxn);
            READ by the Reports section (erp-rpt-txns / stockcard / trace) and by
            the Putaway/Stock-Out "Completed/Dispatched" history tabs.
   PURPOSE: The append-only audit ledger — the single answer to "track every
            movement (movements, logs, quantities)". One row per committed
            mutation (BLOCKING_RULES: an action that writes no audit row is a bug).
            INSERT-ONLY by convention — no UPDATE/DELETE (optionally DENY for the
            app login); production intent is strict immutability with full actor
            (DATA_MODEL gap #6). "type" spans every section so downstream scripts
            add tables, never ALTER this CHECK. "qty" is signed for adjustments.
            from/to are modelled as nullable location FKs (the common
            receive/putaway/move case); cross-site (transfer) and no-location
            events (refuse) carry the human description in "note" + the linked
            document in "ref". */
IF OBJECT_ID(N'dbo.wmstxn', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmstxn (
        id              INT IDENTITY(1,1) NOT NULL,
        code            VARCHAR(40)   NOT NULL,   -- business key e.g. 'TXN-1001'
        ts              DATETIME2     NOT NULL,    -- event timestamp
        type            VARCHAR(20)   NOT NULL,
        lpnid           INT           NULL,        -- affected plate (NULL for refuse / doc-level events)
        productid       INT           NULL,
        qty             DECIMAL(18,3) NULL,         -- base units affected (signed for adjustments)
        fromlocationid  INT           NULL,         -- -> wmslocation (move/putaway/dispatch source)
        tolocationid    INT           NULL,         -- -> wmslocation (receive/putaway destination)
        siteid          INT           NULL,
        userid          INT           NULL,         -- -> [dbo].[Users].[Id] (actor)
        ref             NVARCHAR(60)  NULL,         -- linked document code (GRN / ASN / order / transfer / …)
        note            NVARCHAR(400) NULL,         -- human description (e.g. 'available -> quarantine - Damage found')
        CONSTRAINT pk_wmstxn PRIMARY KEY (id),
        CONSTRAINT uq_wmstxn_code UNIQUE (code),
        -- spans every section's events so downstream scripts add tables, never ALTER this CHECK.
        -- transfer-loss / transfer-cancel (Section 06 transfer abandon/short) and park (Section 03
        -- putaway-to-overflow when no bin is available) are downstream events listed up-front here.
        -- 'reprint' audits every label reprint (P02-S06 — erp-gr-labels / pwa-gr-reprint / print-again
        -- from any screen): qty 0, lpnid or ref identifies the plate/pallet; nothing is minted.
        CONSTRAINT ck_wmstxn_type CHECK (type IN
            ('receive','putaway','park','move','transfer-ship','transfer-receive','transfer-loss',
             'transfer-cancel','adjust','correct','count','status','repack','return','dispatch',
             'attach','attach-remove','inspect','refuse','rtv','dispose','reprint')),
        CONSTRAINT fk_wmstxn_lpn      FOREIGN KEY (lpnid)          REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmstxn_product  FOREIGN KEY (productid)      REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmstxn_fromloc  FOREIGN KEY (fromlocationid) REFERENCES dbo.wmslocation (id),
        CONSTRAINT fk_wmstxn_toloc    FOREIGN KEY (tolocationid)   REFERENCES dbo.wmslocation (id),
        CONSTRAINT fk_wmstxn_site     FOREIGN KEY (siteid)         REFERENCES dbo.wmssite (id)
    );
    CREATE INDEX ix_wmstxn_lpn       ON dbo.wmstxn (lpnid);          -- stock card (per plate)
    CREATE INDEX ix_wmstxn_ts        ON dbo.wmstxn (ts);             -- chronological reports
    CREATE INDEX ix_wmstxn_type_site ON dbo.wmstxn (type, siteid);  -- putaway/dispatch history tabs
    CREATE INDEX ix_wmstxn_ref       ON dbo.wmstxn (ref);           -- trace by document
END
GO

/* ============================================================================
   GROUP A.3 — ATTACHMENTS  (EDM-backed photo justification — polymorphic)
   ============================================================================ */

/* wmsattachment --------------------------------------------------------------
   SCREEN : the shared photos widget across erp-gr-receipt / erp-gr-inspect /
            erp-gr-grn (header + line photos) and, later, Stock-Out + Inventory-Ops.
   PURPOSE: Optional photo/document evidence attached to a WMS document (header) or
            a line. PER THE EXPLICIT INSTRUCTION the image bytes are NOT stored here
            — the asset lives in the EDM system and is referenced by "docid"; this
            table denormalises just enough EDM metadata (docname/doctype) to render
            a list WITHOUT joining to EDM, plus a generated "docthumbnail" so a grid
            never downloads the full asset on every view. POLYMORPHIC ownership: it
            attaches to many entity kinds via (entitytype, entityid) — the WMS row
            it belongs to — with "level" = header|line and "lineref" naming the line
            (a line index or an LPN code) for line-level photos. Every add/remove
            also writes an 'attach'/'attach-remove' row to wmstxn (audited). */
IF OBJECT_ID(N'dbo.wmsattachment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsattachment (
        id            INT IDENTITY(1,1) NOT NULL,
        -- ---- EDM linkage (the only fields that identify the image) ----
        docid         VARCHAR(80)    NOT NULL,   -- references a DOCID inside the EDM database
        docname       NVARCHAR(200)  NULL,        -- EDM metadata, denormalised to avoid a join
        doctype       VARCHAR(40)    NULL,        -- EDM metadata, denormalised (e.g. 'photo','pdf')
        docthumbnail  VARBINARY(MAX) NULL,        -- generated thumbnail (avoids downloading the full asset)
        edmdb         VARCHAR(80)    NULL,        -- which EDM database/repository holds the doc
        mimetype      VARCHAR(80)    NULL,        -- e.g. 'image/jpeg'
        filesizebytes BIGINT         NULL,
        -- ---- WMS ownership (what this is attached to) ----
        entitytype    VARCHAR(30)    NOT NULL,    -- 'receipt'|'grn'|'asn'|'inspection'|'lpn'|'pallet'|'outbound'|'return'|'adjustment'|…
        entityid      INT            NULL,         -- the owning WMS row id (polymorphic — not FK-bound)
        entitycode    NVARCHAR(60)   NULL,         -- the owning business code (mirror of the mock 'ref')
        level         VARCHAR(10)    NOT NULL CONSTRAINT df_wmsattachment_level DEFAULT ('header'),
        lineref       NVARCHAR(60)   NULL,         -- line-level only: line index or LPN code
        caption       NVARCHAR(200)  NULL,
        sortorder     INT            NULL,
        status        VARCHAR(20)    NOT NULL CONSTRAINT df_wmsattachment_status DEFAULT ('active'),
        uploadedby    INT            NULL,         -- -> [dbo].[Users].[Id]
        uploadedat    DATETIME2      NULL,
        createdby     INT            NULL,
        createdat     DATETIME2      NULL,
        editby        INT            NULL,
        edittime      DATETIME2      NULL,
        CONSTRAINT pk_wmsattachment PRIMARY KEY (id),
        CONSTRAINT ck_wmsattachment_level  CHECK (level IN ('header','line')),
        CONSTRAINT ck_wmsattachment_status CHECK (status IN ('active','removed'))
    );
    -- look up "all photos for this document" fast (the widget's main query).
    CREATE INDEX ix_wmsattachment_owner ON dbo.wmsattachment (entitytype, entityid);
    CREATE INDEX ix_wmsattachment_code  ON dbo.wmsattachment (entitycode);
    CREATE INDEX ix_wmsattachment_docid ON dbo.wmsattachment (docid);
END
GO

/* ============================================================================
   END OF GOODS RECEPTION + SHARED OPERATIONAL CORE SCHEMA
   ----------------------------------------------------------------------------
   WMS tables created (16):
     Shared core   : wmslpn, wmslpnserial, wmstxn, wmsattachment
     ASN           : wmsasn, wmsasnline
     Receive       : wmsreceipt, wmsreceiptline, wmsreceiptlineserial
     Mixed pallet  : wmspallet, wmspalletline, wmspalletlineserial
     Inspection    : wmsinspection
     GRN           : wmsgrn, wmsgrnline
     Refusal       : wmsrefusal

   Referenced (from 01_master_data_schema.sql): wmsclient, wmssite, wmsproduct,
     wmslocation, wmssupplier, wmscarrier, wmsreason, wmspackaginglevel, wmsuom.
   Referenced logically (NOT FK-bound): [dbo].[Users] (all *by / userid / assignee).

   PUTAWAY (Section 03) adds NO tables — it operates entirely on wmslpn (status
   to-putaway -> available + split children), wmspallet (decomposition), wmslocation
   (capacity/segregation), and wmstxn (type='putaway' history). Stock-Out and
   Inventory-Ops get their own scripts (05_/06_) building on this same core.

   NOT in this file (by design): views and stored procedures — built per-screen
   during the dev cards. Reference/seed rows live in 02_goods_reception_seed.sql.

   VERIFICATION PASS (2026-06-24) — reconciled field-by-field against the 5 ERP
   mockups (erp-gr-asn / receipt / inspect / grn / labels), the PWA receive/inspect
   screens, and every logTxn()/status mutation in mockups/assets/data.js. Fixes
   applied vs the first draft:
     * wmstxn.type CHECK — added 'transfer-loss','transfer-cancel','park' (these
       downstream events are logged by the transfer + putaway-overflow flows; the
       draft would have REJECTED them — the shared CHECK must list every section's
       event because later scripts add tables, never ALTER this CHECK). Now 21 types.
     * wmslpn.status CHECK — added 'disposed','lost' (terminal states set by the
       Section-05 disposal and Section-06 transfer-short flows). Now 14 statuses.
     * wmsasn — added cancelreason/cancelnote/cancelledby/cancelledat (the Void-ASN
       modal captured a reason+note that the draft had nowhere to persist).
     * wmsgrn — added receivedby/inspectedby (the printed GRN signature block).
   The seed adds the 'receipt'/'refuse'/'discrepancy' reason domains the Receive +
   Refuse screens CONSUME (defined in data.js but absent from 01's reason seed).
   CROSS-SECTION GAP (Master Data, file 01): inline product creation on Receive has a
   role-based pending/unverified policy, but wmsproduct has no verification flag —
   recommend the MD team add e.g. verificationstatus VARCHAR(20) ('verified'|'pending').

   SECOND VERIFICATION PASS (2026-07-03) — pre-execution audit: the 5 ERP mockups
   (erp-gr-asn / receipt / inspect / grn / labels) + data.js re-reconciled against
   this file before its first execution. Changes applied:
     * wmstxn.type CHECK — added 'reprint' (P02-S06 mandates auditing EVERY label
       reprint; this CHECK is frozen after execution by the never-ALTER convention,
       so the type had to ship now). Now 22 types.
     * wmsgrn — added status ('issued'|'sent'): the GRN list renders a Status badge
       and the "Email to client" action needs a lifecycle state to move to.
     * wmsgrnline — added note: the printed GRN renders a per-line Notes column;
       the immutable line snapshot must reproduce it on reprint.
     * wmsreceiptline — added splitpackaginglevelid: labelmodel='split' now records
       WHICH pack level the split uses, so a saved DRAFT receipt resumes exactly
       as entered.
     * wmsreceiptlineserial — NEW pure child table: serials captured on a draft
       line before any plate exists; Confirm slices them onto wmslpnserial.
   Deliberately NOT added (recorded as decisions): wmstxn.palletid (pallet events
   carry the PLT code in "ref"; revisit only if pallet stock-card queries need a
   first-class FK) and a wmsgrnlineserial snapshot (the serial appendix reads the
   live plate via lpnid; the as-received serials stay recoverable via the plate's
   receiptlineid -> wmsreceiptlineserial).
   ============================================================================ */
