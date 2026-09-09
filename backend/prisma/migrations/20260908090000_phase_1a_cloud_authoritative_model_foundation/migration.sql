-- Phase 1A cloud-authoritative data model foundation.
-- Additive and backfill-capable: keeps existing syncId/raw compatibility while
-- preparing normalized relationships and business fields for future services.

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "companyId" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "syncId" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "localRole" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "phone" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "passwordResetRequired" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "passwordUpdatedAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "remoteAuthId" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "authSource" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "lastOnlineLoginAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "raw" JSONB;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "deletedAt" TIMESTAMP(3);

UPDATE "User"
SET "companyId" = COALESCE("companyId", 'alto-dona-mamita-company'),
    "localRole" = COALESCE("localRole", LOWER("role"::TEXT))
WHERE "companyId" IS NULL OR "localRole" IS NULL;

ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "clientId" TEXT;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "lotId" TEXT;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "sellerId" TEXT;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "operatorUserId" TEXT;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "operatorUserSyncId" TEXT;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "initialPercentage" DECIMAL(8,4);
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "initialRequiredAmount" DECIMAL(14,2) NOT NULL DEFAULT 0;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "initialPendingAmount" DECIMAL(14,2) NOT NULL DEFAULT 0;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "reservationMinimumAmount" DECIMAL(14,2) NOT NULL DEFAULT 0;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "reservationPaidAmount" DECIMAL(14,2) NOT NULL DEFAULT 0;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "initialPaymentDeadline" TIMESTAMP(3);
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "activationDate" TIMESTAMP(3);
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "financedBalance" DECIMAL(14,2) NOT NULL DEFAULT 0;
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "monthlyInterestRate" DECIMAL(8,4);
ALTER TABLE "Sale" ADD COLUMN IF NOT EXISTS "installmentCount" INTEGER;

UPDATE "Sale" s
SET "clientId" = c."id"
FROM "Client" c
WHERE s."clientId" IS NULL
  AND s."companyId" = c."companyId"
  AND s."clientSyncId" = c."syncId";

UPDATE "Sale" s
SET "sellerId" = se."id"
FROM "Seller" se
WHERE s."sellerId" IS NULL
  AND s."companyId" = se."companyId"
  AND s."sellerSyncId" = se."syncId";

UPDATE "Sale" s
SET "lotId" = l."id"
FROM "Lot" l
WHERE s."lotId" IS NULL
  AND s."companyId" = l."companyId"
  AND s."lotSyncId" = l."syncId";

WITH duplicate_active_lot_sales AS (
  SELECT "id",
         ROW_NUMBER() OVER (
           PARTITION BY "companyId", "lotId"
           ORDER BY "updatedAt" DESC, "id"
         ) AS row_number
  FROM "Sale"
  WHERE "deletedAt" IS NULL
    AND COALESCE("status", '') <> 'cancelada'
    AND "lotId" IS NOT NULL
)
UPDATE "Sale" s
SET "lotId" = NULL
FROM duplicate_active_lot_sales d
WHERE s."id" = d."id"
  AND d.row_number > 1;

UPDATE "Sale"
SET "initialPercentage" = COALESCE(
      "initialPercentage",
      NULLIF(regexp_replace(COALESCE("raw"->>'inicial_porcentaje', "raw"->>'initial_percentage'), '[^0-9.\-]', '', 'g'), '')::DECIMAL
    ),
    "initialRequiredAmount" = COALESCE(
      NULLIF(regexp_replace(COALESCE("raw"->>'monto_inicial_requerido', "raw"->>'required_initial_payment'), '[^0-9.\-]', '', 'g'), '')::DECIMAL,
      "initialRequiredAmount"
    ),
    "initialPendingAmount" = COALESCE(
      NULLIF(regexp_replace(COALESCE("raw"->>'monto_inicial_pendiente', "raw"->>'pending_initial_payment'), '[^0-9.\-]', '', 'g'), '')::DECIMAL,
      "initialPendingAmount"
    ),
    "reservationMinimumAmount" = COALESCE(
      NULLIF(regexp_replace(COALESCE("raw"->>'monto_apartado_minimo', "raw"->>'minimum_reserve_amount'), '[^0-9.\-]', '', 'g'), '')::DECIMAL,
      "reservationMinimumAmount"
    ),
    "reservationPaidAmount" = COALESCE(
      NULLIF(regexp_replace(COALESCE("raw"->>'monto_apartado_pagado', "raw"->>'reserve_paid_amount'), '[^0-9.\-]', '', 'g'), '')::DECIMAL,
      "reservationPaidAmount"
    ),
    "initialPaymentDeadline" = COALESCE(
      "initialPaymentDeadline",
      NULLIF(COALESCE("raw"->>'fecha_limite_inicial', "raw"->>'initial_payment_deadline'), '')::TIMESTAMP
    ),
    "activationDate" = COALESCE(
      "activationDate",
      NULLIF(COALESCE("raw"->>'fecha_activacion', "raw"->>'activation_date'), '')::TIMESTAMP
    ),
    "financedBalance" = COALESCE(
      NULLIF(regexp_replace(COALESCE("raw"->>'saldo_financiado', "raw"->>'financed_balance'), '[^0-9.\-]', '', 'g'), '')::DECIMAL,
      "financedBalance"
    ),
    "monthlyInterestRate" = COALESCE(
      "monthlyInterestRate",
      NULLIF(regexp_replace(COALESCE("raw"->>'interes_mensual', "raw"->>'monthly_interest'), '[^0-9.\-]', '', 'g'), '')::DECIMAL
    ),
    "installmentCount" = COALESCE(
      "installmentCount",
      NULLIF(regexp_replace(COALESCE("raw"->>'cantidad_cuotas', "raw"->>'installment_count'), '[^0-9\-]', '', 'g'), '')::INTEGER
    )
