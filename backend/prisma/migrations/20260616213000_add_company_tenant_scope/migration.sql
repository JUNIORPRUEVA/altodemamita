-- FullPOS-style tenant scope for Sistema Solares.
-- Existing cloud rows are assigned to the single customer company.

CREATE TABLE "Company" (
    "id" TEXT NOT NULL,
    "tenantKey" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Company_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "Company_tenantKey_key" ON "Company"("tenantKey");

INSERT INTO "Company" ("id", "tenantKey", "name", "active", "updatedAt")
VALUES (
    'alto-dona-mamita-company',
    'alto-dona-mamita-sistema-solares',
    'EL ALTO DE DONA MAMITA',
    true,
    CURRENT_TIMESTAMP
)
ON CONFLICT ("tenantKey") DO UPDATE SET
    "name" = EXCLUDED."name",
    "active" = true,
    "updatedAt" = CURRENT_TIMESTAMP;

ALTER TABLE "Client" ADD COLUMN "companyId" TEXT;
ALTER TABLE "Seller" ADD COLUMN "companyId" TEXT;
ALTER TABLE "Lot" ADD COLUMN "companyId" TEXT;
ALTER TABLE "Sale" ADD COLUMN "companyId" TEXT;
ALTER TABLE "Installment" ADD COLUMN "companyId" TEXT;
ALTER TABLE "Payment" ADD COLUMN "companyId" TEXT;
ALTER TABLE "SyncBatch" ADD COLUMN "companyId" TEXT;

UPDATE "Client" SET "companyId" = 'alto-dona-mamita-company' WHERE "companyId" IS NULL;
UPDATE "Seller" SET "companyId" = 'alto-dona-mamita-company' WHERE "companyId" IS NULL;
UPDATE "Lot" SET "companyId" = 'alto-dona-mamita-company' WHERE "companyId" IS NULL;
UPDATE "Sale" SET "companyId" = 'alto-dona-mamita-company' WHERE "companyId" IS NULL;
UPDATE "Installment" SET "companyId" = 'alto-dona-mamita-company' WHERE "companyId" IS NULL;
UPDATE "Payment" SET "companyId" = 'alto-dona-mamita-company' WHERE "companyId" IS NULL;
UPDATE "SyncBatch" SET "companyId" = 'alto-dona-mamita-company' WHERE "companyId" IS NULL;

ALTER TABLE "Client" ALTER COLUMN "companyId" SET NOT NULL;
ALTER TABLE "Seller" ALTER COLUMN "companyId" SET NOT NULL;
ALTER TABLE "Lot" ALTER COLUMN "companyId" SET NOT NULL;
ALTER TABLE "Sale" ALTER COLUMN "companyId" SET NOT NULL;
ALTER TABLE "Installment" ALTER COLUMN "companyId" SET NOT NULL;
ALTER TABLE "Payment" ALTER COLUMN "companyId" SET NOT NULL;
ALTER TABLE "SyncBatch" ALTER COLUMN "companyId" SET NOT NULL;

ALTER TABLE "Client" ALTER COLUMN "companyId" SET DEFAULT 'alto-dona-mamita-company';
ALTER TABLE "Seller" ALTER COLUMN "companyId" SET DEFAULT 'alto-dona-mamita-company';
ALTER TABLE "Lot" ALTER COLUMN "companyId" SET DEFAULT 'alto-dona-mamita-company';
ALTER TABLE "Sale" ALTER COLUMN "companyId" SET DEFAULT 'alto-dona-mamita-company';
ALTER TABLE "Installment" ALTER COLUMN "companyId" SET DEFAULT 'alto-dona-mamita-company';
ALTER TABLE "Payment" ALTER COLUMN "companyId" SET DEFAULT 'alto-dona-mamita-company';
ALTER TABLE "SyncBatch" ALTER COLUMN "companyId" SET DEFAULT 'alto-dona-mamita-company';

DROP INDEX IF EXISTS "Client_syncId_key";
DROP INDEX IF EXISTS "Seller_syncId_key";
DROP INDEX IF EXISTS "Lot_syncId_key";
DROP INDEX IF EXISTS "Sale_syncId_key";
DROP INDEX IF EXISTS "Installment_syncId_key";
DROP INDEX IF EXISTS "Payment_syncId_key";

CREATE UNIQUE INDEX "Client_companyId_syncId_key" ON "Client"("companyId", "syncId");
CREATE UNIQUE INDEX "Seller_companyId_syncId_key" ON "Seller"("companyId", "syncId");
CREATE UNIQUE INDEX "Lot_companyId_syncId_key" ON "Lot"("companyId", "syncId");
CREATE UNIQUE INDEX "Sale_companyId_syncId_key" ON "Sale"("companyId", "syncId");
CREATE UNIQUE INDEX "Installment_companyId_syncId_key" ON "Installment"("companyId", "syncId");
CREATE UNIQUE INDEX "Payment_companyId_syncId_key" ON "Payment"("companyId", "syncId");

CREATE INDEX "Client_companyId_updatedAt_idx" ON "Client"("companyId", "updatedAt");
CREATE INDEX "Seller_companyId_updatedAt_idx" ON "Seller"("companyId", "updatedAt");
CREATE INDEX "Lot_companyId_updatedAt_idx" ON "Lot"("companyId", "updatedAt");
CREATE INDEX "Sale_companyId_updatedAt_idx" ON "Sale"("companyId", "updatedAt");
CREATE INDEX "Installment_companyId_updatedAt_idx" ON "Installment"("companyId", "updatedAt");
CREATE INDEX "Payment_companyId_updatedAt_idx" ON "Payment"("companyId", "updatedAt");
CREATE INDEX "SyncBatch_companyId_createdAt_idx" ON "SyncBatch"("companyId", "createdAt");

ALTER TABLE "Client" ADD CONSTRAINT "Client_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Seller" ADD CONSTRAINT "Seller_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Lot" ADD CONSTRAINT "Lot_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Installment" ADD CONSTRAINT "Installment_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "SyncBatch" ADD CONSTRAINT "SyncBatch_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
