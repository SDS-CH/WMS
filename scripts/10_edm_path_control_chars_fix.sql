/* ============================================================================
   WMS · EDM path fix — control characters breaking ASN photo uploads
   ----------------------------------------------------------------------------
   Symptom : uploading a photo from GR-ASN-EDITOR-SCREEN fails with
               "The filename, directory name, or volume label syntax is
                incorrect. : 'C:\EDM-DOCS\GEDSuisse\SM\SUISSE<TAB>\11\WMS_ASN\
                2026\WMS_ASN-ASN-3009-66b\V01\WMS_ASN-ASN-3009-66b.png'"
             The invisible <TAB> (CHAR(9)) in the folder name is what Windows
             rejects — it sits between the agency-name segment and the
             template-driven part of the path.

   Cause   : EDM composes the physical path as
                 dfsPathFolder
               + '\' + GED_Agence.NomAgence                  (GetPartialUrlForSuisss)
               + GED_DocumentType.UrlTemplate expanded       (PrepareUrl:
                 [AGENCY]/[TYPE]/[YEAR]/[CODE]/[VERSION])
             (EDM-Common/EDM.Services/EDMComponentManager.cs). A TAB stored at
             the END of NomAgence or at the START of the WMS_ASN type's
             UrlTemplate lands in the middle of the path. Tabs/CR/LF are never
             valid in NTFS names, so any row carrying one is wrong by
             definition — the fix strips them everywhere.

   TARGET DB: the **EDM database** (the one EDM.API's GedContext points at —
             same target as 09_edm_wms_asn_interface_seed.sql).
   Idempotent: yes — the UPDATEs only touch rows that contain control chars;
             re-running is a no-op.
   ============================================================================ */

SET NOCOUNT ON;

/* ── 1) DIAGNOSE — which rows carry TAB / CR / LF? ─────────────────────────
   Run this block first and eyeball the output: expect the agency-11 row
   (NomAgence 'SUISSE') and/or the 'WMS_ASN' document type to show up. */

SELECT 'GED_Agence' AS Source, CodeAgence, NomAgence AS Value,
       LEN(NomAgence) AS Chars,
       CHARINDEX(CHAR(9), NomAgence)  AS TabAt,
       CHARINDEX(CHAR(13), NomAgence) AS CrAt,
       CHARINDEX(CHAR(10), NomAgence) AS LfAt
FROM GED_Agence
WHERE NomAgence LIKE '%' + CHAR(9)  + '%'
   OR NomAgence LIKE '%' + CHAR(13) + '%'
   OR NomAgence LIKE '%' + CHAR(10) + '%';

SELECT 'GED_DocumentType' AS Source, Id, TypeName, UrlTemplate AS Value,
       CHARINDEX(CHAR(9), UrlTemplate)  AS TabAt,
       CHARINDEX(CHAR(13), UrlTemplate) AS CrAt,
       CHARINDEX(CHAR(10), UrlTemplate) AS LfAt
FROM GED_DocumentType
WHERE UrlTemplate LIKE '%' + CHAR(9)  + '%'
   OR UrlTemplate LIKE '%' + CHAR(13) + '%'
   OR UrlTemplate LIKE '%' + CHAR(10) + '%';

/* ── 2) FIX — strip TAB/CR/LF (+ trim) from the two path sources ─────────── */

UPDATE GED_Agence
SET NomAgence = LTRIM(RTRIM(
        REPLACE(REPLACE(REPLACE(NomAgence, CHAR(9), ''), CHAR(13), ''), CHAR(10), '')))
WHERE NomAgence LIKE '%' + CHAR(9)  + '%'
   OR NomAgence LIKE '%' + CHAR(13) + '%'
   OR NomAgence LIKE '%' + CHAR(10) + '%';
PRINT CONCAT('GED_Agence rows fixed: ', @@ROWCOUNT);

UPDATE GED_DocumentType
SET UrlTemplate = LTRIM(RTRIM(
        REPLACE(REPLACE(REPLACE(UrlTemplate, CHAR(9), ''), CHAR(13), ''), CHAR(10), '')))
WHERE UrlTemplate LIKE '%' + CHAR(9)  + '%'
   OR UrlTemplate LIKE '%' + CHAR(13) + '%'
   OR UrlTemplate LIKE '%' + CHAR(10) + '%';
PRINT CONCAT('GED_DocumentType rows fixed: ', @@ROWCOUNT);

/* ── 3) CLEAN-UP — documents persisted with the broken URL ─────────────────
   The upload dies at the file write, but if a GED_Document row was inserted
   before the exception its stored URLs carry the TAB and would 404 on read.
   Strip the control chars there too (the file never existed on disk under the
   tabbed folder — Windows cannot create it — so no orphan files result). */

UPDATE GED_Document
SET DocumentSuisseUrl = REPLACE(REPLACE(REPLACE(DocumentSuisseUrl, CHAR(9), ''), CHAR(13), ''), CHAR(10), ''),
    DocumentUrl       = REPLACE(REPLACE(REPLACE(DocumentUrl,       CHAR(9), ''), CHAR(13), ''), CHAR(10), '')
WHERE DocumentSuisseUrl LIKE '%' + CHAR(9)  + '%'
   OR DocumentSuisseUrl LIKE '%' + CHAR(13) + '%'
   OR DocumentSuisseUrl LIKE '%' + CHAR(10) + '%'
   OR DocumentUrl       LIKE '%' + CHAR(9)  + '%'
   OR DocumentUrl       LIKE '%' + CHAR(13) + '%'
   OR DocumentUrl       LIKE '%' + CHAR(10) + '%';
PRINT CONCAT('GED_Document rows fixed: ', @@ROWCOUNT);

/* ── 4) VERIFY — all three SELECTs must return 0 rows ────────────────────── */

SELECT 'GED_Agence (should be empty)' AS Verify, CodeAgence, NomAgence
FROM GED_Agence
WHERE NomAgence LIKE '%' + CHAR(9) + '%' OR NomAgence LIKE '%' + CHAR(13) + '%' OR NomAgence LIKE '%' + CHAR(10) + '%';

SELECT 'GED_DocumentType (should be empty)' AS Verify, Id, TypeName
FROM GED_DocumentType
WHERE UrlTemplate LIKE '%' + CHAR(9) + '%' OR UrlTemplate LIKE '%' + CHAR(13) + '%' OR UrlTemplate LIKE '%' + CHAR(10) + '%';

SELECT 'GED_Document (should be empty)' AS Verify, DocumentCode
FROM GED_Document
WHERE DocumentSuisseUrl LIKE '%' + CHAR(9) + '%' OR DocumentUrl LIKE '%' + CHAR(9) + '%';
