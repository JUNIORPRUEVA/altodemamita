-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('OWNER', 'TECH');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" "UserRole" NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Client" (
    "id" TEXT NOT NULL,
    "syncId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "document" TEXT,
    "phone" TEXT,
    "address" TEXT,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Client_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Seller" (
    "id" TEXT NOT NULL,
    "syncId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "document" TEXT,
    "phone" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Seller_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Lot" (
    "id" TEXT NOT NULL,
    "syncId" TEXT NOT NULL,
    "block" TEXT,
    "number" TEXT,
    "status" TEXT,
    "area" DECIMAL(14,2),
    "price" DECIMAL(14,2),
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Lot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Sale" (
    "id" TEXT NOT NULL,
    "syncId" TEXT NOT NULL,
    "clientSyncId" TEXT,
    "lotSyncId" TEXT,
    "sellerSyncId" TEXT,
    "saleDate" TIMESTAMP(3),
    "status" TEXT,
    "total" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "initialPaid" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "balance" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Sale_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Installment" (
    "id" TEXT NOT NULL,
    "syncId" TEXT NOT NULL,
    "saleSyncId" TEXT,
    "installmentNumber" INTEGER,
    "dueDate" TIMESTAMP(3),
    "openingBalance" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "principalAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "interestAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "totalAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "paidAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "paidPrincipalAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "paidInterestAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "endingBalance" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "status" TEXT,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Installment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Payment" (
    "id" TEXT NOT NULL,
    "syncId" TEXT NOT NULL,
    "saleSyncId" TEXT,
    "clientSyncId" TEXT,
    "installmentSyncId" TEXT,
    "paidAt" TIMESTAMP(3),
    "amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "method" TEXT,
    "paymentType" TEXT,
    "reference" TEXT,
    "yearToPay" INTEGER,
    "raw" JSONB,
    "version" INTEGER NOT NULL DEFAULT 1,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Payment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SyncBatch" (
    "id" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "receivedCounts" JSONB NOT NULL,
    "appliedCounts" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SyncBatch_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "Client_syncId_key" ON "Client"("syncId");

-- CreateIndex
CREATE UNIQUE INDEX "Seller_syncId_key" ON "Seller"("syncId");

-- CreateIndex
CREATE UNIQUE INDEX "Lot_syncId_key" ON "Lot"("syncId");

-- CreateIndex
CREATE UNIQUE INDEX "Sale_syncId_key" ON "Sale"("syncId");

-- CreateIndex
CREATE UNIQUE INDEX "Installment_syncId_key" ON "Installment"("syncId");

-- CreateIndex
CREATE UNIQUE INDEX "Payment_syncId_key" ON "Payment"("syncId");

