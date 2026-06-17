-- Partial unique indexes for active-only duplicate prevention.
-- These ensure no two active records share the same business key,
-- while allowing soft-deleted records to coexist.

-- Lot: unique active (companyId + block + number)
CREATE UNIQUE INDEX IF NOT EXISTS "Lot_companyId_block_number_active_unique"
ON "Lot" ("companyId", "block", "number")
WHERE "deletedAt" IS NULL;

-- Client: unique active (companyId + document), ignoring null/empty documents
CREATE UNIQUE INDEX IF NOT EXISTS "Client_companyId_document_active_unique"
ON "Client" ("companyId", "document")
WHERE "deletedAt" IS NULL AND "document" IS NOT NULL AND "document" <> '';

-- Seller: unique active (companyId + document), ignoring null/empty documents
CREATE UNIQUE INDEX IF NOT EXISTS "Seller_companyId_document_active_unique"
ON "Seller" ("companyId", "document")
WHERE "deletedAt" IS NULL AND "document" IS NOT NULL AND "document" <> '';
