BEGIN;

-- 1. Revise primero que productos estan ocultos por borrado logico o estado inactivo.
SELECT id, code, name, is_active, deleted_at, updated_at
FROM products
WHERE deleted_at IS NOT NULL OR is_active = FALSE
ORDER BY updated_at DESC;

-- 2. Descomente y ajuste el filtro si necesita restaurar solo un subconjunto.
-- UPDATE products
-- SET
--   deleted_at = NULL,
--   is_active = TRUE,
--   sync_status = 'pending',
--   updated_at = NOW()
-- WHERE code IN ('CODIGO-1', 'CODIGO-2');

-- 3. Reparacion amplia para volver visibles todos los productos ocultos.
UPDATE products
SET
  deleted_at = NULL,
  is_active = TRUE,
  sync_status = 'pending',
  updated_at = NOW()
WHERE deleted_at IS NOT NULL OR is_active = FALSE;

COMMIT;