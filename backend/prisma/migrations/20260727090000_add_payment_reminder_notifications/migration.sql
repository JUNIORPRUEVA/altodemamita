CREATE TABLE "PaymentReminderNotification" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "clientSyncId" TEXT,
    "saleSyncId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "period" TEXT,
    "lastOverdueInstallmentSyncId" TEXT NOT NULL,
    "overdueInstallmentCount" INTEGER NOT NULL,
    "pendingPrincipal" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "lateFeeTotal" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "totalDue" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "destinationPhone" TEXT,
    "templateName" TEXT,
    "whatsappMessageId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "error" TEXT,
    "scheduledAt" TIMESTAMP(3),
    "sentAt" TIMESTAMP(3),
    "payload" JSONB,
    "testMode" BOOLEAN NOT NULL DEFAULT false,
    "redirected" BOOLEAN NOT NULL DEFAULT false,
    "originalRecipientMasked" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PaymentReminderNotification_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PaymentReminderDelivery" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "actualRecipient" TEXT NOT NULL,
    "originalRecipientMasked" TEXT,
    "testMode" BOOLEAN NOT NULL DEFAULT false,
    "redirected" BOOLEAN NOT NULL DEFAULT false,
    "whatsappMessageId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "error" TEXT,
    "sentAt" TIMESTAMP(3),
    "deliveredAt" TIMESTAMP(3),
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PaymentReminderDelivery_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "LateFeeSnapshot" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "clientSyncId" TEXT,
    "saleSyncId" TEXT NOT NULL,
    "installmentSyncId" TEXT NOT NULL,
    "calculatedAt" TIMESTAMP(3) NOT NULL,
    "baseBalance" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "overdueDays" INTEGER NOT NULL,
    "dailyRate" DECIMAL(8,6) NOT NULL DEFAULT 0,
    "calculatedLateFee" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "eventType" TEXT NOT NULL,
    "notificationId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LateFeeSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PaymentReminderNotification_companyId_saleSyncId_type_lastOverdueInstallmentSyncId_key"
ON "PaymentReminderNotification"("companyId", "saleSyncId", "type", "lastOverdueInstallmentSyncId");

CREATE INDEX "PaymentReminderNotification_companyId_status_createdAt_idx"
ON "PaymentReminderNotification"("companyId", "status", "createdAt");

CREATE INDEX "PaymentReminderNotification_companyId_whatsappMessageId_idx"
ON "PaymentReminderNotification"("companyId", "whatsappMessageId");

CREATE UNIQUE INDEX "PaymentReminderDelivery_notificationId_actualRecipient_key"
ON "PaymentReminderDelivery"("notificationId", "actualRecipient");

CREATE INDEX "PaymentReminderDelivery_whatsappMessageId_idx"
ON "PaymentReminderDelivery"("whatsappMessageId");

CREATE INDEX "PaymentReminderDelivery_status_createdAt_idx"
ON "PaymentReminderDelivery"("status", "createdAt");

CREATE INDEX "LateFeeSnapshot_companyId_saleSyncId_calculatedAt_idx"
ON "LateFeeSnapshot"("companyId", "saleSyncId", "calculatedAt");

CREATE INDEX "LateFeeSnapshot_companyId_installmentSyncId_idx"
ON "LateFeeSnapshot"("companyId", "installmentSyncId");

ALTER TABLE "PaymentReminderNotification"
ADD CONSTRAINT "PaymentReminderNotification_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "LateFeeSnapshot"
ADD CONSTRAINT "LateFeeSnapshot_companyId_fkey"
FOREIGN KEY ("companyId") REFERENCES "Company"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "PaymentReminderDelivery"
ADD CONSTRAINT "PaymentReminderDelivery_notificationId_fkey"
FOREIGN KEY ("notificationId") REFERENCES "PaymentReminderNotification"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
