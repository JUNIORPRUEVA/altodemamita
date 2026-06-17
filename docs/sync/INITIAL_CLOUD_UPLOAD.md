# Sincronización Inicial Completa Local -> Nube

## Resumen

Implementación de la sincronización inicial completa (bootstrap) que sube todos los datos
locales existentes en SQLite al backend cuando un cliente actualiza la app por primera vez
después de tener datos históricos que nunca fueron sincronizados.

## Archivos Modificados

### Nuevos archivos:

1. **`app_local/lib/services/sync/initial_cloud_upload_service.dart`**
   - Servicio principal que orquesta la sincronización inicial.
   - Lee todos los datos locales, genera sync_ids estables si faltan,
     sube por lotes respetando dependencias, y marca completado.

### Archivos modificados:

2. **`app_local/lib/services/sync/sync_manager.dart`**
   - Se agregó `InitialCloudUploadService` como dependencia opcional.
   - Se agregó el método `runInitialCloudUpload()` que es llamado desde
     `_onBackendReady()` después de que el backend está configurado.
   - Se agregó el método `resetInitialCloudUploadFlag()` para DEV/testing.

3. **`app_local/lib/services/sync/sync_config_repository.dart`**
   - Se agregaron métodos:
     - `isLocalUploadBootstrapCompleted()` - verifica bandera
     - `markLocalUploadBootstrapCompleted()` - marca completado
     - `resetLocalUploadBootstrapCompleted()` - resetea para DEV
   - La bandera se guarda en SharedPreferences con clave:
     `sync.local_upload_bootstrap_completed`
   - También se guarda:
     - `sync.local_upload_bootstrap_completed_at` (fecha ISO)
     - `sync.local_upload_bootstrap_backend_url` (URL usada)
     - `sync.local_upload_bootstrap_version` (versión opcional)

4. **`app_local/lib/app/navigation/app_shell.dart`**
   - Se agregó `InitialCloudUploadService` como dependencia.
   - Se pasa al `SyncManager` en la construcción.

## Dónde se guarda la bandera

La bandera `initial_cloud_upload_completed` se guarda en **SharedPreferences**
con la clave `sync.local_upload_bootstrap_completed`.

Adicionalmente se guardan metadatos:
- `sync.local_upload_bootstrap_completed_at` - timestamp ISO
- `sync.local_upload_bootstrap_backend_url` - URL del backend usado
- `sync.local_upload_bootstrap_version` - versión opcional

## Cómo resetear en DEV

### Opción 1: Botón en UI (recomendado)
Ir a Configuración > Sincronización > "Resetear sincronización inicial"
(Este botón llama a `SyncManager.resetInitialCloudUploadFlag()`)

### Opción 2: SharedPreferences directamente
```bash
# En Windows, las SharedPreferences están en:
# %APPDATA%/com.example.sistema_solares/flutter_shared_preferences.json
# Editar el archivo y eliminar la clave:
# "sync.local_upload_bootstrap_completed"
```

### Opción 3: Código
```dart
final configRepo = SyncConfigRepository();
await configRepo.resetLocalUploadBootstrapCompleted();
```

## Flujo de ejecución

```
AppShell.init()
  └─> _initAsync()
       └─> _initSync()
            └─> _configureSync()
                 └─> _onBackendReady()
                      ├─> [InitialCloudUpload] starting
                      ├─> Verificar backend online
                      ├─> Verificar bandera completada
                      ├─> Leer datos locales
                      ├─> Subir por lotes (200 registros/scope)
                      │    ├─> clients
                      │    ├─> sellers
                      │    ├─> products
                      │    ├─> sales
                      │    ├─> installments
                      │    └─> payments
                      ├─> Marcar completado
                      └─> [InitialCloudUpload] completed
```

## Logs esperados

