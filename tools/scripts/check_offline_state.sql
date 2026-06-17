-- Verificación del estado offline de la app Windows
-- Ejecutar contra: app_support_dir/database/sistema_solares.db

-- 1. Resumen de sync_queue
SELECT scope, operation, COUNT(*) AS total
FROM sync_queue
GROUP BY scope, operation
ORDER BY scope, operation;

-- 2. Sync status por tabla
SELECT 'clientes' AS tabla, sync_status, COUNT(*) AS total
FROM clientes WHERE nombre LIKE '%OFFCLIENT%' OR documento LIKE '%OFFCLIENT%'
GROUP BY sync_status
UNION ALL
SELECT 'vendedores', sync_status, COUNT(*)
FROM vendedores WHERE nombre LIKE '%OFFSELLER%'
GROUP BY sync_status
UNION ALL
SELECT 'solares', sync_status, COUNT(*)
FROM solares WHERE manzana_numero = 'OFF' AND lote_numero = '100'
GROUP BY sync_status
UNION ALL
SELECT 'ventas', sync_status, COUNT(*)
FROM ventas v
WHERE EXISTS (
  SELECT 1 FROM clientes c
  WHERE c.id = v.cliente_id AND c.nombre LIKE '%OFFCLIENT%'
)
GROUP BY sync_status
ORDER BY tabla;

-- 3. Detalle de solares OFF-100
SELECT id, sync_id, manzana_numero, lote_numero, sync_status, deleted_at, created_at, updated_at
FROM solares
WHERE manzana_numero = 'OFF' AND lote_numero = '100';

-- 4. Detalle de sync_queue para OFF-100
SELECT sq.id, sq.scope, sq.operation, sq.record_sync_id, sq.payload, sq.attempt_count, sq.last_error, sq.created_at
FROM sync_queue sq
WHERE sq.record_sync_id IN (
  SELECT sync_id FROM solares WHERE manzana_numero = 'OFF' AND lote_numero = '100'
)
ORDER BY sq.created_at;
