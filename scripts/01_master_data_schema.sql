/* ============================================================================
   WMS (3PL) — DATABASE SCHEMA
   SECTION 01: MASTER DATA  (tables only — NO views, NO procedures)
   ----------------------------------------------------------------------------
   Target engine : Microsoft SQL Server 2014  (hard constraint)
   Module        : WMS — client-owned stock in a 3PL warehouse
   Scope of file : EVERY table the Master Data section needs. Operational
                   sections (Goods Reception, Putaway, Stock-Out, Inventory
                   Operations, Reports) are intentionally OUT of this file and
                   will be scripted in their own files later.

   WHY this file exists
   --------------------
   Master Data is the foundation reference data every other process depends on:
   the clients whose stock is held, the warehouse network, the products (per
   client), how goods are measured/packaged/barcoded, segregation policy, the
   reason vocabulary, and how users are scoped to sites/clients. Nothing can be
   received, stored, or shipped before these rows exist.

   EACH TABLE'S COMMENT states (per the deliverable constraints):
     * WHICH Master Data screen(s) create/consume it, and
     * WHY the table exists / what it serves for.
   Master Data ERP screens (mockups/erp-md-*.html):
     clients · consignees · sites · locations · products · partners
     (suppliers+carriers) · categories · reasons · uom (UoM & packaging) ·
     users · clientmap (client-user mapping) · import (bulk CSV).
   PWA read-only lookups: pwa-md-lookup-loc.html · pwa-md-lookup-prod.html.

   Functional source of truth : ../docs/01_Master_Data.md, ../docs/DATA_MODEL.md,
                                 ../docs/GLOSSARY.md
   Persistence rules          : ../delivery/00-common-rules/COMMON_DATABASE_RULES.md

   CONVENTIONS HONOURED (per the project constraints for this deliverable)
   -----------------------------------------------------------------------
   * Every table name is lower-case and prefixed "wms"            (e.g. wmsclient).
   * Every column name is lower-case, no spaces.
   * Every table has an "id" column = INT IDENTITY(1,1) PRIMARY KEY (auto-increment).
   * Human/business ids (C-…, S-…, LOC-…, P-…, etc.) are kept as a separate
     "code" business-key column (unique per scope) — they are NOT the PK.

   USERS — NOT CREATED HERE (host-owned)
   -------------------------------------
   The user master ALREADY EXISTS as the host identity table [dbo].[Users]
   (Id, UserName, Email, Password, FirstName, LastName, IsActive, EditTime,
   Photo, IsBlocked). This script does NOT (re)create it — it REFERENCES it.
   An "active user" in the host is: (IsBlocked IS NULL OR IsBlocked = 0)
   AND (IsActive = 1).  Because the shared Auth table must not be altered, the
   WMS-specific user attributes (WMS role + all-sites/all-clients flags) live in
   the WMS-owned extension table wmsuserprofile, and a user's explicit
   site/client scope lives in wmsusersite / wmsuserclient. All reference
   [dbo].[Users].[Id].

   SQL SERVER 2014 NOTES (designed around the engine's limits)
   -----------------------------------------------------------
   * No JSON columns / OPENJSON (2016+) -> the mock dataset's nested arrays
     (site.levels[], site.areas[], packaging.levels[], product.preferred[],
     reasonDomain.groups[].reasons[], location.path{}, user scope) are modelled
     as proper CHILD TABLES with foreign keys.
   * No system-versioned temporal tables (2016+) -> change tracking is via the
     plain audit columns below (and, operationally, the WMS transaction ledger
     which belongs to a later file).
   * Quantities/weights use DECIMAL(18,3) (never FLOAT); dates use DATETIME2;
     enumerations are persisted as their string codes guarded by CHECK
     constraints (matching the enum values documented in DATA_MODEL.md).

   AUDIT COLUMNS
   -------------
   Aggregate-root tables carry: createdby, createdat, editby, edittime.
   createdby / editby are INT and reference [dbo].[Users].[Id] logically
   (NOT FK-bound, so user rows can be deactivated without blocking and to avoid a
   load-order dependency on the host table). Pure child / link tables omit audit
   columns — they are written and rewritten within their parent's unit of work.

   RE-RUN SAFETY
   -------------
   Each CREATE is guarded by IF OBJECT_ID(...) IS NULL so the script can be run
   repeatedly without error. It contains NO DROP statements (non-destructive).

   HOW TO RUN
   ----------
   Select your WMS database first, e.g.  USE [WMS];  then execute this file.
   The host [dbo].[Users] table must already exist (it does in the host ERP).
   ============================================================================ */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   GROUP 1 — SYSTEM / LOOKUP TABLES (no dependencies)
   ============================================================================ */

/* wmssetting -----------------------------------------------------------------
   SCREEN : erp-md-sites.html  (the system-wide "Client–area segregation" toggle
            is rendered + saved here).
   PURPOSE: System-wide configuration as key/value rows. Holds the single most
            important policy switch for this client — clientareasegregation
            (CONFIRMED ON: different clients' stock must never share a location;
            read by putaway/move/transfer/returns segregation enforcement). Also
            the natural home for any other global toggle the deployment needs. */