WHERE "raw" IS NOT NULL;

ALTER TABLE "Installment" ADD COLUMN IF NOT EXISTS "saleId" TEXT;

UPDATE "Installment" i
SET "saleId" = s."id"
FROM "Sale" s
WHERE i."saleId" IS NULL
  AND i."companyId" = s."companyId"
  AND i."saleSyncId" = s."syncId";

WITH duplicate_active_installments AS (
  SELECT "id",
         ROW_NUMBER() OVER (
           PARTITION BY "companyId", "saleId", "installmentNumber"
           ORDER BY "updatedAt" DESC, "id"
         ) AS row_number
  FROM "Installment"
  WHERE "deletedAt" IS NULL
    AND "saleId" IS NOT NULL
    AND "installmentNumber" IS NOT NULL
)
UPDATE "Installment" i
SET "saleId" = NULL
FROM duplicate_active_installments d
WHERE i."id" = d."id"
  AND d.row_number > 1;

ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "saleId" TEXT;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "clientId" TEXT;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "installmentId" TEXT;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "receivedByUserId" TEXT;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "receivedByUserSyncId" TEXT;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "principalApplied" DECIMAL(14,2) NOT NULL DEFAULT 0;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "interestApplied" DECIMAL(14,2) NOT NULL DEFAULT 0;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "annulledAt" TIMESTAMP(3);
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "annulledByUserId" TEXT;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "annulmentReason" TEXT;
ALTER TABLE "Payment" ADD COLUMN IF NOT EXISTS "reversesPaymentId" TEXT;

UPDATE "Payment" p
SET "saleId" = s."id"
FROM "Sale" s
WHERE p."saleId" IS NULL
  AND p."companyId" = s."companyId"
  AND p."saleSyncId" = s."syncId";

UPDATE "Payment" p
SET "clientId" = c."id"
FROM "Client" c
WHERE p."clientId" IS NULL
  AND p."companyId" = c."companyId"
  AND p."clientSyncId" = c."syncId";

UPDATE "Payment" p
SET "installmentId" = i."id"
FROM "Installment" i
WHERE p."installmentId" IS NULL
  AND p."companyId" = i."companyId"
  AND p."installmentSyncId" = i."syncId";

UPDATE "Payment"
SET "receivedByUserSyncId" = COALESCE("receivedByUserSyncId", "raw"->>'usuario_sync_id', "raw"->>'user_sync_id'),
    "principalApplied" = COALESCE(
      NULLIF(regexp_replace(COALESCE("raw"->>'capital_aplicado', "raw"->>'principal_applied'), '[^0-9.\-]', '', 'g'), '')::DECIMAL,
      "principalApplied"
    ),
    "interestApplied" = COALESCE(
      NULLIF(regexp_replace(COALESCE("raw"->>'interes_aplicado', "raw"->>'interest_applied'), '[^0-9.\-]', '', 'g'), '')::DECIMAL,
      "interestApplied"
    ),
    "annulledAt" = COALESCE(
      "annulledAt",
      CASE WHEN "deletedAt" IS NOT NULL THEN "deletedAt" ELSE NULL END
    )
WHERE "raw" IS NOT NULL OR "deletedAt" IS NOT NULL;

UPDATE "Payment" p
SET "receivedByUserId" = u."id"
FROM "User" u
WHERE p."receivedByUserId" IS NULL
  AND p."companyId" = u."companyId"
  AND p."receivedByUserSyncId" IS NOT NULL
  AND p."receivedByUserSyncId" = u."syncId";

