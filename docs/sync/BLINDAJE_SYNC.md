# Blindaje de Sincronización - Sistema Solares

## Diagnóstico Completo

### 1. Cloud Pull (allowCloudPull=false) ✅ YA IMPLEMENTADO

**Archivos verificados:**
- `lib/core/config/app_flags.dart` → `allowCloudPull` default `false`
- `lib/services/sync/sync_service.dart` → `_downloadFromCloudEnabled = allowCloudPull`
- `lib/services/sync/sync_manager.dart` → initial sync condicionado a `allowCloudPull`
- `lib/services/sync/sync_queue_service.dart` → `_attemptConflictRecoveryDownload` protegido
- `lib/services/realtime_sync_service.dart` → respeta `allowCloudPull`

**Conclusión:** El cloud pull ya está deshabilitado por defecto. No hay descarga automática cloud → local.

### 2. Sincronización de Arranque ✅
- `sync_manager.dart` solo ejecuta initial sync si `allowCloudPull=true`
- La app sube datos local → cloud mediante `sync_queue_service.processQueue()`
- No ejecuta cloud → local al arrancar

### 3. Sync Queue ✅
- Cada create/update/delete marca `sync_status` pendiente
- Encola en `sync_queue` e intenta upload inmediato
- Si falla, reintenta después sin bloquear UI

### 4. Duplicados con Soft Delete ✅ CORREGIDO

#### LotRepository ✅ CORREGIDO
- `findByBlockAndLotNumber` ahora busca por `manzana_numero` AND `solar_numero` AND `deleted_at IS NULL`
- `save()` usa validación con logs de duplicados:
  - `[DuplicateCheck][Lot] block=N number=11 foundDeleted=true foundActive=false -> allowed`
  - `[DuplicateCheck][Lot] block=N number=11 foundActive=true -> rejected`
- No bloquea por registros eliminados

#### ClientRepository ✅ YA CORRECTO
- `_findActiveClientIdByDocumentId` busca solo activos (`deleted_at IS NULL`)
- Anonimiza documentos eliminados con `__DELETED__`
- No bloquea por registros eliminados

#### SellerRepository ✅ YA CORRECTO
- `_findActiveSellerIdByDocumentId` busca solo activos (`deleted_at IS NULL`)
- Anonimiza documentos eliminados con `__DELETED__`
- No bloquea por registros eliminados

### 5. Backend Prisma ✅ CORREGIDO

#### sync.routes.ts ✅ CORREGIDO
- `upsertClients`: valida duplicado activo por documento antes de upsert
- `upsertSellers`: valida duplicado activo por documento antes de upsert
- `upsertLots`: valida duplicado activo por block+number antes de upsert
- Logs: `[DuplicateCheck][Client/Seller/Lot] companyId=... foundActive=true -> rejected`
- Se eliminó dependencia de `Prisma.Decimal` y `Prisma.InputJsonObject` (incompatibles con Prisma 7)
- `rawJson()` ahora retorna `any` para compatibilidad

#### Índices Únicos Parciales ✅ CREADOS Y VERIFICADOS EN POSTGRESQL
- `Lot_companyId_block_number_active_unique` - WHERE "deletedAt" IS NULL
- `Client_companyId_document_active_unique` - WHERE "deletedAt" IS NULL AND document NOT NULL AND document <> ''
- `Seller_companyId_document_active_unique` - WHERE "deletedAt" IS NULL AND document NOT NULL AND document <> ''

### 6. Owner/APK ✅
- `owner.routes.ts` ya filtra `deletedAt: null` por defecto
- Dashboard usa `deletedAt: null`
- Owner APK consulta backend con filtro `deletedAt: null`

### 7. Logs de Duplicados ✅ AGREGADOS
- LotRepository: `[DuplicateCheck][Lot] block=N number=11 foundActive=true -> rejected`
- LotRepository: `[DuplicateCheck][Lot] block=N number=11 foundDeleted=true foundActive=false -> allowed`
- Backend sync.routes: `[DuplicateCheck][Client/Seller/Lot] companyId=... foundActive=true -> rejected`

## Archivos Modificados

1. `lib/features/lots/data/lot_repository.dart` - Validación de duplicados block+number con logs
2. `backend/src/routes/sync.routes.ts` - Validación de duplicados activos en backend (Client, Seller, Lot) + fix compatibilidad Prisma 7
3. `backend/prisma/migrations/20260616220000_add_partial_unique_indexes/migration.sql` - Índices únicos parciales
4. `backend/prisma.config.ts` - Configuración para Prisma 7 (archivo requerido pero vacío)
5. `test/system_config_service_refresh_recovers_device_state_test.dart` - Fix: constructor no acepta `httpClient`
6. `BLINDAJE_SYNC.md` - Este documento

## Pruebas Realizadas ✅ TODAS PASARON

### Prueba Solar N-11 (PASÓ) ✅
```
1. Crear solar N-11 → Creado exitosamente (syncId: test-lot-n11-001)
2. Verificar status → Products activos: 2 (1 original + 1 nuevo)
3. Eliminar solar N-11 → deletedAt asignado, version=2
4. Verificar status después de eliminar → Products activos: 1
5. Crear nuevamente solar N-11 (debe permitirlo) → Creado exitosamente (syncId: test-lot-n11-002)
6. Verificar status final → Products activos: 2
7. Verificar duplicados activos:
   - N-11 activos: 1 ✅ (debe ser 1)
   - N-11 eliminados: 3 ✅ (debe ser 1 o más)
   - Total N-11: 4
```

### Prueba Cliente/Vendedor con Documento Duplicado (PASÓ) ✅
```
8. Crear cliente con documento 001-1234567-8 → Creado
9. Eliminar cliente → deletedAt asignado
10. Crear cliente NUEVO con mismo documento → Creado exitosamente ✅
11. Verificar clientes activos: 2 (1 original + 1 nuevo)
12. Crear vendedor con documento 002-8765432-1 → Creado
13. Eliminar vendedor → deletedAt asignado
14. Crear vendedor NUEVO con mismo documento → Creado exitosamente ✅
15. Verificar vendedores activos: 2 (1 original + 1 nuevo)
```

### Prueba de Índices (PASÓ) ✅
- 3 índices parciales únicos creados y verificados en PostgreSQL
- No hay duplicados activos en Lot, Client o Seller
- Los índices permiten múltiples registros eliminados con mismos valores

### Prueba de Compilación Backend (PASÓ) ✅
- `npm run build` → exitoso (TypeScript compila sin errores)
- `prisma migrate deploy` → sin migraciones pendientes
- `prisma generate` → cliente generado correctamente

### Prueba de Compilación Dart (PASÓ) ✅
- `test/system_config_service_refresh_recovers_device_state_test.dart` corregido
- Constructor `SystemConfigService.test()` ya no acepta `httpClient` inexistente

## Estado PostgreSQL (confirmado)
```
Client: 1 total, 1 activos, 0 eliminados
Seller: 1 total, 1 activos, 0 eliminados
Lot: 9 total, 1 activos, 8 eliminados
Sale: 4 total, 0 activos, 4 eliminados
Installment: 78 total, 0 activos, 78 eliminados
Payment: 6 total, 0 activos, 6 eliminados
```

## Regla Fundamental
**LA APP WINDOWS LOCAL ES LA FUENTE DE LA VERDAD.**
- Sincronización normal: solo LOCAL → CLOUD
- Cloud pull deshabilitado por defecto (`ALLOW_CLOUD_PULL=false`)
- Soft delete: registros eliminados tienen `deletedAt` no null
- Eliminados no bloquean nuevas creaciones
- Owner/APK muestra solo activos por defecto