```
[InitialCloudUpload] starting
[InitialCloudUpload] backend online
[InitialCloudUpload] clients count=5
[InitialCloudUpload] sellers count=3
[InitialCloudUpload] lots count=10
[InitialCloudUpload] sales count=8
[InitialCloudUpload] installments count=96
[InitialCloudUpload] payments count=12
[InitialCloudUpload] uploading scope=clients count=5 batch=1/1
[InitialCloudUpload] upload success scope=clients applied=5 rejected=0
[InitialCloudUpload] uploading scope=sellers count=3 batch=1/1
[InitialCloudUpload] upload success scope=sellers applied=3 rejected=0
[InitialCloudUpload] uploading scope=products count=10 batch=1/1
[InitialCloudUpload] upload success scope=products applied=10 rejected=0
[InitialCloudUpload] uploading scope=sales count=8 batch=1/1
[InitialCloudUpload] upload success scope=sales applied=8 rejected=0
[InitialCloudUpload] uploading scope=installments count=96 batch=1/1
[InitialCloudUpload] upload success scope=installments applied=96 rejected=0
[InitialCloudUpload] uploading scope=payments count=12 batch=1/1
[InitialCloudUpload] upload success scope=payments applied=12 rejected=0
[InitialCloudUpload] completed
```

## Plan de Pruebas

### Prerrequisitos
1. Backend local corriendo en http://localhost:3000
2. PostgreSQL con migraciones aplicadas
3. App local con datos de prueba en SQLite

### Prueba A: Preparar datos locales
```bash
cd app_local
flutter run -d windows --dart-define=SYNC_API_BASE_URL=http://localhost:3000
```
Crear manualmente:
- 1 cliente
- 1 vendedor
- 1 solar
- 1 venta
- Generar cuotas
- 1 pago

### Prueba B: Forzar primera vez
```dart
// En consola de depuración o script:
final configRepo = SyncConfigRepository();
await configRepo.resetLocalUploadBootstrapCompleted();
```

### Prueba C: Encender backend
```bash
cd backend
npm run dev
# Verificar:
curl http://localhost:3000/api/system/status  # debe responder 200
curl http://localhost:3000/api/system/config   # debe responder 200
```

### Prueba D: Abrir app local
```bash
cd app_local
flutter run -d windows --dart-define=SYNC_API_BASE_URL=http://localhost:3000
```

### Prueba E: Confirmar logs
Buscar en la consola:
```
[InitialCloudUpload] starting
[InitialCloudUpload] backend online
[InitialCloudUpload] clients count=...
[InitialCloudUpload] sellers count=...
[InitialCloudUpload] lots count=...
[InitialCloudUpload] sales count=...
[InitialCloudUpload] installments count=...
[InitialCloudUpload] payments count=...
[InitialCloudUpload] uploading scope=clients count=...
[InitialCloudUpload] upload success scope=clients applied=... rejected=...
...
[InitialCloudUpload] completed
```

### Prueba F: Confirmar en PostgreSQL
```sql
SELECT 
  'Client' AS tabla,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL) AS activos,
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL) AS eliminados
FROM "Client"
UNION ALL
SELECT 'Seller', COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Seller"
UNION ALL
SELECT 'Lot', COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Lot"
UNION ALL
SELECT 'Sale', COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Sale"
UNION ALL
SELECT 'Installment', COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Installment"
UNION ALL
SELECT 'Payment', COUNT(*),
  COUNT(*) FILTER (WHERE "deletedAt" IS NULL),
  COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)
FROM "Payment";
```

### Prueba G: Reiniciar app
Cerrar y abrir la app de nuevo.
Confirmar log:
```
[InitialCloudUpload] already completed, skipping
```

### Prueba H: Idempotencia
1. Resetear bandera: `configRepo.resetLocalUploadBootstrapCompleted()`
2. Abrir app de nuevo
3. Confirmar que NO duplica registros en PostgreSQL
4. Los conteos deben ser los mismos que en Prueba F

### Prueba I: Offline
1. Apagar backend
2. Abrir app
3. Confirmar log: `[InitialCloudUpload] backend offline, pending retry`
4. Confirmar que NO se marca completed
5. Encender backend
6. Reabrir app
7. Confirmar que reintenta y completa

## Validaciones finales

```bash
cd app_local
flutter analyze
# No debe haber errores en lib/services/sync/

cd ../backend
npm run build
npx prisma generate
npx prisma migrate deploy

cd ../app_owner
flutter analyze
```
