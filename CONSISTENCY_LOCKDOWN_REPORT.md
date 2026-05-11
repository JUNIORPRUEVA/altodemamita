# CONSISTENCY LOCKDOWN REPORT

## Scope
FASE 3 ejecutada con alcance estricto de consistencia offline-first.

Reglas cumplidas:
- Sin features nuevas.
- Sin cambios de UI.
- Sin refactor masivo.
- Sin cambios de arquitectura.
- Solo hardening de consistencia y anti-corrupcion.

## Riesgos Corregidos

### 1) Force-delete de ventas bloqueado en backend
- Archivo: backend/src/modules/sales/infrastructure/controllers/sales.controller.ts
- Cambio: endpoint `DELETE /sales/force-delete/:id` ahora responde 403.
- Resultado: se elimina el borrado permanente de ventas desde API.

### 2) Delete de pagos bloqueado en backend (append-only)
- Archivo: backend/src/modules/payments/infrastructure/controllers/payments.controller.ts
- Cambio: `DELETE /payments/:id` ahora responde 403.
- Resultado: pagos quedan bajo politica append-only.

### 3) Delete de pagos bloqueado en cliente local
- Archivo: lib/features/payments/data/payments_repository.dart
- Cambio: `deletePayment(...)` lanza `StateError` de lockdown.
- Resultado: evita anulacion/borrado local accidental por flujo de UI/servicio.

### 4) Anti-revive en merge remoto para tablas comerciales
- Archivos:
  - lib/repositories/sales_sync_repository.dart
  - lib/repositories/installments_sync_repository.dart
  - lib/repositories/payments_sync_repository.dart
  - lib/repositories/products_sync_repository.dart
- Cambio: en `_shouldKeepLocal(...)`, si local tiene `deleted_at` y remoto no viene eliminado, se conserva tombstone local.
- Resultado: evita revive de registros borrados localmente por payload remoto no-deleted.

### 5) Proteccion de `sync_queue` antes de purge en restore
- Archivo: lib/services/sync/emergency_cloud_restore_service.dart
- Cambio: backup JSON de filas de `sync_queue` por scopes objetivo antes de `DELETE FROM sync_queue`.
- Resultado: se evita perdida silenciosa de evidencia/operaciones pendientes en restore manual.

### 6) PWA: no solicitar soft-deleted products
- Archivo: sistema_solares_ui/lib/features/products/products_service.dart
- Cambio: `includeDeleted` forzado a `false` en request efectiva.
- Resultado: elimina via de lectura de eliminados desde servicio PWA.

### 7) PWA: force-delete deshabilitado en cliente
- Archivo: sistema_solares_ui/lib/features/sales/sales_service.dart
- Cambio: `forceDeleteFromCloud(...)` lanza `ApiException` 403.
- Resultado: el flujo cliente ya no ejecuta force-delete.

### 8) PWA API policy: removida allowlist de ruta peligrosa
- Archivo: sistema_solares_ui/lib/core/network/api_client.dart
- Cambio: se removio `/sales/force-delete/` de `_panelWriteAllowedPathPrefixes`.
- Resultado: se reduce superficie de escritura peligrosa del panel.

### 9) Orphan protection para vendedores con ventas activas
- Archivo: backend/src/modules/sellers/application/services/sellers.service.ts
- Cambio: bloqueo de borrado de seller si tiene ventas activas no canceladas.
- Resultado: evita huerfanos logicos seller->sales.

## Hard Deletes Encontrados

### Bloqueados o neutralizados
- `DELETE /sales/force-delete/:id` (backend): bloqueado con 403.
- `forceDeleteFromCloud(...)` (PWA service): bloqueado con error 403.

### Controlados con resguardo
- `DELETE FROM sync_queue ...` en restore manual:
  - Se mantiene (operacion de limpieza), pero ahora con backup previo obligatorio.

### No tocados en esta fase por alcance
- Tareas administrativas destructivas backend (por ejemplo scripts de reset comercial) permanecen como tooling de operacion.
- No se alteraron scripts de mantenimiento fuera del flujo online/offline productivo.

## Endpoints Peligrosos

### Estado final
- `/sales/force-delete/:id`: DESHABILITADO (403).
- `/payments/:id` delete: DESHABILITADO (403).
- `/reset-database` (panel allowlist): permanece permitido por naturaleza operacional; no fue parte del bloqueo funcional de esta fase.

## Tablas Protegidas
- sales
- installments
- payments
- products
- sync_queue (en contexto de restore manual)
- sellers (proteccion anti-huerfano por ventas activas)

## Orphan Protection
- Implementado guard en backend para sellers con ventas activas no canceladas.
- Se evita eliminar entidad padre mientras existan relaciones comerciales activas.

## PWA Validation

Validaciones realizadas:
- `products_service.dart` fuerza `includeDeleted=false`.
- `sales_service.dart` bloquea force-delete.
- `api_client.dart` sin allowlist de `/sales/force-delete/`.

Resultado:
- Endurecimiento consistente en capa de servicio/red PWA.
- Persisten referencias UI a toggles/llamadas historicas, pero la capa de servicio ya aplica bloqueo efectivo.

## Sync Queue Validation
- Restore manual ahora ejecuta backup JSON de filas de `sync_queue` antes de purge por scopes.
- Se registra `syncQueueBackupPath` en el reporte de ejecucion del restore.

Resultado:
- Se evita purge ciego sin rastro de recuperacion.

## Offline-First Validation

Controles verificados:
- Anti-revive en merges comerciales por tombstone local.
- Force-delete fuera de juego (backend + PWA).
- Pagos en modo append-only (backend + cliente local).

Resultado:
- Menor probabilidad de:
  - revive de registros eliminados,
  - hard-delete accidental en ventas/pagos,
  - corrupcion por pull remoto no alineado con tombstones locales.

## Validacion Tecnica Ejecutada

### Backend
- Estado: OK
- Evidencia: `npm run build` en backend completado correctamente.

### PWA
- Estado: OK (sin errores fatales)
- Evidencia: `flutter analyze` en PWA con warnings/info no bloqueantes.

### Windows / Sync / Restore tests
- Estado: BLOQUEADO
- Bloqueo tecnico observado en ejecuciones de esta fase:
  - crash de Flutter tool por native assets (`PathExistsException` con `build/native_assets/windows/sqlite3.dll`).
  - fallo de finalizacion/compilacion de `flutter test` con rutas temporales no encontradas (`PathNotFoundException` en `flutter_test_listener` y `output.dill`).
- Impacto: no se pudo cerrar validacion de pruebas automatizadas de sync/restore en este entorno durante esta corrida.

## Riesgos Pendientes

1. Validacion E2E de Sync/Restore en Windows pendiente por bloqueo de toolchain Flutter (sqlite3 native assets).
2. Endurecimiento adicional de scripts administrativos destructivos fuera del flujo productivo (si se decide incluir en fase posterior).
3. Barrido final de hard-delete residual en tooling/operacion para cierre total de superficie destructiva.

## Conclusion
FASE 3 (CONSISTENCY LOCKDOWN) queda implementada en codigo para las rutas criticas de consistencia offline-first: hard-delete comercial bloqueado en runtime, pagos en append-only, anti-revive por tombstones, y restore con resguardo de sync_queue.

Cierre funcional parcial:
- Lockdown de codigo: COMPLETADO.
- Validacion integral Windows/Sync/Restore: PENDIENTE por incidencia tecnica externa del toolchain.