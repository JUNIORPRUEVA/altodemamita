ALTER TABLE "Payment"
ADD COLUMN IF NOT EXISTS "lateFeeApplied" DECIMAL(14,2) NOT NULL DEFAULT 0;

ALTER TABLE "LateFeeSnapshot"
ADD COLUMN IF NOT EXISTS "graceDays" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "lateFeeDays" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS "LateFeePolicyHistory" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "dailyRate" DECIMAL(8,6) NOT NULL DEFAULT 0.005,
    "graceDays" INTEGER NOT NULL DEFAULT 5,
    "effectiveFrom" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdByUserId" TEXT,
    "raw" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "LateFeePolicyHistory_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "LateFeePolicyHistory_companyId_effectiveFrom_idx"
ON "LateFeePolicyHistory"("companyId", "effectiveFrom");

CREATE INDEX IF NOT EXISTS "LateFeePolicyHistory_companyId_createdAt_idx"
ON "LateFeePolicyHistory"("companyId", "createdAt");

ALTER TABLE "LateFeePolicyHistory"
ADD CONSTRAINT "LateFeePolicyHistory_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

INSERT INTO "BusinessConfiguration" ("id", "companyId", "key", "value", "description", "raw", "createdAt", "updatedAt")
SELECT 'late_fee_enabled_' || c."id", c."id", 'late_fee_enabled', 'true', 'Mora diaria habilitada', '{"source":"20261003090000_late_fee_policy"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "Company" c
ON CONFLICT ("companyId", "key") DO NOTHING;

INSERT INTO "BusinessConfiguration" ("id", "companyId", "key", "value", "description", "raw", "createdAt", "updatedAt")
SELECT 'late_fee_daily_rate_' || c."id", c."id", 'late_fee_daily_rate', '0.005', 'Tasa diaria de mora. 0.005 equivale a 0.50%.', '{"source":"20261003090000_late_fee_policy"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "Company" c
ON CONFLICT ("companyId", "key") DO NOTHING;

INSERT INTO "BusinessConfiguration" ("id", "companyId", "key", "value", "description", "raw", "createdAt", "updatedAt")
SELECT 'late_fee_grace_days_' || c."id", c."id", 'late_fee_grace_days', '5', 'Dias calendario completos de gracia despues del vencimiento.', '{"source":"20261003090000_late_fee_policy"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "Company" c
ON CONFLICT ("companyId", "key") DO NOTHING;

INSERT INTO "LateFeePolicyHistory" ("id", "companyId", "enabled", "dailyRate", "graceDays", "effectiveFrom", "raw", "createdAt")
SELECT 'late_fee_policy_initial_' || c."id", c."id", true, 0.005, 5, CURRENT_TIMESTAMP, '{"source":"20261003090000_late_fee_policy","displayRate":"0.50%"}'::jsonb, CURRENT_TIMESTAMP
FROM "Company" c
WHERE NOT EXISTS (
  SELECT 1
  FROM "LateFeePolicyHistory" h
  WHERE h."companyId" = c."id"
);
