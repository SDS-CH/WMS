/* ============================================================================
   WMS (3PL) — DATABASE SCHEMA
   SECTION 05: STOCK-OUT (OUTBOUND)
               (tables only — NO views, NO procedures)
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Module        : WMS — client-owned stock in a 3PL warehouse
   Run order     : AFTER 01_master_data_schema.sql AND 02_goods_reception_schema
                   .sql (every table here FKs back to Master Data — clients,
                   sites, products, locations, consignees, carriers, suppliers,
                   reason codes — and to the shared operational core: wmslpn).
                   Then run 05_stock_out_seed.sql (the 'rtv' reason domain).

   SCREENS COVERED (mockups are the functional source of truth)
   ------------------------------------------------------------
     erp-so-orders.html    — Outbound Orders (CRUD, lines, ship-to consignee,
                             fullStockOut, cancel order / cancel line, release)
     erp-so-alloc.html     — Allocation (FEFO/FIFO, reservation-aware, manual
                             override, short allocation, frozen-scope exclusion)
     erp-so-dispatch.html  — Pick / Dispatch (scan-confirm, serials-on-issue,
                             short pick, damage-at-pick, carrier+proof-of-load,
                             issue stock, Delivery Note)
     erp-so-fulfil.html    — Express Fulfil (one-pass; same commit shape)
     erp-so-note.html      — Delivery Notes (register + printable document)
     erp-so-rtv.html       — Return to vendor / client (non-consignee outbound)
     pwa-so-pick / pwa-so-dispatch / pwa-so-rtv — PWA parity (same tables)

   TABLE GROUPS
   ------------
     GROUP A — Outbound order + lines
       wmsoutbound, wmsoutboundline
     GROUP B — Live allocation (reservation on the order line)
       wmsallocation, wmsallocationserial
     GROUP C — Shipment / Delivery Note (immutable snapshot)
       wmsshipment, wmsshipmentline, wmsshipmentlineserial
     GROUP D — Return-to-vendor / client (RTV)
       wmsrtv, wmsrtvline, wmsrtvlineserial

   KEY DESIGN DECISIONS (resolving the DATA_MODEL / phase-file open questions)
   ---------------------------------------------------------------------------
   * NO pick-task table. The mock generates no separate pick-task entity: the
     saved allocation IS the pick list (Pick/Dispatch and the PWA picker read
     line.alloc[]). Picks are captured on wmsallocation.pickedqty; the order
     status (picking/picked) carries the worklist state. This mirrors Putaway
     (Section 03), which also derives its worklist instead of a task table.
   * wmsallocation = the LIVE reservation (closes DATA_MODEL gap #4: the mock
     kept partial-LPN reservations only on alloc[]). A plate's FREE quantity is
     DERIVED:  free = wmslpn.qty − SUM(wmsallocation.qty of orders in status
     allocated/picking/picked).  The LPN row itself stays 'available' until the
     stock is issued at dispatch. Allocation rows are REMOVED when their round
     is consumed (dispatch — after snapshotting into wmsshipmentline), released
     (back to open) or cancelled; history lives in the shipment snapshot +
     wmstxn ledger, not here.
   * wmsshipment/wmsshipmentline are an IMMUTABLE SNAPSHOT (closes the
     "delivery-note immutability" question: snapshot, never re-derive). One
     shipment = one Delivery Note (code 'DN-{order}-{seq}'); a back-ordered
     order accumulates several. Lot/expiry/location/qty are copied VALUES so a
     reprint always reproduces exactly what shipped (same posture as wmsgrn).
     Ordered-vs-shipped on the printed note reads the ordered qty through
     outboundlineid (master data joins only — never live stock).
   * Serials are EXPLICIT ROWS everywhere (wmsallocationserial at pick,
     wmsshipmentlineserial on the note, wmsrtvlineserial on the RTV) — same
     posture as wmslpnserial / wmsreceiptlineserial (DATA_MODEL gap #2). The
     serial-on-issue guard (count == picked qty, no duplicates — F15) is app
     logic; DDL guarantees per-parent uniqueness.
   * Ad-hoc / emergency dispatch (PWA) creates a NORMAL wmsoutbound row flagged
     adhoc=1 + approvalstatus='pending' with its 'dispatch'-domain reason and
     manual reference — the ERP approval queue (P05-S06 carry-over) is a simple
     WHERE approvalstatus='pending' over this table. No separate ad-hoc table.
   * RTV pre-provisions THREE build enhancements the mock lacks (flagged in
     PHASE_05): a 'cancelled' status + cancel columns (no void path in the
     mock), an optional carrierid (the mock ships with no transport data), and
     shippedby separate from createdby (the mock overwrote the creator at ship).
   * The shared core (02) already lists this section's values — wmslpn.status
     CHECK includes 'allocated'/'picked'/'dispatched' and wmstxn.type CHECK
     includes 'dispatch'/'rtv' — so this file ADDS TABLES ONLY and never ALTERs
     a shipped CHECK (per the 02 convention).
   * Blocking rules (BLOCKING_RULES.md — allocation row) are APP LOGIC, not
     DDL: allocate only available/non-expired/un-frozen/free stock; re-validate
     at commit (C1); serials on issue (F15); consignee+carrier re-assert (F21);
     remainder per client.allowbackorder. The DDL persists what those rules
     decide; it does not enforce them.

   CONVENTIONS HONOURED (identical to 01/02)
   -----------------------------------------
   * Table names lower-case, prefixed "wms"; column names lower-case, no spaces.
   * Every table has id INT IDENTITY(1,1) PRIMARY KEY. Human/business ids
     (OUT-…, DN-…, RTV-…) are a separate unique "code" business-key column.
   * Quantities DECIMAL(18,3); dates DATETIME2; enums VARCHAR + CHECK.
   * No JSON / temporal / 2016+ features. Nested mock arrays become child
     tables (COMMON_DATABASE_RULES.md).
   * Audit columns (createdby/createdat/editby/edittime) on aggregate roots
     only; pure child tables omit them.
   * USER references (createdby/editby/assignee/…by) are INT pointing at
     [dbo].[Users].[Id] LOGICALLY — NOT FK-bound (host identity table).
   * Re-run safe: every CREATE guarded by IF OBJECT_ID(...) IS NULL; NO DROPs.

   HOW TO RUN
   ----------
   USE [WMS];  -- (or the per-agency DMS_xx database)
   -- run 01 + 02 schema files first, then this file, then 05_stock_out_seed.sql.
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   GROUP A — OUTBOUND ORDER  (header + requested lines)
   ============================================================================ */

