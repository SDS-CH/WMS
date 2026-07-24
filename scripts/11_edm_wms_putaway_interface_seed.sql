/* ============================================================================
   WMS · EDM interface seed — "WMS_PUTAWAY" (Condition / damage photos)
   ----------------------------------------------------------------------------
   Purpose : provision the EDM/GED configuration the putaway photo strip needs
             (PUT-PLACE-SCREEN + PUT-PALLET-SCREEN, component <sds-wms-putaway-photos>).
             The Angular widget calls
               GET /EDMComponent/GetCategoriesAndTypesByInterface/WMS_PUTAWAY
             to resolve the category + document type before uploading, and
               POST /EDMComponent/Document   (GetDocumentsByInterfaceAndCode)
             to list existing photos. Without this config the list call throws
               APICustomException(DataNotFound)   -- EDMComponentManager.cs:189
               (grp = GetGroupByInterfaceName('WMS_PUTAWAY') == null)
             and uploads are disabled with
               "Photo storage isn't configured yet (EDM WMS_PUTAWAY interface)."

   TARGET DB: the **EDM database** (the one EDM.API's GedContext points at) — the
             SAME target as 09_edm_wms_asn_interface_seed.sql. NOT the WMS agency
             DB. Run once (global config; not per-agency).

   Idempotent: guarded with IF NOT EXISTS; safe to re-run.

   Design note — DEDICATED GROUP (differs from the ASN seed, which reused a
   group). getCategories(WMS_PUTAWAY) returns EVERY category linked to the
   interface's group; giving PUTAWAY its own group keeps its category list clean
   (no 'ASN Photos' leaking in). The new group is CLONED from the group WMS_ASN
   already uses, so its storage connection (server / agency prefix / credentials
   / query type) is identical and proven. Physical file location is decided by
   the module+agency EntityEdmDirectory (AU DB), NOT the group — so putaway
   photos land in the same folder as ASN photos, with their real extension
   (EDMComponentManager.cs:566 keeps ".jpg"/".png"; no PDF conversion).
   ============================================================================ */

SET NOCOUNT ON;

DECLARE @InterfaceName nvarchar(200) = N'WMS_PUTAWAY';
DECLARE @CategoryName  nvarchar(200) = N'Putaway Photos';
DECLARE @TypeName      nvarchar(200) = N'Photo';

/* 1) Resolve a proven, upload-capable source group to clone the storage config
      from: prefer the group WMS_ASN uses, else 'Supplier', else the first group. */
DECLARE @srcGroupId int =
    COALESCE(
        (SELECT TOP 1 GroupId FROM GedInterfaces WHERE Name = N'WMS_ASN'),
        (SELECT TOP 1 GroupId FROM GedInterfaces WHERE Name = N'Supplier'),
        (SELECT TOP 1 Id      FROM GedGroupe ORDER BY Id)
    );
IF @srcGroupId IS NULL
BEGIN
    RAISERROR('No source EDM group found (WMS_ASN / Supplier / any). Configure an EDM group first (EDM admin), then re-run.', 16, 1);
    RETURN;
END

/* 2) Dedicated group, cloned from the source group's storage fields. */
DECLARE @GroupId int = (SELECT TOP 1 Id FROM GedGroupe WHERE Name = @InterfaceName);
IF @GroupId IS NULL
BEGIN
    INSERT INTO GedGroupe (Name, SecondAgencyRequest, ServerName, AgencyPrefix, UserName, Password, TypeQuery)
    SELECT @InterfaceName, SecondAgencyRequest, ServerName, AgencyPrefix, UserName, Password, TypeQuery
    FROM GedGroupe WHERE Id = @srcGroupId;
    SET @GroupId = SCOPE_IDENTITY();
END

/* 3) Category */
IF NOT EXISTS (SELECT 1 FROM GedDocumentCategory WHERE CategoryName = @CategoryName)
    INSERT INTO GedDocumentCategory (CategoryName, CategoryNameFr, CategoryNameEn, CategoryNameEs, CategoryNamePt, CategoryGroup)
    VALUES (@CategoryName, N'Photos de rangement', N'Putaway Photos', N'Fotos de almacenamiento', N'Fotos de arrumação', NULL);

DECLARE @CatId int = (SELECT TOP 1 Id FROM GedDocumentCategory WHERE CategoryName = @CategoryName);

/* 4) Interface WMS_PUTAWAY → dedicated group */
IF NOT EXISTS (SELECT 1 FROM GedInterfaces WHERE Name = @InterfaceName)
    INSERT INTO GedInterfaces (Name, GroupId, Roles)
    VALUES (@InterfaceName, @GroupId, NULL);

/* 5) Category ↔ group link (CanUploadDocument = 1 so the widget may upload) */
IF NOT EXISTS (SELECT 1 FROM GedCategorieGroupe WHERE CategorieId = @CatId AND GroupId = @GroupId)
    INSERT INTO GedCategorieGroupe (CategorieId, GroupId, CanUploadDocument)
    VALUES (@CatId, @GroupId, 1);

/* 6) Document type "Photo" (Visible = 1 — the resolver filters on it) */
IF NOT EXISTS (SELECT 1 FROM GedDocumentType WHERE TypeName = @TypeName AND TypeCategory = @CatId)
    INSERT INTO GedDocumentType (TypeName, TypeCategory, TypeNameFr, TypeNameEn, TypeNameEs, TypeNamePt, Visible, RequiredValidation)
    VALUES (@TypeName, @CatId, N'Photo', N'Photo', N'Foto', N'Foto', 1, 0);

DECLARE @TypeId int = (SELECT TOP 1 Id FROM GedDocumentType WHERE TypeName = @TypeName AND TypeCategory = @CatId);

/* 7) Category ↔ type link */
IF NOT EXISTS (SELECT 1 FROM GedCategorieType WHERE TypesId = @TypeId AND CategorieId = @CatId)
    INSERT INTO GedCategorieType (TypesId, CategorieId)
    VALUES (@TypeId, @CatId);

/* Verify: this should return exactly one row — WMS_PUTAWAY / Putaway Photos / Photo / 1. */
SELECT i.Name AS [Interface], c.CategoryName AS [Category], t.TypeName AS [Type], cg.CanUploadDocument
FROM GedInterfaces i
JOIN GedCategorieGroupe cg ON cg.GroupId = i.GroupId
JOIN GedDocumentCategory c ON c.Id = cg.CategorieId
JOIN GedCategorieType ct   ON ct.CategorieId = c.Id
JOIN GedDocumentType t     ON t.Id = ct.TypesId AND t.Visible = 1
WHERE i.Name = @InterfaceName;
