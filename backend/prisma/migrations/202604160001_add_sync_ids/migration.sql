ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "users" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "users" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "users_sync_id_key" ON "users"("sync_id");

ALTER TABLE "roles" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "roles" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "roles" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "roles_sync_id_key" ON "roles"("sync_id");

ALTER TABLE "permissions" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "permissions" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "permissions" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "permissions_sync_id_key" ON "permissions"("sync_id");

ALTER TABLE "clients" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "clients" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "clients" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "clients_sync_id_key" ON "clients"("sync_id");

ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "products" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "products" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "products_sync_id_key" ON "products"("sync_id");

ALTER TABLE "sales" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "sales" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "sales" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "sales_sync_id_key" ON "sales"("sync_id");

ALTER TABLE "installments" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "installments" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "installments" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "installments_sync_id_key" ON "installments"("sync_id");

ALTER TABLE "payments" ADD COLUMN IF NOT EXISTS "sync_id" TEXT;
UPDATE "payments" SET "sync_id" = "id"::text WHERE "sync_id" IS NULL OR btrim("sync_id") = '';
ALTER TABLE "payments" ALTER COLUMN "sync_id" SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "payments_sync_id_key" ON "payments"("sync_id");