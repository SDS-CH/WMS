/* ============================================================================
   WMS · EDM interface seed — "WMS_ASN" (ASN / delivery photos)
   ----------------------------------------------------------------------------
   Purpose : provision the EDM/GED configuration the GR-ASN-EDITOR-SCREEN photo
             strip needs. The Angular widget calls
             GET /EDMComponent/GetCategoriesAndTypesByInterface/WMS_ASN to resolve
             the category + document type before uploading; without this config
             that call returns nothing and the UI shows
             "Photo storage isn't configured yet (EDM WMS_ASN interface)."

   TARGET DB: the **EDM database** (the one the EDM.API GedContext points at) —
             NOT the WMS agency DB. Run it once (global config; not per-agency).

   Idempotent: guarded with IF NOT EXISTS; safe to re-run.

   Design note — REUSES AN EXISTING GROUP: GedGroupe carries the physical
   document-storage connection (server / agency prefix / credentials / query
   type). We do NOT create a new group; we attach WMS_ASN to a group that is
   already configured and working (resolved below). If you want ASN photos to
   live in a specific group/folder, set @GroupId explicitly instead.
   ============================================================================ */

SET NOCOUNT ON;

DECLARE @InterfaceName  nvarchar(200) = N'WMS_ASN';
DECLARE @CategoryName   nvarchar(200) = N'ASN Photos';
DECLARE @TypeName       nvarchar(200) = N'Photo';

/* 1) Pick a working group. Prefer the one the 'Supplier' interface uses (a
      proven, upload-capable group); else fall back to the first group. Override
      here if a specific group is required. */
DECLARE @GroupId int =
    (SELECT TOP 1 GroupId FROM GedInterfaces WHERE Name = N'Supplier');
IF @GroupId IS NULL
    SET @GroupId = (SELECT TOP 1 Id FROM GedGroupe ORDER BY Id);

IF @GroupId IS NULL
BEGIN
    RAISERROR('No GedGroupe found — configure at least one EDM group first (EDM admin), then re-run.', 16, 1);
    RETURN;
END

/* 2) Category */
IF NOT EXISTS (SELECT 1 FROM GedDocumentCategory WHERE CategoryName = @CategoryName)
    INSERT INTO GedDocumentCategory (CategoryName, CategoryNameFr, CategoryNameEn, CategoryNameEs, CategoryNamePt, CategoryGroup)
    VALUES (@CategoryName, N'Photos ASN', N'ASN Photos', N'Fotos ASN', N'Fotos ASN', NULL);

DECLARE @CatId int = (SELECT TOP 1 Id FROM GedDocumentCategory WHERE CategoryName = @CategoryName);

/* 3) Interface WMS_ASN → group */
IF NOT EXISTS (SELECT 1 FROM GedInterfaces WHERE Name = @InterfaceName)
    INSERT INTO GedInterfaces (Name, GroupId, Roles)
    VALUES (@InterfaceName, @GroupId, NULL);

/* 4) Category ↔ group link (CanUploadDocument = 1 so the widget may upload) */
IF NOT EXISTS (SELECT 1 FROM GedCategorieGroupe WHERE CategorieId = @CatId AND GroupId = @GroupId)
    INSERT INTO GedCategorieGroupe (CategorieId, GroupId, CanUploadDocument)
    VALUES (@CatId, @GroupId, 1);

/* 5) Document type "Photo" (Visible = 1 — the resolver filters on it) */
IF NOT EXISTS (SELECT 1 FROM GedDocumentType WHERE TypeName = @TypeName AND TypeCategory = @CatId)
    INSERT INTO GedDocumentType (TypeName, TypeCategory, TypeNameFr, TypeNameEn, TypeNameEs, TypeNamePt, Visible, RequiredValidation)
    VALUES (@TypeName, @CatId, N'Photo', N'Photo', N'Foto', N'Foto', 1, 0);

DECLARE @TypeId int = (SELECT TOP 1 Id FROM GedDocumentType WHERE TypeName = @TypeName AND TypeCategory = @CatId);

/* 6) Category ↔ type link */
IF NOT EXISTS (SELECT 1 FROM GedCategorieType WHERE TypesId = @TypeId AND CategorieId = @CatId)
    INSERT INTO GedCategorieType (TypesId, CategorieId)
    VALUES (@TypeId, @CatId);

/* Verify: this should return one category with one 'Photo' type. */
SELECT i.Name AS [Interface], c.CategoryName AS [Category], t.TypeName AS [Type], cg.CanUploadDocument
FROM GedInterfaces i
JOIN GedCategorieGroupe cg ON cg.GroupId = i.GroupId
JOIN GedDocumentCategory c ON c.Id = cg.CategorieId
JOIN GedCategorieType ct   ON ct.CategorieId = c.Id
JOIN GedDocumentType t     ON t.Id = ct.TypesId AND t.Visible = 1
WHERE i.Name = @InterfaceName;
