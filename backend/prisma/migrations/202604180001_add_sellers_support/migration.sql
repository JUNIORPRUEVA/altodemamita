CREATE TABLE IF NOT EXISTS "sellers" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "sync_id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "document_id" TEXT,
    "phone" TEXT,
    "sync_status" "SyncStatus" NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "sellers_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "sellers_sync_id_key" ON "sellers"("sync_id");
CREATE INDEX IF NOT EXISTS "sellers_document_id_idx" ON "sellers"("document_id");

ALTER TABLE "sales"
ADD COLUMN IF NOT EXISTS "seller_id" UUID;

CREATE INDEX IF NOT EXISTS "sales_seller_id_idx" ON "sales"("seller_id");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'sales_seller_id_fkey'
      AND table_name = 'sales'
  ) THEN
    ALTER TABLE "sales"
    ADD CONSTRAINT "sales_seller_id_fkey"
    FOREIGN KEY ("seller_id") REFERENCES "sellers"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;