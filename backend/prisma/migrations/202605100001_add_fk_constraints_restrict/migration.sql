-- Migration for adding Foreign Key Constraints with onDelete: Restrict
-- PASO 3: Orphan Records Prevention
-- This migration modifies existing foreign key relationships to use RESTRICT delete action
-- This prevents deletion of parent records that have child references

-- Step 1: Drop existing FK constraints (they default to CASCADE or similar)
-- These will be replaced with RESTRICT constraints

ALTER TABLE "sales"
DROP CONSTRAINT IF EXISTS "sales_client_id_fkey";

ALTER TABLE "sales"
DROP CONSTRAINT IF EXISTS "sales_user_id_fkey";

ALTER TABLE "sales"
DROP CONSTRAINT IF EXISTS "sales_product_id_fkey";

ALTER TABLE "sales"
DROP CONSTRAINT IF EXISTS "sales_seller_id_fkey";

ALTER TABLE "payments"
DROP CONSTRAINT IF EXISTS "payments_sale_id_fkey";

ALTER TABLE "payments"
DROP CONSTRAINT IF EXISTS "payments_installment_id_fkey";

ALTER TABLE "installments"
DROP CONSTRAINT IF EXISTS "installments_sale_id_fkey";

-- Step 2: Recreate FK constraints with RESTRICT delete action

ALTER TABLE "sales"
ADD CONSTRAINT "sales_client_id_fkey" 
FOREIGN KEY ("client_id") REFERENCES "clients"("id") ON DELETE RESTRICT;

ALTER TABLE "sales"
ADD CONSTRAINT "sales_user_id_fkey" 
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT;

ALTER TABLE "sales"
ADD CONSTRAINT "sales_product_id_fkey" 
FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT;

ALTER TABLE "sales"
ADD CONSTRAINT "sales_seller_id_fkey" 
FOREIGN KEY ("seller_id") REFERENCES "sellers"("id") ON DELETE RESTRICT;

ALTER TABLE "payments"
ADD CONSTRAINT "payments_sale_id_fkey" 
FOREIGN KEY ("sale_id") REFERENCES "sales"("id") ON DELETE RESTRICT;

ALTER TABLE "payments"
ADD CONSTRAINT "payments_installment_id_fkey" 
FOREIGN KEY ("installment_id") REFERENCES "installments"("id") ON DELETE RESTRICT;

ALTER TABLE "installments"
ADD CONSTRAINT "installments_sale_id_fkey" 
FOREIGN KEY ("sale_id") REFERENCES "sales"("id") ON DELETE RESTRICT;
