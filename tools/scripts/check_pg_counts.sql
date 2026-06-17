SELECT 'Client' AS tabla,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL) AS activos,
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL) AS eliminados
FROM "Client"
UNION ALL
SELECT 'Seller',
  COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Seller"
UNION ALL
SELECT 'Lot',
  COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Lot"
UNION ALL
SELECT 'Sale',
  COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Sale"
UNION ALL
SELECT 'Installment',
  COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Installment"
UNION ALL
SELECT 'Payment',
  COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Payment";
