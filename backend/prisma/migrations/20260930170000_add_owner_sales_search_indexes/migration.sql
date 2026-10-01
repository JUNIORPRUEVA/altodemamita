CREATE INDEX IF NOT EXISTS "Client_companyId_deletedAt_name_idx"
  ON "Client"("companyId", "deletedAt", "name");

CREATE INDEX IF NOT EXISTS "Client_companyId_deletedAt_document_idx"
  ON "Client"("companyId", "deletedAt", "document");

CREATE INDEX IF NOT EXISTS "Client_companyId_deletedAt_phone_idx"
  ON "Client"("companyId", "deletedAt", "phone");

CREATE INDEX IF NOT EXISTS "Lot_companyId_deletedAt_block_idx"
  ON "Lot"("companyId", "deletedAt", "block");

CREATE INDEX IF NOT EXISTS "Lot_companyId_deletedAt_number_idx"
  ON "Lot"("companyId", "deletedAt", "number");

CREATE INDEX IF NOT EXISTS "Sale_companyId_deletedAt_updatedAt_idx"
  ON "Sale"("companyId", "deletedAt", "updatedAt");

CREATE INDEX IF NOT EXISTS "Sale_companyId_deletedAt_status_idx"
  ON "Sale"("companyId", "deletedAt", "status");

CREATE INDEX IF NOT EXISTS "Sale_companyId_deletedAt_clientSyncId_idx"
  ON "Sale"("companyId", "deletedAt", "clientSyncId");

CREATE INDEX IF NOT EXISTS "Sale_companyId_deletedAt_lotSyncId_idx"
  ON "Sale"("companyId", "deletedAt", "lotSyncId");

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS "Client_name_trgm_active_idx"
  ON "Client" USING gin ("name" gin_trgm_ops)
  WHERE "deletedAt" IS NULL;

CREATE INDEX IF NOT EXISTS "Client_document_trgm_active_idx"
  ON "Client" USING gin ("document" gin_trgm_ops)
  WHERE "deletedAt" IS NULL;

CREATE INDEX IF NOT EXISTS "Client_phone_trgm_active_idx"
  ON "Client" USING gin ("phone" gin_trgm_ops)
  WHERE "deletedAt" IS NULL;

CREATE INDEX IF NOT EXISTS "Lot_block_trgm_active_idx"
  ON "Lot" USING gin ("block" gin_trgm_ops)
  WHERE "deletedAt" IS NULL;

CREATE INDEX IF NOT EXISTS "Lot_number_trgm_active_idx"
  ON "Lot" USING gin ("number" gin_trgm_ops)
  WHERE "deletedAt" IS NULL;

CREATE INDEX IF NOT EXISTS "Sale_id_trgm_active_idx"
  ON "Sale" USING gin ("id" gin_trgm_ops)
  WHERE "deletedAt" IS NULL;

CREATE INDEX IF NOT EXISTS "Sale_syncId_trgm_active_idx"
  ON "Sale" USING gin ("syncId" gin_trgm_ops)
  WHERE "deletedAt" IS NULL;