CREATE TABLE IF NOT EXISTS "BusinessRole" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "syncId" TEXT,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BusinessRole_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BusinessUserRole" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "roleId" TEXT NOT NULL,
    "syncId" TEXT,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BusinessUserRole_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "Permission" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "syncId" TEXT,
    "userId" TEXT,
    "module" TEXT NOT NULL,
    "actions" JSONB NOT NULL DEFAULT '[]',
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Permission_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BusinessRolePermission" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "roleId" TEXT NOT NULL,
    "permissionId" TEXT NOT NULL,
    "syncId" TEXT,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BusinessRolePermission_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "CompanyProfile" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "syncId" TEXT,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "address" TEXT,
    "logoBase64" TEXT,
    "logoLocalPath" TEXT,
    "logoRemoteUrl" TEXT,
    "logoUploadStatus" TEXT,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CompanyProfile_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FinancialParameters" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "syncId" TEXT,
    "initialPercentage" DECIMAL(8,4),
    "monthlyInterestRate" DECIMAL(8,4),
    "installmentCount" INTEGER,
    "currencySymbol" TEXT,
    "decimalPlaces" INTEGER,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FinancialParameters_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "BusinessConfiguration" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "value" TEXT,
    "valueJson" JSONB,
    "description" TEXT,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BusinessConfiguration_pkey" PRIMARY KEY ("id")
);

INSERT INTO "CompanyProfile" ("id", "companyId", "name", "updatedAt")
SELECT 'alto-dona-mamita-company-profile', c."id", c."name", CURRENT_TIMESTAMP
FROM "Company" c
WHERE c."id" = 'alto-dona-mamita-company'
ON CONFLICT DO NOTHING;

CREATE UNIQUE INDEX IF NOT EXISTS "User_companyId_syncId_key" ON "User"("companyId", "syncId");
CREATE INDEX IF NOT EXISTS "User_companyId_updatedAt_idx" ON "User"("companyId", "updatedAt");
CREATE INDEX IF NOT EXISTS "User_companyId_remoteAuthId_idx" ON "User"("companyId", "remoteAuthId");

CREATE INDEX IF NOT EXISTS "Sale_companyId_lotId_idx" ON "Sale"("companyId", "lotId");
CREATE INDEX IF NOT EXISTS "Sale_companyId_clientId_idx" ON "Sale"("companyId", "clientId");
CREATE INDEX IF NOT EXISTS "Sale_companyId_operatorUserId_idx" ON "Sale"("companyId", "operatorUserId");

CREATE INDEX IF NOT EXISTS "Installment_companyId_saleId_idx" ON "Installment"("companyId", "saleId");

CREATE INDEX IF NOT EXISTS "Payment_companyId_saleId_idx" ON "Payment"("companyId", "saleId");
CREATE INDEX IF NOT EXISTS "Payment_companyId_clientId_idx" ON "Payment"("companyId", "clientId");
CREATE INDEX IF NOT EXISTS "Payment_companyId_installmentId_idx" ON "Payment"("companyId", "installmentId");
CREATE INDEX IF NOT EXISTS "Payment_companyId_receivedByUserId_idx" ON "Payment"("companyId", "receivedByUserId");

CREATE UNIQUE INDEX IF NOT EXISTS "Sale_companyId_lotId_active_unique"
ON "Sale"("companyId", "lotId")
WHERE "deletedAt" IS NULL
  AND COALESCE("status", '') <> 'cancelada'
  AND "lotId" IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "Installment_companyId_saleId_installmentNumber_active_unique"
ON "Installment"("companyId", "saleId", "installmentNumber")
WHERE "deletedAt" IS NULL
  AND "saleId" IS NOT NULL
  AND "installmentNumber" IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "BusinessRole_companyId_syncId_key" ON "BusinessRole"("companyId", "syncId");
CREATE UNIQUE INDEX IF NOT EXISTS "BusinessRole_companyId_code_key" ON "BusinessRole"("companyId", "code");
CREATE INDEX IF NOT EXISTS "BusinessRole_companyId_updatedAt_idx" ON "BusinessRole"("companyId", "updatedAt");

CREATE UNIQUE INDEX IF NOT EXISTS "BusinessUserRole_companyId_syncId_key" ON "BusinessUserRole"("companyId", "syncId");
CREATE UNIQUE INDEX IF NOT EXISTS "BusinessUserRole_companyId_userId_roleId_key" ON "BusinessUserRole"("companyId", "userId", "roleId");
CREATE INDEX IF NOT EXISTS "BusinessUserRole_companyId_updatedAt_idx" ON "BusinessUserRole"("companyId", "updatedAt");

