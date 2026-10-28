-- Fase 3 — Condonacion permanente de mora (aditiva).
--
-- Tabla NUEVA. No modifica Payment, Installment, Sale ni la politica global.
-- Permite condonar la mora acumulada hasta un corte sin tocar pagos historicos.
-- La mora posterior al corte sigue acumulandose normalmente.
--
-- NO aplicar en produccion sin autorizacion explicita.

CREATE TABLE "LateFeeWaiver" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "saleId" TEXT NOT NULL,
    "saleSyncId" TEXT NOT NULL,
    "installmentId" TEXT,
    "installmentSyncId" TEXT,
    "cutoffAt" TIMESTAMP(3) NOT NULL,
    "calculatedFee" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "waivedAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "reason" TEXT,
    "appliedByUserId" TEXT,
    "idempotencyKey" TEXT NOT NULL,
    "appliedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "raw" JSONB,

    CONSTRAINT "LateFeeWaiver_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "LateFeeWaiver_companyId_idempotencyKey_key"
    ON "LateFeeWaiver"("companyId", "idempotencyKey");
CREATE INDEX "LateFeeWaiver_companyId_saleId_idx" ON "LateFeeWaiver"("companyId", "saleId");
CREATE INDEX "LateFeeWaiver_companyId_installmentId_idx" ON "LateFeeWaiver"("companyId", "installmentId");
CREATE INDEX "LateFeeWaiver_companyId_cutoffAt_idx" ON "LateFeeWaiver"("companyId", "cutoffAt");

ALTER TABLE "LateFeeWaiver"
    ADD CONSTRAINT "LateFeeWaiver_companyId_fkey"
    FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