/* wmsoutbound ------------------------------------------------------------------
   SCREEN : erp-so-orders.html (list + create/edit); worklist source for
            erp-so-alloc (open/allocated/partial), erp-so-dispatch (allocated/
            picking/picked), erp-so-fulfil (open/partial) and erp-so-note
            (shipments); pwa-so-pick / pwa-so-dispatch.
   PURPOSE: A client's request to remove stock — full stock-out or partial by
            line. STATUS IS STORED (unlike the derived ASN status):
              open -> allocated -> picking -> picked -> dispatched
              'partial'   = some shipped, remainder back-ordered (re-enters the
                            allocation/express worklists),
              'cancelled' = order (or its un-shipped remainder) voided,
                            reservations freed.
            "consigneeid" is the SHIP-TO — a delivery point of the OWNING
            client, never the client itself (key 3PL distinction). Required at
            save/dispatch by app guard (F21); nullable here because the printed
            note tolerates a missing consignee ("No consignee recorded").
            App rule (not a composite FK): the consignee MUST belong to
            clientid — enforced on screen (consigneesFor) + server-side.
            "fullstockout" = allocation takes ALL available stock per line
            product at this site; line qty is ignored (NULL). "shortclosed" =
            a short dispatch cancelled the remainder (client without
            back-order); the order still ends 'dispatched'. "dispatchedat" =
            latest dispatch. "carrierid" = optional default carrier (the
            dispatch screen prefills its carrier select from it; the carrier
            that actually shipped lives on each wmsshipment).
            AD-HOC (PWA emergency dispatch, P05-S06): adhoc=1 + a mandatory
            'dispatch'-domain justification (adhocreasonid / wmsreason) + the
            manual reference captured at the governance gate (adhocref) +
            approvalstatus 'pending' -> 'approved'|'rejected' (the ERP
            after-the-fact review queue = WHERE approvalstatus='pending').
            NULL approvalstatus = a normal order (no approval needed).
            CANCEL: cancelledby/cancelledat + cancelreason (the mock's cancel
            captures no reason — pre-provisioned so the build can add one, same
            governance posture as the ASN void). "requestedat" backs the
            editor's Requested-date field (present but unwired in the mock).
            "assignee" = work-item owner (CC-09; dispatch picker on the list). */
