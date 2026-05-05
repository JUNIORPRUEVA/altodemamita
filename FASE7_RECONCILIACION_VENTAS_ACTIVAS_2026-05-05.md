# FASE 7 - Reconciliacion exacta de ventas activas local vs backend

Fecha: 2026-05-05

## Backup previo

Backup SQLite local creado antes de la auditoria:

- `C:\Users\pc\DEV\PROYECTOS\CLIENTES\SISTEMA_SOLARES\backups\phase7\sistema_solares_phase7_*.db`

## Limitaciones operativas confirmadas

- La API backend publica responde en `https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api`.
- El `DATABASE_URL` del backend apunta a un host interno de EasyPanel: `altodemamita_altomamita-postgres`.
- En esta maquina no hay `psql` ni `pg_dump` instalados.
- Las credenciales documentadas del repo no autentican contra el backend vivo, por lo que no fue posible hacer export SQL remoto ni listar ventas activas vivas por API desde esta sesion.

## Estado local actual confirmado

Ventas activas locales actuales en SQLite:

1. `0280dcc1-1e95-447a-b7d2-3a633ce27c3c`
   - `id_remote`: `39dd6dba-8f12-4992-966b-6e890feb4ad8`
   - estado: `activa`
   - cuotas activas: `12`
   - pagos activos: `2`
   - cliente padre local: soft-deleted
   - producto padre local: soft-deleted

2. `b1f2c23e-49a5-4046-a0f8-c417188ffda0`
   - `id_remote`: `2984a4fb-11a6-4ad5-bdfd-f702817a69d0`
   - estado: `activa`
   - cuotas activas: `68`
   - pagos activos: `0`
   - cliente padre local: soft-deleted
   - producto padre local: soft-deleted

## Venta inconsistente identificada

La venta exacta faltante localmente es:

- `sync_id`: `e6268bad-f111-4afe-8f7a-5712b23e4691`
- `id_remote`: `df4992da-caa5-4173-8bc6-d97089a290ae`
- estado historico auditado: `activa`
- cliente relacionado: `9cbb5c5f-2f4c-4b36-9c70-1973b0441bc5`
- producto relacionado: `f5091c58-9c72-4876-aeb0-62347ff026ce`
- cuotas historicas auditadas: `59`
- pagos historicos auditados: `1`

## Evidencia

1. En `audit_sales_sync_state_output.txt` aparece como venta activa local historica con 59 cuotas activas y 1 pago activo.
2. En el SQLite actual ya no existe ninguna fila `ventas.sync_id = e6268bad-f111-4afe-8f7a-5712b23e4691`.
3. En el SQLite actual sigue existiendo evidencia forense en `conflict_logs`:
   - scope: `sales`
   - record_sync_id: `e6268bad-f111-4afe-8f7a-5712b23e4691`
   - resolution: `server_won`
   - mensaje: `Conflicto de sincronizacion: no se puede borrar la venta en la nube porque ya tiene pagos registrados. Se requiere revision manual.`
4. En el SQLite actual los padres locales de esa venta estan soft-deleted:
   - cliente `9cbb5c5f-2f4c-4b36-9c70-1973b0441bc5`
   - producto `f5091c58-9c72-4876-aeb0-62347ff026ce`

## Conclusion tecnica

La inconsistencia actual no apunta a una venta local oculta sino a una venta remota previamente conocida que dejo de materializarse en SQLite.

La venta exacta a reconciliar es `e6268bad-f111-4afe-8f7a-5712b23e4691`.

No corresponde hacer hard delete:

- existe evidencia de al menos un pago relacionado;
- existe conflicto historico indicando que la nube no acepto su borrado automatico;
- no se pudo verificar export SQL del backend vivo desde esta sesion.

## Recomendacion de siguiente paso seguro

1. Obtener acceso autenticado al backend vivo o export SQL de `sales`, `installments`, `payments`, `clients` y `products`.
2. Verificar el estado actual de `df4992da-caa5-4173-8bc6-d97089a290ae` en backend.
3. Si backend la mantiene activa con pagos/cuotas, rehidratar localmente la venta y sus dependencias; no borrar.
4. Si backend ya no la mantiene activa, entonces revisar por que la evidencia local conserva conflicto `server_won` y pagos historicos antes de cualquier accion destructiva.