IF OBJECT_ID(N'dbo.wmssetting', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmssetting (
        id            INT IDENTITY(1,1) NOT NULL,
        settingkey    VARCHAR(80)   NOT NULL,   -- e.g. 'clientAreaSegregation'
        settingvalue  NVARCHAR(400) NULL,       -- stored as text; interpreted per valuetype
        valuetype     VARCHAR(20)   NULL,        -- 'bool' | 'int' | 'string'
        description   NVARCHAR(400) NULL,
        createdby     INT           NULL,
        createdat     DATETIME2     NULL,
        editby        INT           NULL,
        edittime      DATETIME2     NULL,
        CONSTRAINT pk_wmssetting PRIMARY KEY (id),
        CONSTRAINT uq_wmssetting_settingkey UNIQUE (settingkey)
    );
END
GO

/* wmsuom ---------------------------------------------------------------------
   SCREEN : erp-md-uom.html  ("Units of Measure" tab).
   PURPOSE: Units of Measure — a GLOBAL master shared by all clients. "isbase"
            marks the base unit of its measurement category; "allowdecimal"
            permits fractional quantities. Referenced by every packaging level
            (wmspackaginglevel.uomid) and aligns to a product's base-unit label. */
IF OBJECT_ID(N'dbo.wmsuom', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsuom (
        id            INT IDENTITY(1,1) NOT NULL,
        code          VARCHAR(20)  NOT NULL,    -- business key e.g. 'EA','KG','PAL'
        name          NVARCHAR(80) NOT NULL,
        category      VARCHAR(20)  NOT NULL,    -- Count|Weight|Volume|Length|Packaging
        isbase        BIT          NOT NULL CONSTRAINT df_wmsuom_isbase DEFAULT (0),
        allowdecimal  BIT          NOT NULL CONSTRAINT df_wmsuom_allowdecimal DEFAULT (0),
        createdby     INT          NULL,
        createdat     DATETIME2    NULL,
        editby        INT          NULL,
        edittime      DATETIME2    NULL,
        CONSTRAINT pk_wmsuom PRIMARY KEY (id),
        CONSTRAINT uq_wmsuom_code UNIQUE (code),
        CONSTRAINT ck_wmsuom_category CHECK (category IN ('Count','Weight','Volume','Length','Packaging'))
    );
    -- At most ONE base unit per measurement category (Count/Weight/Volume/Length each have one;
    -- Packaging legitimately has none). Filtered unique index — supported on SQL Server 2014.
    CREATE UNIQUE INDEX uq_wmsuom_onebase ON dbo.wmsuom (category) WHERE isbase = 1;
END
GO

/* wmsdefaultsitelevel --------------------------------------------------------
   SCREEN : erp-md-sites.html  (seeds a NEW site's addressing levels; the
            "Reset to default" action on the location-structure editor reads it).
   PURPOSE: The DEFAULT ordered addressing levels (Zone -> Aisle -> Rack -> Bin)
            applied to a brand-new site before the user edits that site's actual
            levels (wmssitelevel). This is the seed template, not a per-site list. */
IF OBJECT_ID(N'dbo.wmsdefaultsitelevel', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsdefaultsitelevel (
        id          INT IDENTITY(1,1) NOT NULL,
        levelorder  INT          NOT NULL,    -- 1-based position in the addressing path
        levelname   NVARCHAR(40) NOT NULL,    -- e.g. 'Zone','Aisle','Rack','Bin'
        CONSTRAINT pk_wmsdefaultsitelevel PRIMARY KEY (id),
        CONSTRAINT uq_wmsdefaultsitelevel_order UNIQUE (levelorder)
    );
END
GO

/* ============================================================================
   GROUP 2 — PRODUCT TAXONOMY (global, cross-client — same posture as UoM)
   ============================================================================ */

/* wmscategory ----------------------------------------------------------------
   SCREEN : erp-md-categories.html  (authored here). Also consumed as a picker on
            erp-md-products.html (product category) and erp-md-sites.html (Area
            preferred-categories affinity).
   PURPOSE: Top level of the GLOBAL product taxonomy (belongs to no client).
            Drives Area slotting affinity for directed putaway and reporting. */
IF OBJECT_ID(N'dbo.wmscategory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmscategory (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,    -- business key e.g. 'CAT-FB'
        name        NVARCHAR(120) NOT NULL,
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmscategory PRIMARY KEY (id),
        CONSTRAINT uq_wmscategory_code UNIQUE (code)
    );
END
GO

/* wmssubcategory -------------------------------------------------------------
   SCREEN : erp-md-categories.html  (sub-rows under each category). Consumed as a
            picker on erp-md-products.html and erp-md-sites.html (Area
            preferred-sub-categories).
   PURPOSE: Second level of the global taxonomy; each sub-category belongs to
            exactly one category. (Mock array: category.subs[].) */
IF OBJECT_ID(N'dbo.wmssubcategory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmssubcategory (
        id          INT IDENTITY(1,1) NOT NULL,
        categoryid  INT           NOT NULL,
        code        VARCHAR(40)   NOT NULL,    -- business key e.g. 'SUB-OIL'
        name        NVARCHAR(120) NOT NULL,
        CONSTRAINT pk_wmssubcategory PRIMARY KEY (id),
        CONSTRAINT uq_wmssubcategory_code UNIQUE (code),
        CONSTRAINT fk_wmssubcategory_category FOREIGN KEY (categoryid) REFERENCES dbo.wmscategory (id)
    );
    CREATE INDEX ix_wmssubcategory_categoryid ON dbo.wmssubcategory (categoryid);
END
GO

/* ============================================================================
   GROUP 3 — CLIENTS & TRADING PARTNERS
   ============================================================================ */

/* wmsclient ------------------------------------------------------------------
   SCREEN : erp-md-clients.html  (list + create/edit, incl. the operating-sites
            multi-select). Also the client picker used across erp-md-consignees,
            erp-md-products, erp-md-sites (Area owning-clients) and
            erp-md-clientmap.
   PURPOSE: The stock owner / principal. In a 3PL the goods belong to the client,
            never to the operator's balance sheet. "allowbackorder" is the
            outbound short-shipment policy (0 = short-close: ship what's there and
            cancel the rest; 1 = back-order: remainder stays open and re-allocates
            when stock arrives). Operating sites are linked via wmsclientsite. */
IF OBJECT_ID(N'dbo.wmsclient', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsclient (
        id              INT IDENTITY(1,1) NOT NULL,
        code            VARCHAR(40)   NOT NULL,   -- business key e.g. 'C-ACME'
        name            NVARCHAR(160) NOT NULL,
        legalname       NVARCHAR(200) NULL,
        contact         NVARCHAR(120) NULL,
        email           NVARCHAR(160) NULL,
        phone           VARCHAR(40)   NULL,
        country         NVARCHAR(80)  NULL,
        allowbackorder  BIT           NOT NULL CONSTRAINT df_wmsclient_allowbackorder DEFAULT (0),
        status          VARCHAR(20)   NOT NULL CONSTRAINT df_wmsclient_status DEFAULT ('active'),
        createdby       INT           NULL,
        createdat       DATETIME2     NULL,
        editby          INT           NULL,
        edittime        DATETIME2     NULL,
        CONSTRAINT pk_wmsclient PRIMARY KEY (id),
        CONSTRAINT uq_wmsclient_code UNIQUE (code),
        CONSTRAINT ck_wmsclient_status CHECK (status IN ('active','inactive'))
    );
END
GO

/* wmssupplier ----------------------------------------------------------------
   SCREEN : erp-md-partners.html  ("Suppliers" tab).
   PURPOSE: GLOBAL trading-partner master — the source of inbound goods,
            referenced on an ASN header in Goods Reception. Shared across all
            clients. */
IF OBJECT_ID(N'dbo.wmssupplier', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmssupplier (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'SUP-100'
        name        NVARCHAR(160) NOT NULL,
        contact     NVARCHAR(120) NULL,
        email       NVARCHAR(160) NULL,
        phone       VARCHAR(40)   NULL,
        country     NVARCHAR(80)  NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmssupplier_status DEFAULT ('active'),
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmssupplier PRIMARY KEY (id),
        CONSTRAINT uq_wmssupplier_code UNIQUE (code),
        CONSTRAINT ck_wmssupplier_status CHECK (status IN ('active','inactive'))
    );
END
GO

/* wmscarrier -----------------------------------------------------------------
   SCREEN : erp-md-partners.html  ("Carriers" tab).
   PURPOSE: GLOBAL trading-partner master — who physically moves stock OUT.
            Recorded on a dispatch shipment and printed on the delivery note.
            "scac" = standard carrier code; "mode" = service/mode (e.g. 'Road',
            'Road · 2-8 C'). Shared across all clients. */
IF OBJECT_ID(N'dbo.wmscarrier', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmscarrier (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'CAR-EFR'
        name        NVARCHAR(160) NOT NULL,
        scac        VARCHAR(20)   NULL,
        mode        NVARCHAR(60)  NULL,
        contact     NVARCHAR(120) NULL,
        phone       VARCHAR(40)   NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmscarrier_status DEFAULT ('active'),
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmscarrier PRIMARY KEY (id),
        CONSTRAINT uq_wmscarrier_code UNIQUE (code),
        CONSTRAINT ck_wmscarrier_status CHECK (status IN ('active','inactive'))
    );
END
GO

/* wmsconsignee ---------------------------------------------------------------
   SCREEN : erp-md-consignees.html  (list + create/edit, client-scoped).
   PURPOSE: A client's ship-to / delivery point (its store, hospital, end
            customer). KEY 3PL DISTINCTION: an outbound order ships to a
            CONSIGNEE, NOT to the owning client — the client owns the stock, the
            consignee is where it is delivered. (Mock array: consignees[].) */
IF OBJECT_ID(N'dbo.wmsconsignee', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsconsignee (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'CNE-AC01'
        clientid    INT           NOT NULL,   -- owning client scope
        name        NVARCHAR(160) NOT NULL,
        address     NVARCHAR(200) NULL,
        city        NVARCHAR(80)  NULL,
        country     NVARCHAR(80)  NULL,
        contact     NVARCHAR(120) NULL,
        phone       VARCHAR(40)   NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmsconsignee_status DEFAULT ('active'),
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmsconsignee PRIMARY KEY (id),
        CONSTRAINT uq_wmsconsignee_code UNIQUE (code),
        CONSTRAINT ck_wmsconsignee_status CHECK (status IN ('active','inactive')),
        CONSTRAINT fk_wmsconsignee_client FOREIGN KEY (clientid) REFERENCES dbo.wmsclient (id)
    );
    CREATE INDEX ix_wmsconsignee_clientid ON dbo.wmsconsignee (clientid);
END
GO

/* ============================================================================
   GROUP 4 — SITES, ADDRESSING LEVELS, STORAGE AREAS, LOCATIONS
   ============================================================================ */

/* wmssite --------------------------------------------------------------------
   SCREEN : erp-md-sites.html  (list + create/edit). Also the site picker on
            erp-md-clients.html (operating-sites multi-select),
            erp-md-locations.html, erp-md-products.html (preferred storage), and
            user site-scope (erp-md-users.html).
   PURPOSE: A physical warehouse/facility. Owns (a) its ordered addressing levels
            (wmssitelevel) and (b) its list of Storage Areas (wmsstoragearea).
            "type" is free text (e.g. 'Distribution Centre', 'Cross-dock Hub'). */
IF OBJECT_ID(N'dbo.wmssite', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmssite (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'S-LYON'
        name        NVARCHAR(120) NOT NULL,
        city        NVARCHAR(80)  NULL,
        country     NVARCHAR(80)  NULL,
        type        NVARCHAR(60)  NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmssite_status DEFAULT ('active'),
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmssite PRIMARY KEY (id),
        CONSTRAINT uq_wmssite_code UNIQUE (code),
        CONSTRAINT ck_wmssite_status CHECK (status IN ('active','inactive'))
    );
END
GO

/* wmsclientsite --------------------------------------------------------------
   SCREEN : erp-md-clients.html  (the "operating sites" multi-select on the client
            form). Read back on erp-md-products.html / erp-md-locations.html to
            limit a client's products + preferred storage to its sites.
   PURPOSE: Many-to-many link: which operating sites a client uses. Scopes the
            client's products, stock and preferred storage. (Mock: client.sites[].) */
IF OBJECT_ID(N'dbo.wmsclientsite', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsclientsite (
        id          INT IDENTITY(1,1) NOT NULL,
        clientid    INT NOT NULL,
        siteid      INT NOT NULL,
        CONSTRAINT pk_wmsclientsite PRIMARY KEY (id),
        CONSTRAINT uq_wmsclientsite UNIQUE (clientid, siteid),
        CONSTRAINT fk_wmsclientsite_client FOREIGN KEY (clientid) REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsclientsite_site   FOREIGN KEY (siteid)   REFERENCES dbo.wmssite (id)
    );
    CREATE INDEX ix_wmsclientsite_siteid ON dbo.wmsclientsite (siteid);
END
GO

/* wmssitelevel ---------------------------------------------------------------
   SCREEN : erp-md-sites.html  (the per-site "location-structure editor"). Read by
            erp-md-locations.html to render the location's level fields DYNAMICALLY
            and by pwa-md-lookup-loc.html when showing a location's path.
   PURPOSE: The ordered addressing path for ONE site (e.g.
            Floor->Zone->Aisle->Rack->Bin, or just Zone->Aisle). PURE ADDRESSING —
            never used for slotting or ownership (that is the Storage Area's job).
            Depth and names are per-site, not fixed. Level names are UNIQUE within a
            site (uq_wmssitelevel_name) because a location's path values are keyed by
            level name in wmslocationpath. (Mock array: site.levels[].) */
IF OBJECT_ID(N'dbo.wmssitelevel', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmssitelevel (
        id          INT IDENTITY(1,1) NOT NULL,
        siteid      INT          NOT NULL,
        levelorder  INT          NOT NULL,    -- 1-based position in the path
        levelname   NVARCHAR(40) NOT NULL,
        CONSTRAINT pk_wmssitelevel PRIMARY KEY (id),
        CONSTRAINT uq_wmssitelevel_order UNIQUE (siteid, levelorder),
        CONSTRAINT uq_wmssitelevel_name  UNIQUE (siteid, levelname),
        CONSTRAINT fk_wmssitelevel_site FOREIGN KEY (siteid) REFERENCES dbo.wmssite (id)
    );
END
GO

/* wmsstoragearea -------------------------------------------------------------
   SCREEN : erp-md-sites.html  ("Storage areas (slotting & segregation)" editor).
            Consumed by erp-md-locations.html (assign each storage bin to an area)
            and erp-md-products.html (preferred-area storage mode).
   PURPOSE: A managed, per-site logical grouping for SLOTTING + SEGREGATION,
            decoupled from the addressing path (renaming/restructuring levels never
            affects it). "code" is unique within the site (e.g. 'A','B','C'). An
            area carries category affinity (wmsareacategory / wmsareasubcategory)
            and optional owning clients (wmsareaclient). (Mock: site.areas[].) */
IF OBJECT_ID(N'dbo.wmsstoragearea', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsstoragearea (
        id          INT IDENTITY(1,1) NOT NULL,
        siteid      INT          NOT NULL,
        code        VARCHAR(20)  NOT NULL,    -- unique within the site
        name        NVARCHAR(120) NOT NULL,
        CONSTRAINT pk_wmsstoragearea PRIMARY KEY (id),
        CONSTRAINT uq_wmsstoragearea_code UNIQUE (siteid, code),
        -- composite-FK target: lets wmslocation / wmsproductpreferred enforce that a chosen
        -- area belongs to the SAME site (id is already unique, so (id,siteid) is trivially so).
        CONSTRAINT uq_wmsstoragearea_idsite UNIQUE (id, siteid),
        CONSTRAINT fk_wmsstoragearea_site FOREIGN KEY (siteid) REFERENCES dbo.wmssite (id)
    );
END
GO

/* wmsareacategory ------------------------------------------------------------
   SCREEN : erp-md-sites.html  (an area's "preferred categories" multi-select).
   PURPOSE: Slotting affinity — the categories an Area prefers to hold (feeds the
            directed-putaway category ranking). (Mock: area.preferredCategories[].) */
IF OBJECT_ID(N'dbo.wmsareacategory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsareacategory (
        id          INT IDENTITY(1,1) NOT NULL,
        areaid      INT NOT NULL,
        categoryid  INT NOT NULL,
        CONSTRAINT pk_wmsareacategory PRIMARY KEY (id),
        CONSTRAINT uq_wmsareacategory UNIQUE (areaid, categoryid),
        CONSTRAINT fk_wmsareacategory_area     FOREIGN KEY (areaid)     REFERENCES dbo.wmsstoragearea (id),
        CONSTRAINT fk_wmsareacategory_category FOREIGN KEY (categoryid) REFERENCES dbo.wmscategory (id)
    );
    CREATE INDEX ix_wmsareacategory_categoryid ON dbo.wmsareacategory (categoryid);
END
GO

/* wmsareasubcategory ---------------------------------------------------------
   SCREEN : erp-md-sites.html  (an area's "preferred sub-categories" multi-select).
   PURPOSE: Finer slotting affinity at the sub-category level.
            (Mock: area.preferredSubCategories[].) */
IF OBJECT_ID(N'dbo.wmsareasubcategory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsareasubcategory (
        id             INT IDENTITY(1,1) NOT NULL,
        areaid         INT NOT NULL,
        subcategoryid  INT NOT NULL,
        CONSTRAINT pk_wmsareasubcategory PRIMARY KEY (id),
        CONSTRAINT uq_wmsareasubcategory UNIQUE (areaid, subcategoryid),
        CONSTRAINT fk_wmsareasubcategory_area FOREIGN KEY (areaid)        REFERENCES dbo.wmsstoragearea (id),
        CONSTRAINT fk_wmsareasubcategory_sub  FOREIGN KEY (subcategoryid) REFERENCES dbo.wmssubcategory (id)
    );
    CREATE INDEX ix_wmsareasubcategory_subcategoryid ON dbo.wmsareasubcategory (subcategoryid);
END
GO

/* wmsareaclient --------------------------------------------------------------
   SCREEN : erp-md-sites.html  (the "Owning client(s)" chips on each storage area).
   PURPOSE: SEGREGATION — the set of clients allowed in an Area. NO rows = the
            area is unowned / shared (any client). One or more rows = the area is
            reserved for that set of clients. Enforced server-side on every
            bin-write only when wmssetting clientareasegregation = ON (CONFIRMED ON
            for this client). (Mock array: area.owningClients[].) */
IF OBJECT_ID(N'dbo.wmsareaclient', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsareaclient (
        id          INT IDENTITY(1,1) NOT NULL,
        areaid      INT NOT NULL,
        clientid    INT NOT NULL,
        CONSTRAINT pk_wmsareaclient PRIMARY KEY (id),
        CONSTRAINT uq_wmsareaclient UNIQUE (areaid, clientid),
        CONSTRAINT fk_wmsareaclient_area   FOREIGN KEY (areaid)   REFERENCES dbo.wmsstoragearea (id),
        CONSTRAINT fk_wmsareaclient_client FOREIGN KEY (clientid) REFERENCES dbo.wmsclient (id)
    );
END
GO

/* wmslocation ----------------------------------------------------------------
   SCREEN : erp-md-locations.html  (list + create/edit: type, area assignment incl.
            bulk-assign, capacity limits, system ID + structured code + user ref +
            label preview). Also bulk-loaded via erp-md-import.html and looked up
            read-only by the floor on pwa-md-lookup-loc.html.
   PURPOSE: A physical spot in a site. Identity is the permanent, scannable "code"
            (the System ID, LOC-…) which never changes on relabel/restructure — all
            stock and audit history reference it. "structuredcode" is the
            human-readable code derived from the addressing path (regenerable);
            "userref" is an optional free label. "type" controls function. Storage
            bins are assigned to one Area (areaid) and may carry optional capacity
            limits (enforced at PUTAWAY only, never as a master-data block; any
            unset limit = unlimited). */
IF OBJECT_ID(N'dbo.wmslocation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmslocation (
        id              INT IDENTITY(1,1) NOT NULL,
        code            VARCHAR(40)   NOT NULL,   -- System ID e.g. 'LOC-A0101' (permanent, scannable)
        siteid          INT           NOT NULL,
        type            VARCHAR(20)   NOT NULL,   -- storage|wait/put|dispatch|quarantine
        structuredcode  NVARCHAR(80)  NOT NULL,    -- derived human code e.g. '1-A-01-R1-B01' (always computed at save)
        userref         NVARCHAR(120) NULL,
        areaid          INT           NULL,        -- storage bins only -> wmsstoragearea
        maxweightkg     DECIMAL(18,3) NULL,        -- capacity (unset = unlimited)
        maxunits        DECIMAL(18,3) NULL,        -- capacity (unset = unlimited)
        maxlpns         INT           NULL,        -- pallet/LPN slots (unset = unlimited)
        status          VARCHAR(20)   NOT NULL CONSTRAINT df_wmslocation_status DEFAULT ('active'),
        createdby       INT           NULL,
        createdat       DATETIME2     NULL,
        editby          INT           NULL,
        edittime        DATETIME2     NULL,
        CONSTRAINT pk_wmslocation PRIMARY KEY (id),
        CONSTRAINT uq_wmslocation_code UNIQUE (code),
        CONSTRAINT ck_wmslocation_type CHECK (type IN ('storage','wait/put','dispatch','quarantine')),
        CONSTRAINT ck_wmslocation_status CHECK (status IN ('active','inactive')),
        CONSTRAINT uq_wmslocation_idsite UNIQUE (id, siteid),   -- composite-FK target for wmsproductpreferred
        CONSTRAINT fk_wmslocation_site FOREIGN KEY (siteid) REFERENCES dbo.wmssite (id),
        -- composite FK: a storage bin's area MUST belong to the SAME site. When areaid is NULL
        -- (non-storage location) the FK is not checked, so staging/dispatch/quarantine are exempt.
        -- Guards directed slotting + client-area segregation (a CONFIRMED requirement).
        CONSTRAINT fk_wmslocation_area FOREIGN KEY (areaid, siteid) REFERENCES dbo.wmsstoragearea (id, siteid)
    );
    CREATE INDEX ix_wmslocation_siteid ON dbo.wmslocation (siteid);
    CREATE INDEX ix_wmslocation_areaid ON dbo.wmslocation (areaid);
END
GO

/* wmslocationpath ------------------------------------------------------------
   SCREEN : erp-md-locations.html  (the dynamic per-level fields rendered from the
            site's levels, used to compute the structured code + label preview).
   PURPOSE: The addressing-path VALUE per level for a location (e.g. Floor='1',
            Zone='A', Aisle='01', Rack='R1', Bin='B01'). Because each site defines
            its own levels, the path is a child table keyed by level name rather
            than fixed columns. (Mock object: location.path{}.) */
IF OBJECT_ID(N'dbo.wmslocationpath', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmslocationpath (
        id          INT IDENTITY(1,1) NOT NULL,
        locationid  INT          NOT NULL,
        levelname   NVARCHAR(40) NOT NULL,    -- matches a wmssitelevel.levelname of the site
        levelvalue  NVARCHAR(40) NOT NULL,
        CONSTRAINT pk_wmslocationpath PRIMARY KEY (id),
        CONSTRAINT uq_wmslocationpath UNIQUE (locationid, levelname),
        CONSTRAINT fk_wmslocationpath_location FOREIGN KEY (locationid) REFERENCES dbo.wmslocation (id)
    );
END
GO

/* ============================================================================
   GROUP 5 — PRODUCTS, PREFERRED STORAGE, PACKAGING
   ============================================================================ */

/* wmsproduct -----------------------------------------------------------------
   SCREEN : erp-md-products.html  (list + create/edit: tracking flags, category /
            sub-category, weight, base unit, barcode, preferred storage). Also bulk
            loaded via erp-md-import.html and looked up read-only on
            pwa-md-lookup-prod.html.
   PURPOSE: The SKU master, scoped PER CLIENT (the same physical SKU under two
            clients = two distinct rows; "sku" unique per client). Tracking flags
            drive show/hide of Lot/Expiry/Serial on EVERY downstream screen and are
            the single source of truth for genealogy capture: lot + expiry default
            ON, serial OFF (serials are scanned off the unit, not minted). RULE:
            expiry implies lot (ck_…_track). "weightkg" is the BASE-unit weight
            feeding putaway capacity math. "baseuom" is the base unit label (free
            text aligning to a wmsuom.code). "testcase" is a demo-only
            tracking-profile tag (A-D) carried from the mock dataset. Preferred home
            storage lives in wmsproductpreferred; packaging in wmspackaging. */
IF OBJECT_ID(N'dbo.wmsproduct', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsproduct (
        id             INT IDENTITY(1,1) NOT NULL,
        code           VARCHAR(40)   NOT NULL,   -- business key e.g. 'P-1001'
        clientid       INT           NOT NULL,
        sku            VARCHAR(60)   NOT NULL,
        name           NVARCHAR(200) NOT NULL,
        baseuom        NVARCHAR(40)  NOT NULL,    -- base unit label e.g. 'each','vial' (free text; aligns to a wmsuom.code, NOT an FK)
        barcode        VARCHAR(60)   NULL,        -- base-unit barcode (per-level barcodes live on wmspackaginglevel)
        categoryid     INT           NULL,
        subcategoryid  INT           NULL,
        weightkg       DECIMAL(18,3) NULL,        -- base-unit weight (feeds putaway capacity math)
        -- physical attributes (spec 01_Master_Data In-Scope; no mock seed -> NULL until captured)
        lengthcm       DECIMAL(18,3) NULL,        -- base-unit dimensions
        widthcm        DECIMAL(18,3) NULL,
        heightcm       DECIMAL(18,3) NULL,
        hazmatclass    NVARCHAR(40)  NULL,        -- hazard / dangerous-goods class
        storageconditions NVARCHAR(120) NULL,     -- temperature / storage conditions e.g. '2-8 C' (cold-chain)
        tracklot       BIT           NOT NULL CONSTRAINT df_wmsproduct_tracklot DEFAULT (1),
        trackexpiry    BIT           NOT NULL CONSTRAINT df_wmsproduct_trackexpiry DEFAULT (1),
        trackserial    BIT           NOT NULL CONSTRAINT df_wmsproduct_trackserial DEFAULT (0),
        testcase       VARCHAR(4)    NULL,        -- demo tracking-profile tag (A-D); NULL in production
        createdby      INT           NULL,
        createdat      DATETIME2     NULL,
        editby         INT           NULL,
        edittime       DATETIME2     NULL,
        CONSTRAINT pk_wmsproduct PRIMARY KEY (id),
        CONSTRAINT uq_wmsproduct_code UNIQUE (code),
        CONSTRAINT uq_wmsproduct_clientsku UNIQUE (clientid, sku),
        CONSTRAINT ck_wmsproduct_track CHECK (trackexpiry = 0 OR tracklot = 1),  -- expiry => lot
        CONSTRAINT ck_wmsproduct_testcase CHECK (testcase IS NULL OR testcase IN ('A','B','C','D')),
        CONSTRAINT fk_wmsproduct_client      FOREIGN KEY (clientid)      REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmsproduct_category    FOREIGN KEY (categoryid)    REFERENCES dbo.wmscategory (id),
        CONSTRAINT fk_wmsproduct_subcategory FOREIGN KEY (subcategoryid) REFERENCES dbo.wmssubcategory (id)
    );
    CREATE INDEX ix_wmsproduct_clientid ON dbo.wmsproduct (clientid);
    CREATE INDEX ix_wmsproduct_categoryid ON dbo.wmsproduct (categoryid);
END
GO

/* wmsproductpreferred --------------------------------------------------------
   SCREEN : erp-md-products.html  (the "preferred storage" editor on the product
            form — pick a fixed location OR a preferred area, per operating site).
   PURPOSE: Optional preferred home storage for a product, PER operating site.
            "mode" chooses what the reference means: 'location' = a fixed bin
            (locationid set); 'area' = any open bin in a Storage Area (areaid set).
            Putaway offers it first; never required. The CHECK enforces exactly one
            of locationid/areaid per the mode. uq(productid,siteid) intentionally caps
            it at ONE preferred home per product per site. (Mock: product.preferred[].) */
IF OBJECT_ID(N'dbo.wmsproductpreferred', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsproductpreferred (
        id          INT IDENTITY(1,1) NOT NULL,
        productid   INT          NOT NULL,
        siteid      INT          NOT NULL,
        mode        VARCHAR(20)  NOT NULL,    -- 'location' | 'area'
        locationid  INT          NULL,         -- set when mode='location'
        areaid      INT          NULL,         -- set when mode='area'
        CONSTRAINT pk_wmsproductpreferred PRIMARY KEY (id),
        CONSTRAINT uq_wmsproductpreferred UNIQUE (productid, siteid),
        CONSTRAINT ck_wmsproductpreferred_mode CHECK (mode IN ('location','area')),
        CONSTRAINT ck_wmsproductpreferred_ref CHECK (
              (mode = 'location' AND locationid IS NOT NULL AND areaid IS NULL)
           OR (mode = 'area'     AND areaid IS NOT NULL AND locationid IS NULL)
        ),
        CONSTRAINT fk_wmsproductpreferred_product  FOREIGN KEY (productid)  REFERENCES dbo.wmsproduct (id),
        CONSTRAINT fk_wmsproductpreferred_site     FOREIGN KEY (siteid)     REFERENCES dbo.wmssite (id),
        -- composite FKs: the chosen location/area MUST belong to THIS row's site (the NULL
        -- column for the unused mode skips its own check). NOTE: that the site is one of the
        -- product's client's sites (wmsclientsite) is enforced in app logic, not here.
        CONSTRAINT fk_wmsproductpreferred_location FOREIGN KEY (locationid, siteid) REFERENCES dbo.wmslocation (id, siteid),
        CONSTRAINT fk_wmsproductpreferred_area     FOREIGN KEY (areaid, siteid)     REFERENCES dbo.wmsstoragearea (id, siteid)
    );
    CREATE INDEX ix_wmsproductpreferred_productid  ON dbo.wmsproductpreferred (productid);
    CREATE INDEX ix_wmsproductpreferred_locationid ON dbo.wmsproductpreferred (locationid);
    CREATE INDEX ix_wmsproductpreferred_areaid     ON dbo.wmsproductpreferred (areaid);
END
GO

/* wmspackaging ---------------------------------------------------------------
   SCREEN : erp-md-uom.html  ("Packaging hierarchies" tab — SHARED templates are
            authored here). A PRODUCT's own packaging (isshared=0, client+product
            set) is authored on erp-md-products.html by cloning a template.
   PURPOSE: Packaging hierarchy HEADER. Two tiers:
              * shared template  -> isshared = 1, clientid/productid NULL (e.g. "Dozen").
              * product packaging -> isshared = 0, clientid set, productid OPTIONAL
                (a client-level/demo packaging may have no product, e.g. PKG-BOXES);
                created by CLONING a template, then adding per-level barcodes.
            "baselabel" names the base level (e.g. 'Each','Vial') — free text, NOT an FK
            (cf. wmsproduct.baseuom). Levels live in wmspackaginglevel.
            (Mock array: packagings[].) */
IF OBJECT_ID(N'dbo.wmspackaging', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmspackaging (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(40)   NOT NULL,   -- business key e.g. 'PKG-OLIVE','PKG-T-DOZEN'
        name        NVARCHAR(160) NOT NULL,
        isshared    BIT           NOT NULL CONSTRAINT df_wmspackaging_isshared DEFAULT (0),
        clientid    INT           NULL,        -- product packaging only
        productid   INT           NULL,        -- product packaging only
        baselabel   NVARCHAR(60)  NULL,        -- base-level display label, free text (cf. wmsproduct.baseuom)
        createdby   INT           NULL,
        createdat   DATETIME2     NULL,
        editby      INT           NULL,
        edittime    DATETIME2     NULL,
        CONSTRAINT pk_wmspackaging PRIMARY KEY (id),
        CONSTRAINT uq_wmspackaging_code UNIQUE (code),
        -- tier integrity: a shared template carries NO client/product; a non-shared packaging
        -- must carry a client (product OPTIONAL — e.g. the client-level PKG-BOXES has no product).
        CONSTRAINT ck_wmspackaging_tier CHECK (
              (isshared = 1 AND clientid IS NULL AND productid IS NULL)
           OR (isshared = 0 AND clientid IS NOT NULL)
        ),
        CONSTRAINT fk_wmspackaging_client  FOREIGN KEY (clientid)  REFERENCES dbo.wmsclient (id),
        CONSTRAINT fk_wmspackaging_product FOREIGN KEY (productid) REFERENCES dbo.wmsproduct (id)
    );
END
GO

/* wmspackaginglevel ----------------------------------------------------------
   SCREEN : erp-md-uom.html  (the packaging-level editor for templates) and
            erp-md-products.html (a product's cloned levels + per-level barcodes).
   PURPOSE: Ordered levels of a packaging hierarchy (base first). Each level
            declares its "basis": 'base' = an independent/parallel pack defined off
            the base unit; a lower level NAME = true nesting; NULL = defined against
            the immediately lower level. "perparent" = qty in its basis unit;
            "factor" = cumulative factor to the base unit (= basisFactor x perparent,
            precomputed). "barcode" is the per-level barcode (blank on templates).
            (Mock array: packaging.levels[].) */
IF OBJECT_ID(N'dbo.wmspackaginglevel', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmspackaginglevel (
        id           INT IDENTITY(1,1) NOT NULL,
        packagingid  INT           NOT NULL,
        levelorder   INT           NOT NULL,    -- 1-based, base level first
        levelname    NVARCHAR(60)  NOT NULL,    -- e.g. 'Six-pack','Carton'
        uomid        INT           NULL,         -- -> wmsuom
        basis        NVARCHAR(60)  NULL,         -- 'base' | <lower level name> | NULL(=immediately lower)
        perparent    DECIMAL(18,4) NOT NULL CONSTRAINT df_wmspackaginglevel_perparent DEFAULT (1),
        factor       DECIMAL(18,4) NOT NULL CONSTRAINT df_wmspackaginglevel_factor DEFAULT (1),
        barcode      VARCHAR(60)   NULL,
        note         NVARCHAR(200) NULL,
        CONSTRAINT pk_wmspackaginglevel PRIMARY KEY (id),
        CONSTRAINT uq_wmspackaginglevel_order UNIQUE (packagingid, levelorder),
        CONSTRAINT fk_wmspackaginglevel_packaging FOREIGN KEY (packagingid) REFERENCES dbo.wmspackaging (id),
        CONSTRAINT fk_wmspackaginglevel_uom       FOREIGN KEY (uomid)       REFERENCES dbo.wmsuom (id)
    );
    CREATE INDEX ix_wmspackaginglevel_packagingid ON dbo.wmspackaginglevel (packagingid);
END
GO

/* ============================================================================
   GROUP 6 — USER EXTENSION & ACCESS SCOPE
   (the user master itself is the host's existing [dbo].[Users] — NOT created here)
   ============================================================================ */

/* wmsuserprofile -------------------------------------------------------------
   SCREEN : erp-md-users.html  ("Users & Roles" — the WMS role + "all sites"/"all
            clients" toggles per user).
   PURPOSE: WMS-owned EXTENSION of the host [dbo].[Users] table (one row per
            WMS-enabled user, userid 1:1 -> Users.Id). Because the shared Auth table
            must not be altered, the WMS-specific attributes live here: "wmsrole"
            (Administrator|Supervisor|Operator) and the scope short-circuits
            "allsites"/"allclients" (1 = every site / every client, in which case
            the explicit scope tables are ignored). When a flag is 0 the explicit
            scope is read from wmsusersite / wmsuserclient. (Host "active user" =
            Users.IsActive = 1 AND (Users.IsBlocked IS NULL OR Users.IsBlocked = 0).) */
IF OBJECT_ID(N'dbo.wmsuserprofile', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsuserprofile (
        id          INT IDENTITY(1,1) NOT NULL,
        userid      INT          NOT NULL,   -- 1:1 -> [dbo].[Users].[Id]
        wmsrole     VARCHAR(20)  NOT NULL,   -- Administrator|Supervisor|Operator
        allsites    BIT          NOT NULL CONSTRAINT df_wmsuserprofile_allsites DEFAULT (0),
        allclients  BIT          NOT NULL CONSTRAINT df_wmsuserprofile_allclients DEFAULT (0),
        createdby   INT          NULL,
        createdat   DATETIME2    NULL,
        editby      INT          NULL,
        edittime    DATETIME2    NULL,
        CONSTRAINT pk_wmsuserprofile PRIMARY KEY (id),
        CONSTRAINT uq_wmsuserprofile_userid UNIQUE (userid),
        CONSTRAINT ck_wmsuserprofile_role CHECK (wmsrole IN ('Administrator','Supervisor','Operator')),
        CONSTRAINT fk_wmsuserprofile_user FOREIGN KEY (userid) REFERENCES dbo.[Users] ([Id])
    );
END
GO

/* wmsusersite ----------------------------------------------------------------
   SCREEN : erp-md-users.html  (a user's site-scope multi-select).
   PURPOSE: Explicit site scope for a user — used only when
            wmsuserprofile.allsites = 0. References the host [dbo].[Users].[Id].
   NOTE   : In the MOCK, site scope is a DISPLAY LABEL only (user.sites =
            'All sites'|'Luanda'|'Soyo') with no machine-readable site-id list (unlike
            client scope, which has authoritative allClients + clientIds[]). When
            seeding from the mock, derive allsites = (sites == 'All sites') and resolve
            these rows from the site NAME. */
IF OBJECT_ID(N'dbo.wmsusersite', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsusersite (
        id          INT IDENTITY(1,1) NOT NULL,
        userid      INT NOT NULL,   -- -> [dbo].[Users].[Id]
        siteid      INT NOT NULL,
        CONSTRAINT pk_wmsusersite PRIMARY KEY (id),
        CONSTRAINT uq_wmsusersite UNIQUE (userid, siteid),
        CONSTRAINT fk_wmsusersite_user FOREIGN KEY (userid) REFERENCES dbo.[Users] ([Id]),
        CONSTRAINT fk_wmsusersite_site FOREIGN KEY (siteid) REFERENCES dbo.wmssite (id)
    );
END
GO

/* wmsuserclient --------------------------------------------------------------
   SCREEN : erp-md-clientmap.html  (the Client-User Mapping grid: which clients a
            user may access) and erp-md-users.html (a user's client scope).
   PURPOSE: Explicit client scope for a user — used only when
            wmsuserprofile.allclients = 0. References the host [dbo].[Users].[Id]. */
IF OBJECT_ID(N'dbo.wmsuserclient', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsuserclient (
        id          INT IDENTITY(1,1) NOT NULL,
        userid      INT NOT NULL,   -- -> [dbo].[Users].[Id]
        clientid    INT NOT NULL,
        CONSTRAINT pk_wmsuserclient PRIMARY KEY (id),
        CONSTRAINT uq_wmsuserclient UNIQUE (userid, clientid),
        CONSTRAINT fk_wmsuserclient_user   FOREIGN KEY (userid)   REFERENCES dbo.[Users] ([Id]),
        CONSTRAINT fk_wmsuserclient_client FOREIGN KEY (clientid) REFERENCES dbo.wmsclient (id)
    );
END
GO

/* ============================================================================
   GROUP 7 — REASON CODES (configurable operational vocabulary)
   ============================================================================ */

/* wmsreasondomain ------------------------------------------------------------
   SCREEN : erp-md-reasons.html  (the domain accordions). The reasons are then
            consumed by the Section-05 operational screens (status change,
            adjustment, correction, returns, ad-hoc dispatch).
   PURPOSE: The top of the configurable reason vocabulary so operational screens
            never hardcode reasons. "code" is the domain key (status | adjust |
            correct | return | dispatch | … extensible). "groupedby" labels the
            grouping dimension ('Target status', 'Direction'), or NULL for a single
            shared list. (The mock encodes the single-list case as an EMPTY STRING ''
            in groupedBy — the loader should normalise '' -> NULL.)
            (Mock array: reasonDomains[].) */
IF OBJECT_ID(N'dbo.wmsreasondomain', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreasondomain (
        id          INT IDENTITY(1,1) NOT NULL,
        code        VARCHAR(20)  NOT NULL,    -- 'status','adjust','correct','return','dispatch'
        label       NVARCHAR(80) NOT NULL,
        groupedby   NVARCHAR(40) NULL,
        createdby   INT          NULL,
        createdat   DATETIME2    NULL,
        editby      INT          NULL,
        edittime    DATETIME2    NULL,
        CONSTRAINT pk_wmsreasondomain PRIMARY KEY (id),
        CONSTRAINT uq_wmsreasondomain_code UNIQUE (code)
    );
END
GO

/* wmsreasongroup -------------------------------------------------------------
   SCREEN : erp-md-reasons.html  (the groups inside each domain).
   PURPOSE: A group within a domain. For the 'status' domain the "groupkey" IS the
            target LPN status (available/quarantine/hold/damaged/expired) so reasons
            stay logically linked to the status; for 'adjust' it is
            increase/decrease; for single-list domains it is 'all'.
            (Mock array: domain.groups[].) */
IF OBJECT_ID(N'dbo.wmsreasongroup', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreasongroup (
        id          INT IDENTITY(1,1) NOT NULL,
        domainid    INT          NOT NULL,
        groupkey    VARCHAR(40)  NOT NULL,    -- target status / direction / 'all'
        label       NVARCHAR(80) NOT NULL,
        seq         INT          NULL,
        CONSTRAINT pk_wmsreasongroup PRIMARY KEY (id),
        CONSTRAINT uq_wmsreasongroup UNIQUE (domainid, groupkey),
        CONSTRAINT fk_wmsreasongroup_domain FOREIGN KEY (domainid) REFERENCES dbo.wmsreasondomain (id)
    );
END
GO

/* wmsreason ------------------------------------------------------------------
   SCREEN : erp-md-reasons.html  (add/remove the individual reason rows per group).
   PURPOSE: An individual selectable reason string within a group. Recorded on the
            transaction log when an operator posts the related action.
            (Mock array: group.reasons[].) */
IF OBJECT_ID(N'dbo.wmsreason', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmsreason (
        id          INT IDENTITY(1,1) NOT NULL,
        groupid     INT           NOT NULL,
        reasontext  NVARCHAR(200) NOT NULL,
        seq         INT           NULL,
        status      VARCHAR(20)   NOT NULL CONSTRAINT df_wmsreason_status DEFAULT ('active'),
        CONSTRAINT pk_wmsreason PRIMARY KEY (id),
        CONSTRAINT uq_wmsreason UNIQUE (groupid, reasontext),
        CONSTRAINT ck_wmsreason_status CHECK (status IN ('active','inactive')),
        CONSTRAINT fk_wmsreason_group FOREIGN KEY (groupid) REFERENCES dbo.wmsreasongroup (id)
    );
END
GO

/* ============================================================================
   GROUP 8 — LICENSE PLATE / SSCC CONFIGURATION
   ============================================================================ */

/* wmslpnconfig ---------------------------------------------------------------
   SCREEN : NO dedicated mock screen yet — this is a Section-01 In-Scope master-data
            item (LPN/SSCC numbering scheme + label format). In the build it belongs
            on an LPN/SSCC settings screen (candidate: an extension of the
            erp-md-sites.html settings panel or a dedicated settings screen). Listed
            here so the master-data schema is complete.
   PURPOSE: Drives generation of the License Plate (LPN/SSCC) ids used through
            receive -> putaway -> pick. "siteid" NULL = the global default rule; a
            row per site overrides it. Columns reflect the functional intent
            (prefix + scheme + zero-padding + running sequence + label template);
            the mock dataset has no seed for this. */
IF OBJECT_ID(N'dbo.wmslpnconfig', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.wmslpnconfig (
        id              INT IDENTITY(1,1) NOT NULL,
        code            VARCHAR(40)   NOT NULL,   -- business key e.g. 'LPNCFG-DEFAULT'
        name            NVARCHAR(120) NULL,
        siteid          INT           NULL,        -- NULL = global default
        prefix          VARCHAR(20)   NULL,        -- e.g. 'LPN-'
        numberingscheme VARCHAR(40)   NULL,        -- e.g. 'sequential','sscc'
        paddinglength   INT           NULL,        -- zero-pad width of the running number
        nextsequence    BIGINT        NULL,        -- next running number to issue
        labelformat     NVARCHAR(200) NULL,        -- label template / format reference
        status          VARCHAR(20)   NOT NULL CONSTRAINT df_wmslpnconfig_status DEFAULT ('active'),
        createdby       INT           NULL,
        createdat       DATETIME2     NULL,
        editby          INT           NULL,
        edittime        DATETIME2     NULL,
        CONSTRAINT pk_wmslpnconfig PRIMARY KEY (id),
        CONSTRAINT uq_wmslpnconfig_code UNIQUE (code),
        CONSTRAINT ck_wmslpnconfig_status CHECK (status IN ('active','inactive')),
        CONSTRAINT fk_wmslpnconfig_site FOREIGN KEY (siteid) REFERENCES dbo.wmssite (id)
    );
END
GO

/* ============================================================================
   END OF MASTER DATA SCHEMA
   ----------------------------------------------------------------------------
   WMS tables created (29):
     System/lookup : wmssetting, wmsuom, wmsdefaultsitelevel
     Taxonomy      : wmscategory, wmssubcategory
     Parties       : wmsclient, wmssupplier, wmscarrier, wmsconsignee
     Sites/storage : wmssite, wmsclientsite, wmssitelevel, wmsstoragearea,
                     wmsareacategory, wmsareasubcategory, wmsareaclient,
                     wmslocation, wmslocationpath
     Products      : wmsproduct, wmsproductpreferred, wmspackaging, wmspackaginglevel
     Users/scope   : wmsuserprofile, wmsusersite, wmsuserclient
                     (the user master itself = host [dbo].[Users], referenced only)
     Reason codes  : wmsreasondomain, wmsreasongroup, wmsreason
     LPN config    : wmslpnconfig

   Referenced but NOT created here: [dbo].[Users] (host identity table).

   NOT in this file (by design): views and stored procedures — they are built
   per-screen during the Master Data development cards. Seed/reference data is
   also out of scope here (schema only).
   ============================================================================ */
