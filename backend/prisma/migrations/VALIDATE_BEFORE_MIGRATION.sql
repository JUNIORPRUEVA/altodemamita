-- Pre-migration validation script for FK constraints
-- This script checks for orphaned records that would violate the new RESTRICT constraints
-- Run this BEFORE applying the migration to identify any data integrity issues

-- Check 1: Sales with non-existent clients
SELECT COUNT(*) as orphaned_sales_no_client
FROM sales s
LEFT JOIN clients c ON s.client_id = c.id
WHERE c.id IS NULL;

-- Check 2: Sales with non-existent users
SELECT COUNT(*) as orphaned_sales_no_user
FROM sales s
LEFT JOIN users u ON s.user_id = u.id
WHERE u.id IS NULL;

-- Check 3: Sales with non-existent products
SELECT COUNT(*) as orphaned_sales_no_product
FROM sales s
LEFT JOIN products p ON s.product_id = p.id
WHERE p.id IS NULL;

-- Check 4: Sales with non-existent sellers (optional seller_id)
SELECT COUNT(*) as orphaned_sales_no_seller
FROM sales s
LEFT JOIN sellers sl ON s.seller_id = sl.id
WHERE s.seller_id IS NOT NULL AND sl.id IS NULL;

-- Check 5: Payments with non-existent sales
SELECT COUNT(*) as orphaned_payments_no_sale
FROM payments p
LEFT JOIN sales s ON p.sale_id = s.id
WHERE s.id IS NULL;

-- Check 6: Payments with non-existent installments (optional installment_id)
SELECT COUNT(*) as orphaned_payments_no_installment
FROM payments p
LEFT JOIN installments i ON p.installment_id = i.id
WHERE p.installment_id IS NOT NULL AND i.id IS NULL;

-- Check 7: Installments with non-existent sales
SELECT COUNT(*) as orphaned_installments_no_sale
FROM installments i
LEFT JOIN sales s ON i.sale_id = s.id
WHERE s.id IS NULL;

-- If all counts are 0, the migration is safe to apply
-- If any count is > 0, investigate and fix the orphaned records before migrating
