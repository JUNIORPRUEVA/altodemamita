ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "sync_payload" JSONB;
ALTER TABLE "sales" ADD COLUMN IF NOT EXISTS "sync_payload" JSONB;
ALTER TABLE "installments" ADD COLUMN IF NOT EXISTS "sync_payload" JSONB;
ALTER TABLE "payments" ADD COLUMN IF NOT EXISTS "sync_payload" JSONB;