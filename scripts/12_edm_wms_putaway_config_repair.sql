/* ============================================================================
   WMS · EDM config REPAIR — "WMS_PUTAWAY"
   ----------------------------------------------------------------------------
   Symptom : the interface exists (no more DataNotFound) but the widget still
             shows "Photo storage isn't configured yet (EDM WMS_PUTAWAY
             interface)". That toast fires when
               GET /EDMComponent/GetCategoriesAndTypesByInterface/WMS_PUTAWAY
             does NOT return a category WITH at least one VISIBLE document type.

   Three gaps this repairs (any of them causes the toast):
     1. category↔group link CanUploadDocument = NULL  → EdmCategoryRepository.cs:59
        does `cat_group.CanUploadDocument.Value`, which THROWS on NULL → 500 →
        the front falls back to default-types (none) → toast.
     2. no VISIBLE document type under the category (Visible <> 1, the resolver
        filters `type.Visible == true`).
     3. the type isn't linked to the category via GedCategorieType.

   Unlike 11_..._seed.sql (which makes a NEW group), this works off the
   interface's ACTUAL group — so it fixes a config made by hand / admin UI too.

   TARGET DB: the **EDM database** the app resolves for YOUR agency — the same
             one where WMS_PUTAWAY now resolves (no DataNotFound). If the
             interface isn't in this DB, the script says so (you configured a
             different agency's EDM DB).
   Idempotent: guarded; safe to re-run.
   ============================================================================ */

SET NOCOUNT ON;

DECLARE @CategoryName nvarchar(200) = N'Putaway Photos';
DECLARE @TypeName     nvarchar(200) = N'Photo';

/* The interface's ACTUAL group (whatever created it). */
DECLARE @GroupId int = (SELECT TOP 1 GroupId FROM GedInterfaces WHERE Name = N'WMS_PUTAWAY');
IF @GroupId IS NULL
BEGIN
    RAISERROR('WMS_PUTAWAY interface not found in THIS EDM database. You configured a different agency''s EDM DB (or not at all) — run this on the DB the app uses for your agency.', 16, 1);
    RETURN;
END

/* 1) Ensure a category is linked to that group (with CanUploadDocument = 1). */
DECLARE @CatId int = (
    SELECT TOP 1 c.Id
    FROM GedCategorieGroupe cg
    JOIN GedDocumentCategory c ON c.Id = cg.CategorieId
    WHERE cg.GroupId = @GroupId
    ORDER BY c.Id
);
IF @CatId IS NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM GedDocumentCategory WHERE CategoryName = @CategoryName)
        INSERT INTO GedDocumentCategory (CategoryName, CategoryNameFr, CategoryNameEn, CategoryNameEs, CategoryNamePt, CategoryGroup)
        VALUES (@CategoryName, N'Photos de rangement', N'Putaway Photos', N'Fotos de almacenamiento', N'Fotos de arrumação', NULL);
    SET @CatId = (SELECT TOP 1 Id FROM GedDocumentCategory WHERE CategoryName = @CategoryName);
    INSERT INTO GedCategorieGroupe (CategorieId, GroupId, CanUploadDocument) VALUES (@CatId, @GroupId, 1);
END

/* Fix the NULL upload-flag trap on every category link of this group. */
UPDATE GedCategorieGroupe SET CanUploadDocument = 1
WHERE GroupId = @GroupId AND CanUploadDocument IS NULL;

/* 2) Ensure a "Photo" document type exists under the category, VISIBLE. */
DECLARE @TypeId int = (SELECT TOP 1 Id FROM GedDocumentType WHERE TypeName = @TypeName AND TypeCategory = @CatId);
IF @TypeId IS NULL
BEGIN
    INSERT INTO GedDocumentType (TypeName, TypeCategory, TypeNameFr, TypeNameEn, TypeNameEs, TypeNamePt, Visible, RequiredValidation)
    VALUES (@TypeName, @CatId, N'Photo', N'Photo', N'Foto', N'Foto', 1, 0);
    SET @TypeId = (SELECT TOP 1 Id FROM GedDocumentType WHERE TypeName = @TypeName AND TypeCategory = @CatId);
END
UPDATE GedDocumentType SET Visible = 1 WHERE Id = @TypeId AND (Visible IS NULL OR Visible = 0);

/* 3) Ensure the type is linked to the category (this is what the resolver reads). */
IF NOT EXISTS (SELECT 1 FROM GedCategorieType WHERE TypesId = @TypeId AND CategorieId = @CatId)
    INSERT INTO GedCategorieType (TypesId, CategorieId) VALUES (@TypeId, @CatId);

/* VERIFY — must return at least one row (Visible = 1, CanUploadDocument = 1).
   This mirrors GetCategoriesAndTypesByInterface exactly. */
SELECT i.Name AS [Interface], c.CategoryName AS [Category], cg.CanUploadDocument,
       t.TypeName AS [Type], t.Visible
FROM GedInterfaces i
JOIN GedCategorieGroupe cg ON cg.GroupId = i.GroupId
JOIN GedDocumentCategory c ON c.Id = cg.CategorieId
JOIN GedCategorieType ct   ON ct.CategorieId = c.Id
JOIN GedDocumentType t     ON t.Id = ct.TypesId AND t.Visible = 1
WHERE i.Name = N'WMS_PUTAWAY';