CREATE UNIQUE INDEX IF NOT EXISTS "Permission_companyId_syncId_key" ON "Permission"("companyId", "syncId");
CREATE UNIQUE INDEX IF NOT EXISTS "Permission_companyId_userId_module_key" ON "Permission"("companyId", "userId", "module");
CREATE INDEX IF NOT EXISTS "Permission_companyId_updatedAt_idx" ON "Permission"("companyId", "updatedAt");

CREATE UNIQUE INDEX IF NOT EXISTS "BusinessRolePermission_companyId_syncId_key" ON "BusinessRolePermission"("companyId", "syncId");
CREATE UNIQUE INDEX IF NOT EXISTS "BusinessRolePermission_companyId_roleId_permissionId_key" ON "BusinessRolePermission"("companyId", "roleId", "permissionId");
CREATE INDEX IF NOT EXISTS "BusinessRolePermission_companyId_updatedAt_idx" ON "BusinessRolePermission"("companyId", "updatedAt");

CREATE UNIQUE INDEX IF NOT EXISTS "CompanyProfile_companyId_key" ON "CompanyProfile"("companyId");
CREATE UNIQUE INDEX IF NOT EXISTS "CompanyProfile_companyId_syncId_key" ON "CompanyProfile"("companyId", "syncId");
CREATE INDEX IF NOT EXISTS "CompanyProfile_companyId_updatedAt_idx" ON "CompanyProfile"("companyId", "updatedAt");

CREATE UNIQUE INDEX IF NOT EXISTS "FinancialParameters_companyId_key" ON "FinancialParameters"("companyId");
CREATE UNIQUE INDEX IF NOT EXISTS "FinancialParameters_companyId_syncId_key" ON "FinancialParameters"("companyId", "syncId");

CREATE UNIQUE INDEX IF NOT EXISTS "BusinessConfiguration_companyId_key_key" ON "BusinessConfiguration"("companyId", "key");
CREATE INDEX IF NOT EXISTS "BusinessConfiguration_companyId_updatedAt_idx" ON "BusinessConfiguration"("companyId", "updatedAt");

ALTER TABLE "User"
ADD CONSTRAINT "User_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Sale"
ADD CONSTRAINT "Sale_clientId_fkey"
FOREIGN KEY ("clientId") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Sale"
ADD CONSTRAINT "Sale_lotId_fkey"
FOREIGN KEY ("lotId") REFERENCES "Lot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Sale"
ADD CONSTRAINT "Sale_sellerId_fkey"
FOREIGN KEY ("sellerId") REFERENCES "Seller"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Sale"
ADD CONSTRAINT "Sale_operatorUserId_fkey"
FOREIGN KEY ("operatorUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Installment"
ADD CONSTRAINT "Installment_saleId_fkey"
FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Payment"
ADD CONSTRAINT "Payment_saleId_fkey"
FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Payment"
ADD CONSTRAINT "Payment_clientId_fkey"
FOREIGN KEY ("clientId") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Payment"
ADD CONSTRAINT "Payment_installmentId_fkey"
FOREIGN KEY ("installmentId") REFERENCES "Installment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Payment"
ADD CONSTRAINT "Payment_receivedByUserId_fkey"
FOREIGN KEY ("receivedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Payment"
ADD CONSTRAINT "Payment_annulledByUserId_fkey"
FOREIGN KEY ("annulledByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Payment"
ADD CONSTRAINT "Payment_reversesPaymentId_fkey"
FOREIGN KEY ("reversesPaymentId") REFERENCES "Payment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "BusinessRole"
ADD CONSTRAINT "BusinessRole_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "BusinessUserRole"
ADD CONSTRAINT "BusinessUserRole_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "BusinessUserRole"
ADD CONSTRAINT "BusinessUserRole_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "BusinessUserRole"
ADD CONSTRAINT "BusinessUserRole_roleId_fkey"
FOREIGN KEY ("roleId") REFERENCES "BusinessRole"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Permission"
ADD CONSTRAINT "Permission_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "Permission"
ADD CONSTRAINT "Permission_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "BusinessRolePermission"
ADD CONSTRAINT "BusinessRolePermission_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "BusinessRolePermission"
ADD CONSTRAINT "BusinessRolePermission_roleId_fkey"
FOREIGN KEY ("roleId") REFERENCES "BusinessRole"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "BusinessRolePermission"
ADD CONSTRAINT "BusinessRolePermission_permissionId_fkey"
FOREIGN KEY ("permissionId") REFERENCES "Permission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "CompanyProfile"
ADD CONSTRAINT "CompanyProfile_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "FinancialParameters"
ADD CONSTRAINT "FinancialParameters_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "BusinessConfiguration"
ADD CONSTRAINT "BusinessConfiguration_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
