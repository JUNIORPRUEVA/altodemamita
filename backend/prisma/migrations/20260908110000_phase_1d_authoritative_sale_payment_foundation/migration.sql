CREATE TABLE IF NOT EXISTS "AuthoritativeOperation" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "operationKey" TEXT NOT NULL,
    "operationType" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'completed',
    "resourceType" TEXT,
    "resourceId" TEXT,
    "response" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AuthoritativeOperation_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AuthoritativeOperation_companyId_operationKey_key"
    ON "AuthoritativeOperation"("companyId", "operationKey");

CREATE INDEX IF NOT EXISTS "AuthoritativeOperation_companyId_operationType_createdAt_idx"
    ON "AuthoritativeOperation"("companyId", "operationType", "createdAt");

ALTER TABLE "AuthoritativeOperation"
    ADD CONSTRAINT "AuthoritativeOperation_companyId_fkey"
    FOREIGN KEY ("companyId") REFERENCES "Company"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
