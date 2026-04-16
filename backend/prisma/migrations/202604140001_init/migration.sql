CREATE TYPE "SyncStatus" AS ENUM ('pending', 'synced');
CREATE TYPE "RoleCode" AS ENUM ('SUPER_ADMIN', 'ADMIN', 'MANAGER', 'CASHIER', 'SALES_AGENT');
CREATE TYPE "SaleStatus" AS ENUM ('draft', 'active', 'completed', 'cancelled', 'overdue');
CREATE TYPE "PaymentMethod" AS ENUM ('cash', 'transfer', 'card', 'check', 'mobile_wallet', 'mixed');
CREATE TYPE "InstallmentStatus" AS ENUM ('pending', 'paid', 'overdue', 'partial', 'cancelled');

CREATE TABLE "users" (
  "id" UUID PRIMARY KEY,
  "email" TEXT NOT NULL UNIQUE,
  "username" TEXT NOT NULL UNIQUE,
  "full_name" TEXT NOT NULL,
  "password_hash" TEXT NOT NULL,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL
);

CREATE TABLE "roles" (
  "id" UUID PRIMARY KEY,
  "code" "RoleCode" NOT NULL UNIQUE,
  "name" TEXT NOT NULL UNIQUE,
  "description" TEXT NULL,
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL
);

CREATE TABLE "permissions" (
  "id" UUID PRIMARY KEY,
  "code" TEXT NOT NULL UNIQUE,
  "name" TEXT NOT NULL,
  "description" TEXT NULL,
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL
);

CREATE TABLE "user_roles" (
  "id" UUID PRIMARY KEY,
  "user_id" UUID NOT NULL REFERENCES "users"("id"),
  "role_id" UUID NOT NULL REFERENCES "roles"("id"),
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL,
  UNIQUE("user_id", "role_id")
);

CREATE TABLE "role_permissions" (
  "id" UUID PRIMARY KEY,
  "role_id" UUID NOT NULL REFERENCES "roles"("id"),
  "permission_id" UUID NOT NULL REFERENCES "permissions"("id"),
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL,
  UNIQUE("role_id", "permission_id")
);

CREATE TABLE "clients" (
  "id" UUID PRIMARY KEY,
  "code" TEXT UNIQUE,
  "first_name" TEXT NOT NULL,
  "last_name" TEXT NOT NULL,
  "document_id" TEXT NULL,
  "email" TEXT NULL,
  "phone" TEXT NULL,
  "address" TEXT NULL,
  "notes" TEXT NULL,
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL
);

CREATE TABLE "products" (
  "id" UUID PRIMARY KEY,
  "code" TEXT NOT NULL UNIQUE,
  "name" TEXT NOT NULL,
  "description" TEXT NULL,
  "price" DECIMAL(18,2) NOT NULL,
  "financing_price" DECIMAL(18,2) NULL,
  "stock" INTEGER NOT NULL DEFAULT 0,
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL
);

CREATE TABLE "sales" (
  "id" UUID PRIMARY KEY,
  "client_id" UUID NOT NULL REFERENCES "clients"("id"),
  "user_id" UUID NOT NULL REFERENCES "users"("id"),
  "product_id" UUID NOT NULL REFERENCES "products"("id"),
  "contract_number" TEXT UNIQUE,
  "sale_date" TIMESTAMPTZ NOT NULL,
  "principal_amount" DECIMAL(18,2) NOT NULL,
  "financed_amount" DECIMAL(18,2) NOT NULL,
  "down_payment" DECIMAL(18,2) NOT NULL,
  "interest_rate" DECIMAL(8,4) NOT NULL,
  "total_amount" DECIMAL(18,2) NOT NULL,
  "term_months" INTEGER NOT NULL,
  "paid_amount" DECIMAL(18,2) NOT NULL DEFAULT 0,
  "outstanding_balance" DECIMAL(18,2) NOT NULL,
  "status" "SaleStatus" NOT NULL DEFAULT 'active',
  "notes" TEXT NULL,
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL
);

CREATE TABLE "installments" (
  "id" UUID PRIMARY KEY,
  "sale_id" UUID NOT NULL REFERENCES "sales"("id"),
  "installment_number" INTEGER NOT NULL,
  "due_date" TIMESTAMPTZ NOT NULL,
  "amount" DECIMAL(18,2) NOT NULL,
  "principal_amount" DECIMAL(18,2) NOT NULL,
  "interest_amount" DECIMAL(18,2) NOT NULL,
  "paid_amount" DECIMAL(18,2) NOT NULL DEFAULT 0,
  "status" "InstallmentStatus" NOT NULL DEFAULT 'pending',
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL,
  UNIQUE("sale_id", "installment_number")
);

CREATE TABLE "payments" (
  "id" UUID PRIMARY KEY,
  "sale_id" UUID NOT NULL REFERENCES "sales"("id"),
  "installment_id" UUID NULL REFERENCES "installments"("id"),
  "payment_date" TIMESTAMPTZ NOT NULL,
  "amount" DECIMAL(18,2) NOT NULL,
  "principal_amount" DECIMAL(18,2) NOT NULL,
  "interest_amount" DECIMAL(18,2) NOT NULL,
  "method" "PaymentMethod" NOT NULL,
  "reference" TEXT NULL,
  "notes" TEXT NULL,
  "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ NULL
);

CREATE INDEX "clients_document_id_idx" ON "clients"("document_id");
CREATE INDEX "sales_client_id_idx" ON "sales"("client_id");
CREATE INDEX "sales_user_id_idx" ON "sales"("user_id");
CREATE INDEX "sales_product_id_idx" ON "sales"("product_id");
CREATE INDEX "sales_status_idx" ON "sales"("status");
CREATE INDEX "payments_sale_id_idx" ON "payments"("sale_id");
CREATE INDEX "payments_installment_id_idx" ON "payments"("installment_id");
CREATE INDEX "installments_sale_id_idx" ON "installments"("sale_id");
CREATE INDEX "installments_status_idx" ON "installments"("status");