IF OBJECT_ID(N'dbo.wmsoutbound', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsoutbound (
        id             INT IDENTITY(1,1) NOT NULL,
        code           VARCHAR(40)   NOT NULL,   -- business key e.g. 'OUT-7001'
        clientid       INT           NOT NULL,   -- stock owner
        siteid         INT           NOT NULL,
        consigneeid    INT           NULL,        -- SHIP-TO (a delivery point of clientid)
        ref            NVARCHAR(80)  NULL,        -- client PO / reference
        status         VARCHAR(20)   NOT NULL CONSTRAINT df_wmsoutbound_status DEFAULT ('open'),
        fullstockout   BIT           NOT NULL CONSTRAINT df_wmsoutbound_full DEFAULT (0),
        shortclosed    BIT           NOT NULL CONSTRAINT df_wmsoutbound_shortclosed DEFAULT (0),
        requestedat    DATETIME2     NULL,        -- requested delivery date (editor field; wire in build)
        dispatchedat   DATETIME2     NULL,        -- date of the LATEST dispatch
        carrierid      INT           NULL,        -- optional default carrier (prefill only)
        adhoc          BIT           NOT NULL CONSTRAINT df_wmsoutbound_adhoc DEFAULT (0),
        approvalstatus VARCHAR(20)   NULL,        -- NULL = normal | 'pending'|'approved'|'rejected' (ad-hoc review)
        adhocreasonid  INT           NULL,        -- -> wmsreason ('dispatch' domain; ad-hoc justification)
        adhocref       NVARCHAR(80)  NULL,        -- manual reference captured at the ad-hoc governance gate
        approvedby     INT           NULL,        -- -> [dbo].[Users].[Id] (ad-hoc reviewer)
        approvedat     DATETIME2     NULL,
        cancelreason   NVARCHAR(200) NULL,        -- pre-provisioned (mock cancel captures no reason)
        cancelledby    INT           NULL,        -- -> [dbo].[Users].[Id]
        cancelledat    DATETIME2     NULL,
        assignee       INT           NULL,        -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        note           NVARCHAR(400) NULL,
        createdby      INT           NULL,
        createdat      DATETIME2     NULL,
        editby         INT           NULL,
        edittime       DATETIME2     NULL,
        CONSTRAINT pk_wmsoutbound PRIMARY KEY (id),
        CONSTRAINT uq_wmsoutbound_code UNIQUE (code),
        CONSTRAINT ck_wmsoutbound_status CHECK (status IN
            ('open','allocated','picking','picked','partial','dispatched','cancelled')),
        CONSTRAINT ck_wmsoutbound_approval CHECK (approvalstatus IS NULL
            OR approvalstatus IN ('pending','approved','rejected')),
        CONSTRAINT fk_wmsoutbound_client    FOREIGN KEY (clientid)      REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsoutbound_site      FOREIGN KEY (siteid)        REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsoutbound_consignee FOREIGN KEY (consigneeid)   REFERENCES dbo.wmsconsignee (id),
        CONSTRAINT fk_wmsoutbound_carrier   FOREIGN KEY (carrierid)     REFERENCES dbo.wmscarrier (id),
        CONSTRAINT fk_wmsoutbound_adhocrsn  FOREIGN KEY (adhocreasonid) REFERENCES dbo.wmsreason (id)
    );
    -- the worklist hot path: every SO screen filters site + status (+ client).
    CREATE INDEX ix_wmsoutbound_site_status ON dbo.wmsoutbound (siteid, status, clientid);
    CREATE INDEX ix_wmsoutbound_client      ON dbo.wmsoutbound (clientid);
    CREATE INDEX ix_wmsoutbound_consignee   ON dbo.wmsoutbound (consigneeid);
    -- the ERP ad-hoc review queue (P05-S06): WHERE approvalstatus='pending' at a site.
    CREATE INDEX ix_wmsoutbound_site_approval ON dbo.wmsoutbound (siteid, approvalstatus);
END
GO

/* wmsoutboundline --------------------------------------------------------------
   SCREEN : erp-so-orders.html (requested lines) + every downstream SO screen.
   PURPOSE: One REQUESTED product line. "qty" = requested base units — NULL when
            the order is full-stock-out (the request literally has no quantity;
            allocation takes everything available). "shipped" = CUMULATIVE base
            units issued across ALL dispatches (maintained as each shipment
            posts); remaining-to-fulfil = qty − shipped, and allocation always
            works on the remainder. "cancelled" = per-line void (restorable in
            the mock): excluded from totals/completion and skipped by
            Allocation / Pick-Dispatch / Express; cancelling a line frees its
            reservations (delete its wmsallocation rows). Line-level photos and
            notes attach via wmsattachment / the notes widget (polymorphic —
            entitycode 'OUT-…:L{n}'), not as columns here. */
IF OBJECT_ID(N'dbo.wmsoutboundline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsoutboundline (
        id          INT IDENTITY(1,1) NOT NULL,
        outboundid  INT           NOT NULL,
        [lineno]      INT           NOT NULL,   -- 1-based position on the order
        productid   INT           NOT NULL,
        qty         DECIMAL(18,3) NULL,         -- requested base units (NULL = full-stock-out order)
        shipped     DECIMAL(18,3) NOT NULL CONSTRAINT df_wmsoutboundline_shipped DEFAULT (0),
        cancelled   BIT           NOT NULL CONSTRAINT df_wmsoutboundline_cancelled DEFAULT (0),
        note        NVARCHAR(200) NULL,
        CONSTRAINT pk_wmsoutboundline PRIMARY KEY (id),
        CONSTRAINT uq_wmsoutboundline_lineno UNIQUE (outboundid, [lineno]),
        CONSTRAINT fk_wmsoutboundline_outbound FOREIGN KEY (outboundid) REFERENCES dbo.wmsoutbound (id),
        CONSTRAINT fk_wmsoutboundline_product  FOREIGN KEY (productid)  REFERENCES dbo.wmsproduct (id)
    );
    CREATE INDEX ix_wmsoutboundline_outbound ON dbo.wmsoutboundline (outboundid);
    CREATE INDEX ix_wmsoutboundline_product  ON dbo.wmsoutboundline (productid);
END
GO

/* ============================================================================
   GROUP B — LIVE ALLOCATION  (the reservation on an order line — the pick list)
   ============================================================================ */

/* wmsallocation ----------------------------------------------------------------
   SCREEN : written by erp-so-alloc.html (Confirm allocation) and the auto-fill
            step of erp-so-fulfil / pwa-so-pick / pwa-so-dispatch; READ as the
            pick list by erp-so-dispatch + the PWA picker ("reserved by the
            office" vs "auto-allocated FEFO").
   PURPOSE: ONE reservation of quantity on ONE plate for ONE order line — the
            CURRENT allocation round. Chosen FEFO (expiry-tracked) or FIFO,
            manually overridable. THIS TABLE IS THE RESERVATION PERSISTENCE
            (closes DATA_MODEL gap #4):
              plate free qty = wmslpn.qty
                             − SUM(a.qty) over wmsallocation a
                               JOIN wmsoutboundline ol ON ol.id=a.outboundlineid
                               JOIN wmsoutbound o ON o.id=ol.outboundid
                               WHERE o.status IN ('allocated','picking','picked')
            The plate itself STAYS status='available' (its qty is decremented
            only at issue). LIFECYCLE: rows are DELETED when the round is
            consumed at dispatch (after snapshotting into wmsshipmentline),
            released (order back to open), or the order/line is cancelled —
            history lives in the shipment snapshot + wmstxn, never here.
            "lot"/"expiry" are copied from the plate at allocation time
            (display + note snapshot source); "fromlocationid" = where the
            plate sat when allocated (the pick-from bin printed on the pick
            list; the mis-pick guard F17b compares the scan against it).
            "pickedqty" = base units actually picked, captured by Save picks /
            the PWA scan flow (0 until then; short pick => pickedqty < qty).
            Serials captured at pick live in wmsallocationserial. */
IF OBJECT_ID(N'dbo.wmsallocation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsallocation (
        id              INT IDENTITY(1,1) NOT NULL,
        outboundlineid  INT           NOT NULL,
        lpnid           INT           NOT NULL,
        lot             NVARCHAR(60)  NULL,        -- copied from the plate (blank when untracked)
        expiry          DATETIME2     NULL,        -- copied from the plate (drives the FEFO display)
        fromlocationid  INT           NULL,        -- pick-from bin at allocation time
        qty             DECIMAL(18,3) NOT NULL,    -- base units RESERVED from this plate
        pickedqty       DECIMAL(18,3) NOT NULL CONSTRAINT df_wmsallocation_picked DEFAULT (0),
        CONSTRAINT pk_wmsallocation PRIMARY KEY (id),
        -- one row per plate per line (the mock's alloc[] has one entry per LPN).
        CONSTRAINT uq_wmsallocation_line_lpn UNIQUE (outboundlineid, lpnid),
        CONSTRAINT fk_wmsallocation_line    FOREIGN KEY (outboundlineid) REFERENCES dbo.wmsoutboundline (id),
        CONSTRAINT fk_wmsallocation_lpn     FOREIGN KEY (lpnid)          REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsallocation_fromloc FOREIGN KEY (fromlocationid) REFERENCES dbo.wmslocation (id)
    );
    -- the reservation-math hot path (lpnAvail / ordersReserving): all rows for a plate.
    CREATE INDEX ix_wmsallocation_lpn  ON dbo.wmsallocation (lpnid);
    CREATE INDEX ix_wmsallocation_line ON dbo.wmsallocation (outboundlineid);
END
GO

/* wmsallocationserial ------------------------------------------------------------
   PURPOSE: Explicit serial rows captured AT PICK on a live allocation (the
            serial-on-issue guard F15: count must equal pickedqty, no
            duplicates — app-enforced). On dispatch they slice onto the
            shipment snapshot (wmsshipmentlineserial) and these rows go with
            their allocation row. Pure child table — no audit columns. */
IF OBJECT_ID(N'dbo.wmsallocationserial', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsallocationserial (
        id            INT IDENTITY(1,1) NOT NULL,
        allocationid  INT          NOT NULL,
        serial        VARCHAR(80)  NOT NULL,
        CONSTRAINT pk_wmsallocationserial PRIMARY KEY (id),
        CONSTRAINT uq_wmsallocationserial UNIQUE (allocationid, serial),
        CONSTRAINT fk_wmsallocationserial_alloc FOREIGN KEY (allocationid) REFERENCES dbo.wmsallocation (id)
    );
END
GO

/* ============================================================================
   GROUP C — SHIPMENT / DELIVERY NOTE  (immutable snapshot; one note per dispatch)
   ============================================================================ */

/* wmsshipment ------------------------------------------------------------------
   SCREEN : minted by the dispatch commit (erp-so-dispatch / erp-so-fulfil /
            pwa-so-pick / pwa-so-dispatch); READ by erp-so-note.html (register
            + printable document, deep-links ?note=DN-… / ?out=OUT-…).
   PURPOSE: ONE dispatched batch of an outbound order == ONE Delivery Note.
            code = 'DN-{orderNumber}-{seq}' (seq starts at 1 per order); a
            back-ordered order accumulates several shipments, each immutable
            once posted (no edit/void path — the register and document are
            read-only). "carrierid" is REQUIRED — the F21 guard blocks a
            dispatch without a carrier on every channel, so the document row is
            born with one. "vehiclereg"/"drivername" pre-provision the note's
            transport block (the mock prints only the carrier; the signature
            grid expects a driver — wire in build). status 'issued' -> 'sent'
            backs the note's "Email to client" action (same lifecycle as
            wmsgrn). The printed document's ship-to / stock-owner / carrier
            blocks resolve via the ORDER's consignee + client and this row's
            carrier; proof-of-load photos + dispatch notes attach to the ORDER
            (wmsattachment entitytype 'outbound'), shown read-only on the note. */
IF OBJECT_ID(N'dbo.wmsshipment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsshipment (
        id            INT IDENTITY(1,1) NOT NULL,
        code          VARCHAR(40)   NOT NULL,   -- business key e.g. 'DN-7000-1'
        outboundid    INT           NOT NULL,
        seq           INT           NOT NULL,   -- 1-based delivery number within the order
        dispatchedat  DATETIME2     NULL,        -- when the stock was issued
        carrierid     INT           NOT NULL,   -- who moves it (F21: required at dispatch)
        vehiclereg    NVARCHAR(40)  NULL,        -- transport detail (build enhancement)
        drivername    NVARCHAR(80)  NULL,        -- transport detail (build enhancement)
        status        VARCHAR(20)   NOT NULL CONSTRAINT df_wmsshipment_status DEFAULT ('issued'),
        issuedby      INT           NULL,        -- -> [dbo].[Users].[Id] (who confirmed the dispatch)
        note          NVARCHAR(400) NULL,
        createdby     INT           NULL,
        createdat     DATETIME2     NULL,
        editby        INT           NULL,
        edittime      DATETIME2     NULL,
        CONSTRAINT pk_wmsshipment PRIMARY KEY (id),
        CONSTRAINT uq_wmsshipment_code UNIQUE (code),
        CONSTRAINT uq_wmsshipment_seq  UNIQUE (outboundid, seq),
        -- lifecycle of the client document: issued (generated) -> sent (emailed to the client).
        CONSTRAINT ck_wmsshipment_status CHECK (status IN ('issued','sent')),
        CONSTRAINT fk_wmsshipment_outbound FOREIGN KEY (outboundid) REFERENCES dbo.wmsoutbound (id),
        CONSTRAINT fk_wmsshipment_carrier  FOREIGN KEY (carrierid)  REFERENCES dbo.wmscarrier (id)
    );
    CREATE INDEX ix_wmsshipment_outbound ON dbo.wmsshipment (outboundid);
    CREATE INDEX ix_wmsshipment_carrier  ON dbo.wmsshipment (carrierid);
END
GO

/* wmsshipmentline --------------------------------------------------------------
   PURPOSE: Immutable line snapshot of the Delivery Note — ONE ROW PER PLATE
            ISSUED (the note's line table renders one row per LPN; a product
            spanning several plates prints several rows, grouped by product).
            Copied VALUES (lot/expiry/from/qty) — deliberately stored rather
            than re-derived, so a reprint reproduces exactly what shipped even
            after the plate mutates (same posture as wmsgrnline).
            "outboundlineid" ties back to the requested line: the printed
            Ordered column and the line-level photo/note refs ('OUT-…:L{n}')
            resolve through it. "reservedqty" = what the allocation round had
            reserved on this plate; "shippedqty" = what was actually picked and
            issued on THIS note (short pick => shippedqty < reservedqty; only
            shippedqty left the building). Serial appendix rows live in
            wmsshipmentlineserial. Pure child table — no audit columns. */
IF OBJECT_ID(N'dbo.wmsshipmentline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsshipmentline (
        id              INT IDENTITY(1,1) NOT NULL,
        shipmentid      INT           NOT NULL,
        [lineno]          INT           NOT NULL,   -- 1-based print order on the note
        outboundlineid  INT           NOT NULL,   -- the requested line this fills
        productid       INT           NOT NULL,
        lpnid           INT           NOT NULL,   -- the plate issued
        lot             NVARCHAR(60)  NULL,        -- snapshot
        expiry          DATETIME2     NULL,        -- snapshot
        fromlocationid  INT           NULL,        -- snapshot: picked-from bin
        reservedqty     DECIMAL(18,3) NOT NULL CONSTRAINT df_wmsshipmentline_res DEFAULT (0),
        shippedqty      DECIMAL(18,3) NOT NULL,   -- base units issued on THIS note
        CONSTRAINT pk_wmsshipmentline PRIMARY KEY (id),
        CONSTRAINT uq_wmsshipmentline_lineno UNIQUE (shipmentid, [lineno]),
        CONSTRAINT fk_wmsshipmentline_shipment FOREIGN KEY (shipmentid)     REFERENCES dbo.wmsshipment (id),
        CONSTRAINT fk_wmsshipmentline_outline  FOREIGN KEY (outboundlineid) REFERENCES dbo.wmsoutboundline (id),
        CONSTRAINT fk_wmsshipmentline_product  FOREIGN KEY (productid)      REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsshipmentline_lpn      FOREIGN KEY (lpnid)          REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsshipmentline_fromloc  FOREIGN KEY (fromlocationid) REFERENCES dbo.wmslocation (id)
    );
    CREATE INDEX ix_wmsshipmentline_shipment ON dbo.wmsshipmentline (shipmentid);
    CREATE INDEX ix_wmsshipmentline_lpn      ON dbo.wmsshipmentline (lpnid);      -- plate genealogy / trace
    CREATE INDEX ix_wmsshipmentline_product  ON dbo.wmsshipmentline (productid);  -- outbound reports
END
GO

/* wmsshipmentlineserial ----------------------------------------------------------
   PURPOSE: The Delivery Note's SERIAL APPENDIX — explicit unique serial rows
            issued with a shipment line (sliced from wmsallocationserial at
            dispatch). Immutable with its parent snapshot; the printed appendix
            reads these rows, never the live plate. Pure child table. */
IF OBJECT_ID(N'dbo.wmsshipmentlineserial', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsshipmentlineserial (
        id              INT IDENTITY(1,1) NOT NULL,
        shipmentlineid  INT          NOT NULL,
        serial          VARCHAR(80)  NOT NULL,
        CONSTRAINT pk_wmsshipmentlineserial PRIMARY KEY (id),
        CONSTRAINT uq_wmsshipmentlineserial UNIQUE (shipmentlineid, serial),
        CONSTRAINT fk_wmsshipmentlineserial_line FOREIGN KEY (shipmentlineid) REFERENCES dbo.wmsshipmentline (id)
    );
    CREATE INDEX ix_wmsshipmentlineserial_serial ON dbo.wmsshipmentlineserial (serial);  -- trace a serial
END
GO

/* ============================================================================
   GROUP D — RETURN-TO-VENDOR / CLIENT (RTV)  (non-consignee outbound)
   ============================================================================ */

/* wmsrtv -----------------------------------------------------------------------
   SCREEN : erp-so-rtv.html (list + create + process/note) + pwa-so-rtv.html
            (scan-confirm & ship).
   PURPOSE: Ship stock OUT of the warehouse back to a SUPPLIER or to the OWNING
            CLIENT (recall / defect / expired / over-delivery) — distinct from
            a customer outbound (no consignee; not an order). The destination
            is TYPED: desttype 'supplier' => destsupplierid set, 'client' =>
            destclientid set (the mock forces destination-client == the owning
            client — app rule, kept out of DDL). One HEADER-level reason from
            the 'rtv' domain (05_stock_out_seed.sql), reasontext free-text
            fallback ("Other (see note)"). Ship issues each line's qty out of
            its plate (plate -> 'dispatched' when emptied) + one 'rtv' wmstxn
            per line, then status 'open' -> 'shipped' + shippedat/shippedby
            (kept SEPARATE from createdby — the mock overwrote the creator at
            ship; this preserves both actors).
            BUILD ENHANCEMENTS PRE-PROVISIONED (gaps flagged in PHASE_05):
            'cancelled' in the status CHECK + cancel columns (the mock has no
            void path for an open RTV) and an optional carrierid (the mock
            ships with no transport data at all — odd for a 3PL document).
            The build must also re-validate each plate at ship (C1 posture:
            still present / not already issued / qty sufficient) — the mock
            silently ships min(line qty, plate qty). "assignee" = work-item
            owner (CC-09). The printable RTV note reads this row + its lines. */
IF OBJECT_ID(N'dbo.wmsrtv', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsrtv (
        id              INT IDENTITY(1,1) NOT NULL,
        code            VARCHAR(40)   NOT NULL,   -- business key e.g. 'RTV-7001'
        clientid        INT           NOT NULL,   -- OWNING client of the returned stock
        siteid          INT           NOT NULL,
        desttype        VARCHAR(20)   NOT NULL,   -- 'supplier' | 'client'
        destsupplierid  INT           NULL,        -- set when desttype='supplier'
        destclientid    INT           NULL,        -- set when desttype='client' (== clientid, app rule)
        reasonid        INT           NULL,        -- -> wmsreason ('rtv' domain)
        reasontext      NVARCHAR(200) NULL,        -- free-text fallback ('Other (see note)')
        carrierid       INT           NULL,        -- transport (build enhancement; mock captures none)
        status          VARCHAR(20)   NOT NULL CONSTRAINT df_wmsrtv_status DEFAULT ('open'),
        shippedat       DATETIME2     NULL,
        shippedby       INT           NULL,        -- -> [dbo].[Users].[Id] (who issued the stock)
        cancelreason    NVARCHAR(200) NULL,        -- pre-provisioned (no void path in the mock)
        cancelledby     INT           NULL,        -- -> [dbo].[Users].[Id]
        cancelledat     DATETIME2     NULL,
        assignee        INT           NULL,        -- -> [dbo].[Users].[Id] (work-item owner; NULL = Any)
        note            NVARCHAR(400) NULL,
        createdby       INT           NULL,
        createdat       DATETIME2     NULL,
        editby          INT           NULL,
        edittime        DATETIME2     NULL,
        CONSTRAINT pk_wmsrtv PRIMARY KEY (id),
        CONSTRAINT uq_wmsrtv_code UNIQUE (code),
        CONSTRAINT ck_wmsrtv_status   CHECK (status IN ('open','shipped','cancelled')),
        CONSTRAINT ck_wmsrtv_desttype CHECK (desttype IN ('supplier','client')),
        -- the typed destination must match desttype (exactly one destination set).
        CONSTRAINT ck_wmsrtv_dest CHECK (
            (desttype = 'supplier' AND destsupplierid IS NOT NULL AND destclientid IS NULL) OR
            (desttype = 'client'   AND destclientid   IS NOT NULL AND destsupplierid IS NULL)),
        CONSTRAINT fk_wmsrtv_client       FOREIGN KEY (clientid)       REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsrtv_site         FOREIGN KEY (siteid)         REFERENCES dbo.wmssite (id),
        CONSTRAINT fk_wmsrtv_destsupplier FOREIGN KEY (destsupplierid) REFERENCES dbo.wmssupplier (id),
        CONSTRAINT fk_wmsrtv_destclient   FOREIGN KEY (destclientid)   REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsrtv_reason       FOREIGN KEY (reasonid)       REFERENCES dbo.wmsreason (id),
        CONSTRAINT fk_wmsrtv_carrier      FOREIGN KEY (carrierid)      REFERENCES dbo.wmscarrier (id)
    );
    CREATE INDEX ix_wmsrtv_site_status ON dbo.wmsrtv (siteid, status, clientid);
    CREATE INDEX ix_wmsrtv_destsupplier ON dbo.wmsrtv (destsupplierid);
    CREATE INDEX ix_wmsrtv_destclient   ON dbo.wmsrtv (destclientid);
END
GO

/* wmsrtvline -------------------------------------------------------------------
   PURPOSE: ONE plate drawn onto an RTV — eligible stock is AVAILABLE OR
            BLOCKED (quarantine/hold/damaged/expired) on-hand plates of the
            owning client at the site (blocked stock is precisely what RTVs
            exist for; terminal statuses never qualify). One plate appears on
            at most one line (uq). "qty" may be a PARTIAL take (clamped 1..
            plate qty on screen); lot/expiry are copied values so the shipped
            RTV note reprints faithfully after the plate mutates. Serials
            carried from the plate live in wmsrtvlineserial. Pure child table. */
IF OBJECT_ID(N'dbo.wmsrtvline', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsrtvline (
        id         INT IDENTITY(1,1) NOT NULL,
        rtvid      INT           NOT NULL,
        [lineno]     INT           NOT NULL,   -- 1-based position on the RTV
        lpnid      INT           NOT NULL,
        productid  INT           NOT NULL,
        qty        DECIMAL(18,3) NOT NULL,    -- base units returned (may be partial)
        lot        NVARCHAR(60)  NULL,         -- snapshot from the plate
        expiry     DATETIME2     NULL,         -- snapshot from the plate
        CONSTRAINT pk_wmsrtvline PRIMARY KEY (id),
        CONSTRAINT uq_wmsrtvline_lineno UNIQUE (rtvid, [lineno]),
        CONSTRAINT uq_wmsrtvline_lpn    UNIQUE (rtvid, lpnid),
        CONSTRAINT fk_wmsrtvline_rtv     FOREIGN KEY (rtvid)     REFERENCES dbo.wmsrtv (id),
        CONSTRAINT fk_wmsrtvline_lpn     FOREIGN KEY (lpnid)     REFERENCES dbo.wmslpn (id),
        CONSTRAINT fk_wmsrtvline_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id)
    );
    CREATE INDEX ix_wmsrtvline_rtv ON dbo.wmsrtvline (rtvid);
    CREATE INDEX ix_wmsrtvline_lpn ON dbo.wmsrtvline (lpnid);
END
GO

/* wmsrtvlineserial ---------------------------------------------------------------
   PURPOSE: Explicit unique serial rows shipped with an RTV line (copied from
            the plate at line creation; printed on the RTV note's Serial(s)
            column). Pure child table — no audit columns. */
IF OBJECT_ID(N'dbo.wmsrtvlineserial', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsrtvlineserial (
        id         INT IDENTITY(1,1) NOT NULL,
        rtvlineid  INT          NOT NULL,
        serial     VARCHAR(80)  NOT NULL,
        CONSTRAINT pk_wmsrtvlineserial PRIMARY KEY (id),
        CONSTRAINT uq_wmsrtvlineserial UNIQUE (rtvlineid, serial),
        CONSTRAINT fk_wmsrtvlineserial_line FOREIGN KEY (rtvlineid) REFERENCES dbo.wmsrtvline (id)
    );
END
GO

/* ============================================================================
   END OF STOCK-OUT SCHEMA
   ----------------------------------------------------------------------------
   WMS tables created (10):
     Outbound order : wmsoutbound, wmsoutboundline
     Allocation     : wmsallocation, wmsallocationserial
     Delivery note  : wmsshipment, wmsshipmentline, wmsshipmentlineserial
     RTV            : wmsrtv, wmsrtvline, wmsrtvlineserial

   Referenced (01 Master Data): wmsclient, wmssite, wmsconsignee, wmscarrier,
     wmssupplier, wmsproduct, wmslocation, wmsreason.
   Referenced (02 shared core): wmslpn. Every dispatch/RTV issue also APPENDS
     to wmstxn (types 'dispatch' / 'rtv' — already in 02's CHECK) and evidence
     photos land in wmsattachment (entitytype 'outbound' / 'rtv') — no new
     columns needed there.
   Referenced logically (NOT FK-bound): [dbo].[Users] (all *by / assignee).

   DERIVED, DELIBERATELY NOT STORED:
     * Plate free quantity  = wmslpn.qty − SUM(live wmsallocation.qty)   (gap #4)
     * Order progress/totals (requested / allocated / picked / shipped /
       remaining) = aggregates over lines + allocations + shipments.
     * The Pick/Dispatch worklist = wmsoutbound WHERE status IN
       ('allocated','picking','picked') — no pick-task table (see header).

   NOT in this file (by design): views and stored procedures — built per-screen
   during the dev cards. Reference/seed rows live in 05_stock_out_seed.sql
   (the 'rtv' reason domain; the 'dispatch' ad-hoc domain was seeded in 01).

   RECONCILIATION PASS (2026-07-05) — authored field-by-field against the 6 ERP
   mockups (erp-so-orders / alloc / dispatch / fulfil / note / rtv), the PWA
   sweep notes in docs/04_Stock_Out.md, DATA_MODEL.md §Outbound/§Allocation,
   BLOCKING_RULES.md (allocation row) and every logTxn()/status mutation in
   mockups/assets/data.js (outReserved / lpnAvail / fefoAllocate / dispatchGuard
   / validateSerials / pickReject / rtvIssue). Decisions vs the mock recorded
   above: no pick-task table; allocation rows deleted on consume/release;
   snapshot delivery notes; explicit serial rows; ad-hoc as flags on the order;
   RTV cancel/carrier/shippedby pre-provisioned as flagged build enhancements.
   NOT yet executed against a live SQL Server 2014 instance.
   ============================================================================ */
