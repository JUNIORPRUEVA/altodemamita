# AUDITORÍA FASE 1: MAPA COMPLETO DEL SISTEMA DE SINCRONIZACIÓN

## Resumen Ejecutivo

Esta es la **FASE 1** del análisis sistemático completo de la arquitectura offline-first. Se han identificado:
- ✅ 8 archivos críticos de sincronización
- ✅ 6 patrones de delete (hard, soft, tombstone, rawDelete)
- ✅ 4 estrategias de conflicto
- ✅ 2 canales de cloud pull (auth + data)
- ✅ 5 endpoints backend
- ✅ 13 flags de configuración

**ADVERTENCIA**: Fase de DESCUBRIMIENTO ÚNICAMENTE. No se ha implementado correctamente. Estos hallazgos REQUIEREN validación en Fases 2-13.

---

## 1. ARQUIECTURA GENERAL

### 1.1 Modelo Offline-First Declarado

```
PC LOCAL (Windows)
├─ SQLite local (offline-first source)
├─ Sync Queue (enqueue operations locally first)
└─ Upload-only to Cloud (read-only during bootstrap)

NUBE (PostgreSQL + NestJS API)
├─ Mirror/Backup
├─ PWA read-only access
└─ Manual emergency restore only (ALLOW_CLOUD_PULL=false)
```

### 1.2 Scopes de Sincronización
- **AUTH**: Usuarios, dispositivos, permisos (bootstrap solo)
- **COMMERCIAL**: Clientes, vendedores, solares, ventas, cuotas, pagos (offline-first)

### 1.3 Canales de Sincronización

| Canal | Dirección | Restricción | Archivo |
|-------|-----------|-------------|---------|
| Upload (Queue → Cloud) | PC → Cloud | Siempre | `sync_queue_service.dart` |
| Download (Cloud → Queue) | Cloud → PC | ALLOW_CLOUD_PULL flag | `sync_queue_service.dart` |
| Conflict Recovery | Cloud → Local | ALLOW_CLOUD_PULL flag | `sync_conflict_service.dart` |
| Emergency Restore | Cloud → Local | Manual admin only | `emergency_cloud_restore_service.dart` |
| Auth Bootstrap | Cloud → Local | Hybrid (allowed) | `auth_service.dart` |

---

## 2. ARCHIVOS CRÍTICOS IDENTIFICADOS

### 2.1 Flutter Client (lib/)

#### **sync_api_client.dart** (HTTP Transport)
```
Localización: lib/services/sync/sync_api_client.dart
Responsabilidad: HTTP client para endpoints /sync/upload y /sync/download
Métodos Clave:
  - uploadQueuedRecords(records, scope)
    → POST /api/sync/upload
    → Envía payload con sync_queue records
    → Retorna SyncUploadResponse o lanza SyncConflictException (409)
  
  - downloadChanges(lastSync, scope)
    → GET /api/sync/download
    → Recibe cambios remotos
    → Retorna SyncDownloadResponse

  - _buildHeaders()
    → Incluye Authorization bearer token
    → Incluye X-Device-Id
    → Incluye X-Is-Primary (primary device flag)

Flujo HTTP esperado:
  1. Enqueue locally
  2. Send to /api/sync/upload
  3. Server applies & returns conflicts (409) OR success (200)
  4. Client receives conflicts → log to conflict_logs
  5. User resolves conflict → retry or ignore

Manejo de Errores:
  - 409 Conflict → SyncConflictException
  - 401 Unauthorized → Handle auth failure
  - 500 Server error → Retry
```

#### **sync_queue_service.dart** (Orchestration Local)
```
Localización: lib/services/sync/sync_queue_service.dart
Responsabilidad: Orquestar cola local, retry, manejo de conflictos
Métodos Clave:
  - processQueue()
    → Lee sync_queue local
    → Itera por scope (AUTH, COMMERCIAL, etc.)
    → Para cada scope: llama uploadScopeRecords()
    → Si error → marca como failed, continúa siguiente scope
    → Si 409 → logUploadConflicts() + SKIPS auto-retry (Products)
    → Registra sync_events
  
  - enqueueUpsert(record, scope)
    → Inserta en sync_queue con sync_status='pending'
    → Crea sync_event local
    → Próximo processQueue() lo enviará
  
  - enqueueDelete(record, scope)
    → Inserta DELETE operation en sync_queue
    → Marca record como deleted_at=NOW, sync_status='pending_delete'
    → Backend verá isDeleteMutation=true
  
  - _markSourceRowsAsQueued(scope)
    → Actualiza tabla fuente (clientes, vendedores, etc.)
    → Marca sync_queue=true/pending
  
  - _markSourceRowsAsFailed(scope)
    → Recorre fallidos
    → Si COMERCIAL + es delete: marca con special conflict flag
    → Si es Products 409: NO auto-retry, espera resolución manual

Conflict Handling:
  - mergeRemoteRecords(serverPayload)
    → SOLO si servidor gana (server_won resolution)
    → Reemplaza local con remote
    → Marca como synced
  
  - detectHardDeleteError()
    → ADVERTENCIA: Busca "DELETE FROM solares WHERE deleted_at IS NOT NULL"
    → Si encuentra → error pattern, special handling

Hard Delete Patterns Encontrados:
  - rawDelete("DELETE FROM sync_queue WHERE scope IN (...)")
    → Lines 1353-1354, 1539-1540, 1697-1698
  - Busqueda: _hasLegacyHardDeleteError() (line 1620-1626)
    → Detecta "DELETE FROM solares WHERE deleted_at IS NOT NULL"
    → Comentario: "Legacy hard-delete error pattern"

Comportamiento Especial Products:
  - Products 409 conflicts aislados
  - Queue continúa procesando otros scopes
  - Products no auto-retry, quedan marcados como "pending_conflict"
```

#### **sync_conflict_service.dart** (Conflict Persistence & Resolution)
```
Localización: lib/services/sync/sync_conflict_service.dart
Responsabilidad: Persistir conflictos en conflict_logs, permitir resolución manual
Métodos Clave:
  - logUploadConflicts(scope, conflicts)
    → Recibe SyncConflictException (409 response)
    → Llama ensureConflictLogsSchema() antes de insert
    → Inserta en tabla conflict_logs local
    → Marca conflict_reason, server_version, local_version
  
  - listOpenConflicts()
    → Lee de conflict_logs WHERE resolved_at IS NULL
    → Retorna lista de SyncConflictRecord
  
  - resolveUsingServerVersion(conflictId)
    → Marca conflict como "server_won"
    → Llama mergeRemoteRecords() con servidor payload
    → Reemplaza local completamente
    → Actualiza resolved_at=NOW
  
  - retryKeepLocalOverwrite(conflictId)
    → Marca conflict como "retry"
    → Reintenta envío local (próximo processQueue)
  
  - ignoreLocalConflict(conflictId)
    → Marca conflict como "ignored"
    → Descarta cambio local
    → Mantiene versión servidor

Estrategia "server_won":
  - Línea 276: resolution='server_won'
  - Llamadas a mergeRemoteRecords([serverPayload])
  - Casos de uso:
    1. User explicitly chooses server version
    2. Automatic resolution for non-commercial scopes
    3. DANGER: Si COMMERCIAL scope + AUTO server_won → OFFLINE-FIRST VIOLATION

Schema Repair:
  - ensureConflictLogsSchema() llamado antes de TODAS operaciones DB
  - Usa PRAGMA table_info para verificar columnas
  - ALTER TABLE ADD COLUMN si falta conflict_reason, etc.
  - Idempotent, safe, no data loss
```

#### **emergency_cloud_restore_service.dart** (Manual Restore)
```
Localización: lib/services/sync/emergency_cloud_restore_service.dart
Responsabilidad: Restore manual desde cloud (admin only, emergency)
Métodos Clave:
  - preview()
    → Descarga cambios desde /api/sync/restore/preview
    → Retorna delta sin aplicar
  
  - execute()
    → Descarga completo desde /api/sync/restore/download
    → Llama _clearSyncQueueForRestoreScopes()
    → Aplica SyncService.applyRemoteScopeRecords()
    → Marca todo como synced
  
  - _clearSyncQueueForRestoreScopes()
    → rawDelete("DELETE FROM sync_queue WHERE scope IN (...)")
    → Line 259: HARD DELETE de queue ANTES de aplicar cloud
    → Descarta cambios locales pendientes
    → PELIGRO: Pérdida de datos si local tenía cambios no synced

Flujo de Riesgo:
  1. PC tiene VENTA nueva, pendiente de upload
  2. Admin llama emergency_cloud_restore
  3. DELETE FROM sync_queue limpia la venta
  4. Cloud data se aplica (sin la venta nueva)
  5. Venta se pierde

Control de Acceso:
  - Requiere usuario con permisos admin
  - Requiere confirmación manual UI
  - Logged para auditoría
```

#### **sync_service.dart** (Orquestación Principal)
```
Localización: lib/services/sync/sync_service.dart
Responsabilidad: Flujo principal, descargas, merge remoto
Métodos Clave:
  - downloadUpdates()
    → Obtiene lastSync timestamp local
    → Si ALLOW_CLOUD_PULL=false:
        ✓ Bloquea downloadChanges() para COMMERCIAL
        ✓ Permite para AUTH (bootstrap)
    → Si ALLOW_CLOUD_PULL=true:
        → Descarga cambios
        → Llamadas mergeRemoteRecords()
    → Log: "Descarga desde la nube deshabilitada (ALLOW_CLOUD_PULL=false)"
  
  - mergeRemoteRecords(remotePayload, scope)
    → Aplica registros remotos a tablas locales
    → Detecta soft-deletes (deleted_at != null)
    → Filtra is_active=false
    → Actualiza version, sync_status, etc.
    → RIESGO: Si scope=COMMERCIAL + auto-applied → server gana sin permission

  - applyRemoteScopeRecords(scope, records)
    → Inserta/actualiza en tabla local de scope
    → Reemplaza sync_id si falta
    → Marca sync_status='synced'
    → Usado por emergency_cloud_restore_service

Config Flags (líneas 1-50):
  - LOCAL_MASTER_MODE (backend only, no visible aquí)
  - ALLOW_CLOUD_PULL (visible: line 484)
    → Si false: bloquea mergeRemoteRecords() para COMMERCIAL
    → Si true: permite cloud pull (RIESGO)
```

#### **auth_service.dart** (Híbrido Local + Online)
```
Localización: lib/features/auth/data/auth_service.dart
Responsabilidad: Login híbrido, persistencia JWT, bootstrap
Métodos Clave:
  - login(email, password)
    → Intenta cloud login
    → Si falla → fallback a local JWT persistence
    → Crea token local para siguiente session
  
  - _tryCheckRemoteStatus()
    → Intenta conectar a BASE_URL (canonical)
    → Si falla → fallback a LEGACY_BASE_URL
    → Retorna unreachable si ambas fallan
    → Lines 1742-1746: URL fallback logic

URL Configuration:
  - BASE_URL: URL canónica (intended)
  - LEGACY_BASE_URL: URL fallback antiguo
  - Typo Risk: Buscar "backent" u otros typos en URLs
    → NOT FOUND en búsqueda actual
    → Pero riesgo presente si API_BASE_URL mal escrito

Bootstrap Flow:
  - New PC: Tries cloud first (ALLOW_CLOUD_PULL for auth=true)
  - Existing PC: Uses local JWT from memory
  - Fallback: If both fail → offline mode (limited functionality)
```

---

### 2.2 Backend NestJS (backend/src/)

#### **sync.service.ts** (Apply Logic)
```
Localización: backend/src/modules/sync/application/services/sync.service.ts
Responsabilidad: Recibir registros, aplicar a PostgreSQL, detectar conflictos
Métodos Clave:
  - createSyncUploadService()
    → Procesa POST /api/sync/upload
    → Extrae context (isPrimary, userId, deviceId)
    
  - applyUpsertRecords(context, records, scope)
    → Para cada record:
      1. Obtiene version previa del DB
      2. Detecta isDeleteMutation (líneas 585-610)
      3. Si DELETE + isPrimary + LOCAL_MASTER_MODE=true:
         → soft-delete directamente (bypass version check)
         → emite deleted event
         → Retorna success
      4. Si UPDATE + version conflict:
         → Retorna 409 Conflict
         → Incluye server version para cliente
      5. Si UPDATE + version OK:
         → Actualiza PostgreSQL
         → Retorna 200 success

  - mergeRemoteRecords([serverPayload])
    → Aplica bulk de registros server al estado local
    → SOLO llamado por conflict recovery o restore manual
    → RIESGO: Si llamado para COMMERCIAL auto → server wins

isDeleteMutation Detection (línea 585-610):
  - Busca: deletedAt field
  - Busca: deleted_at field
  - Busca: operation=delete
  - Busca: sync_status=pending_delete
  - Si encuentra CUALQUIERA → isDeleteMutation=true

LOCAL_MASTER_MODE Logic (línea 85):
  - isLocalMaster = context.isPrimary && process.env['LOCAL_MASTER_MODE'] === 'true'
  - Si LOCAL_MASTER_MODE=true:
    → PC Primary wins automáticamente en deletes
    → Server no revierte delete de primary PC
  - Si LOCAL_MASTER_MODE=false:
    → Server puede rechazar delete si versión conflict
    → Client recibe 409

Endpoints:
  - POST /api/sync/upload (SyncController.upload)
  - GET /api/sync/download (SyncController.download)
  - POST /api/sync/restore/preview (RestoreController.preview)
  - POST /api/sync/restore/download (RestoreController.download)
```

#### **sync.controller.ts** (HTTP Routes)
```
Localización: backend/src/modules/sync/infrastructure/controllers/sync.controller.ts
Responsabilidad: Routing HTTP, logging, permission checks
Métodos Clave:
  - @Post('/upload')
    → POST /api/sync/upload
    → Extrae Authorization header
    → Logs isPrimary, canWrite estados
    → Antes: Always logged "autorizado=no" (BUG FIXED)
    → Ahora: Logs real canWrite/isPrimary
  
  - @Get('/download')
    → GET /api/sync/download?lastSync=ISO
    → Retorna cambios desde timestamp
  
  - @Post('/restore/preview')
    → Previsualiza cloud restore sin aplicar
  
  - @Post('/restore/download')
    → Ejecuta cloud restore manual
    → Requiere admin permission
    → Emite audit log
```

#### **cloud-commercial-reset.ts** (DANGER TASK)
```
Localización: backend/src/tasks/cloud-commercial-reset.ts
Responsabilidad: Limpiar datos comerciales de cloud (TASK manual, MUY PELIGROSO)
Métodos Clave:
  - deleteCommercialTables(prisma)
    → HARD DELETE en orden:
      1. sync_queue
      2. sync_events
      3. sync_event_logs
      4. sync_conflicts
      5. sync_conflict_logs
      6. cuotas (installments)
      7. pagos (payments)
      8. ventas (sales)
      9. vendedores (sellers)
      10. clientes (clients)
      11. solares (properties)
    → Cada DELETE es permanente
    → No soft-delete, no recovery
    → Respaldo manual via pg_dump antes

Invocación:
  - npm run task:cloud-commercial-reset
  - Requiere DATABASE_URL valida
  - Genera backup timestamp en backups/
  - Outputs report a console + file

RIESGO:
  - No confirmación interactiva en algunas versiones
  - Si ejecutado accidentalmente → pérdida total comercial cloud
  - Necesita control más estricto
```

#### **cloud-audit.ts** (Verificación Estado)
```
Localización: backend/src/tasks/cloud-audit.ts
Responsabilidad: Auditar divergencias cloud vs local SQLite
Métodos Clave:
  - countCloudRecords()
    → SELECT COUNT(*) WHERE deleted_at IS NULL
    → Para: clientes, vendedores, solares, ventas, etc.
  
  - countLocalRecords()
    → Lee SQLite DB descargado
    → Same COUNT logic
    → Compara contra cloud
  
  - detectOrphanedRecords()
    → Ventas sin cliente (cliente deleted pero venta no)
    → Cuotas/pagos sin venta
    → Clientes/vendedores sin solares asociados
  
  - detectPossibleDuplicates()
    → Busca cedulas/IDs duplicados
    → Múltiples clientes con mismo documentId
    → Posible corruption
  
  - detectIntegrityIssues()
    → sync_status='pending' en cloud
      → Registros no syncados desde local
    → Versiones inconsistentes
    → Deleted_at timestamps en futuro

Salida:
  - JSON report a console
  - Saved a backups/audit_[timestamp].json
  - Usable para reconciliación manual
```

---

### 2.3 Archivos de Configuración

#### **app_flags.dart** (Build-time Configuration)
```
Localización: lib/core/config/app_flags.dart
Flags Compiladas en Build:
  - PRODUCTION_MODE (default: false)
    → `--dart-define=PRODUCTION_MODE=false`
    → Controls error reporting, logging verbosity
  
  - MANUAL_CLOUD_SYNC_ONLY (default: false)
    → `--dart-define=MANUAL_CLOUD_SYNC_ONLY=false`
    → Si true: disables automatic sync queue processing
    → Requires manual "Sync Now" button
  
  - ALLOW_CLOUD_PULL (default: FALSE)
    → `--dart-define=ALLOW_CLOUD_PULL=true`
    → Controla downloadUpdates() para COMMERCIAL
    → Si false: bloquea mergeRemoteRecords() para no-auth
    → CRÍTICO: Must stay FALSE para offline-first

Build Command Example:
  flutter build windows --dart-define=ALLOW_CLOUD_PULL=false
```

#### **database_schema.dart** (Schema Versioning)
```
Localización: lib/core/database/database_schema.dart
Responsabilidad: SQLite schema versioning, migrations, auto-repair
Current Version: databaseVersion = 25
Migrations: _migrateToVersion1() through _migrateToVersion25()
            → Each async, idempotent

Critical Auto-Repair (Line ~900):
  - ensureConflictLogsSchema(Database db)
    → Checks if conflict_logs table exists
    → If not: CREATE TABLE
    → If exists: PRAGMA table_info check for columns
    → If column missing: ALTER TABLE ADD COLUMN
    → IDEMPOTENT: Safe to call repeatedly
    → Called in:
      * app_database.dart onOpen()
      * sync_conflict_service.dart before DB operations
      * sync_queue_service.dart before conflict reads

Schema Columns (conflict_logs):
  - id (TEXT PRIMARY KEY)
  - scope (TEXT)
  - record_id (TEXT)
  - conflict_reason (TEXT)
  - server_version (INT)
  - local_version (INT)
  - resolution (TEXT: 'server_won'|'retry'|'ignored'|NULL)
  - resolved_at (TEXT ISO timestamp or NULL)
  - created_at (TEXT ISO timestamp)

Downgrade Handling:
  - onDowngrade throws error (no backwards compatibility)
  - Prevents opening newer DB with older app
```

#### **app_database.dart** (SQLite Opening)
```
Localización: lib/core/database/app_database.dart
Responsabilidad: Open SQLite, call migrations, seed defaults
onOpen Callback (Línea ~150):
  - Llama DatabaseSchema.ensureConflictLogsSchema(db)
    → Repairs conflict_logs if missing
  - Llama seedDefaults()
    → Inserta tablas por defecto
  - Llama _migrateLegacyDatabaseIfNeeded()
    → Maneja migration desde versiones muy viejas

Beneficio:
  - Old DBs sin conflict_logs auto-repaired
  - No need to delete/reset app
  - Transparent upgrade
  - Data preserved
```

---

## 3. PATRONES DE DELETE IDENTIFICADOS

### 3.1 Soft Delete (Intención: Tombstone)
```
Localización primaria: sync_queue_service.dart enqueueDelete()
Proceso:
  1. Local: UPDATE [table] SET deleted_at=NOW, sync_status='pending_delete'
  2. Queue: INSERT sync_queue(operation='delete', record_id=X, scope=Y, status='pending')
  3. Upload: POST /api/sync/upload con operation='delete'
  4. Backend: Detecta isDeleteMutation=true (línea 585-610 sync.service.ts)
  5. Backend: Si LOCAL_MASTER_MODE=true → soft-delete directo
  6. Cloud: UPDATE [table] SET deleted_at=NOW
  7. ACK: Marca sync_status='synced'

Ventaja: Reversible, auditable, puede filtrar con WHERE deleted_at IS NULL
Riesgo: Si PWA no filtra deleted_at → muestra datos eliminados
```

### 3.2 Hard Delete (Detectado: LEGACY PATTERN)
```
Patrón Encontrado:
  - _hasLegacyHardDeleteError() sync_queue_service.dart (line 1620-1626)
  - Busca: "DELETE FROM solares WHERE deleted_at IS NOT NULL"
  - Comentario: "Legacy hard-delete error pattern"
  
Locaciones de rawDelete():
  1. sync_queue_service.dart line 1353-1354
     → rawDelete("DELETE FROM sync_queue WHERE ...")
     → Durante conflict resolution
     
  2. sync_queue_service.dart line 1539-1540
     → rawDelete("DELETE FROM sync_queue WHERE ...")
     → Durante failed cleanup
     
  3. sync_queue_service.dart line 1697-1698
     → rawDelete("DELETE FROM sync_queue WHERE ...")
     → Cleanup routine
  
  4. emergency_cloud_restore_service.dart line 259
     → rawDelete("DELETE FROM sync_queue WHERE scope IN (...)")
     → BEFORE applying cloud restore
     → Descarta cambios locales pendientes

Riesgo CRÍTICO:
  - rawDelete() elimina permanentemente de SQLite
  - Si se ejecuta sobre tabla equivocada → datos perdidos
  - No recovery sin backup
  - Usado en emergency_cloud_restore → puede perder ventas nuevas locales

Patrón Seguro vs Inseguro:
  ✓ SEGURO: rawDelete FROM sync_queue (queue es temporal)
  ✗ INSEGURO: rawDelete FROM solares (datos comerciales)
  ✗ INSEGURO: rawDelete FROM ventas (datos financieros)
```

### 3.3 Tombstone Pattern (Sin Implementar Completamente)
```
Intención: Marcar delete localmente, enviar al server, server aplica soft-delete
Estado: PARCIAL - Soft-delete implementado, pero algunos canales aún usan hard-delete

Implementación Correcta:
  1. Local: deleted_at=NOW + sync_status='pending_delete' ✓
  2. Upload: Detecta pending_delete ✓
  3. Backend: Soft-delete en cloud ✓
  4. Download: Filtra deleted_at IS NULL ✓
  5. PWA: Filtra deleted_at IS NULL ✓

Gaps:
  - emergency_cloud_restore limpia sync_queue con rawDelete ✗
  - Legacy hard-delete error pattern aún detectado ✗
  - Posible hard-delete en old migration code ✗
```

### 3.4 Cloud-Commercial-Reset (Nuclear Option)
```
Localización: backend/src/tasks/cloud-commercial-reset.ts
Operación: TRUNCATE todas tablas comerciales + sync tables
Tablas: clientes, vendedores, solares, ventas, cuotas, pagos, sync_*
Permanencia: PERMANENTE - No recovery sin backup PostgreSQL
Invocación: npm run task:cloud-commercial-reset
Protecciones: Backup automático, pero confirmación insuficiente

Riesgo: Ejecutado accidentalmente → pérdida total cloud
Mitigación: Requiere confirmación CLI más estricta
```

---

## 4. ESTRATEGIAS DE CONFLICTO

### 4.1 Server Won (Conflicto)
```
Localización: sync_conflict_service.dart línea 276
Resolución: resolution='server_won'
Proceso:
  1. User observa conflicto (409 desde backend)
  2. Elige "Usar versión servidor"
  3. Llama resolveUsingServerVersion(conflictId)
  4. Interno: mergeRemoteRecords([serverPayload])
  5. Resultado: Local reemplazado por remote
  6. Marca resolved_at=NOW
  7. Siguiente sync confirma

RIESGO COMERCIAL:
  - Si applied automáticamente para COMMERCIAL → offline-first violation
  - Si applied without user consent → data loss
  - Debe requerir confirmación UI

Verificación: Buscar auto-apply server_won para COMMERCIAL
  → NOT FOUND en búsqueda actual (parece manual UI only)
  → Pero riesgo presente si código futuro auto-applies
```

### 4.2 Retry Local (Manual Retry)
```
Localización: sync_conflict_service.dart
Método: retryKeepLocalOverwrite(conflictId)
Proceso:
  1. Marca conflict como 'retry'
  2. Reintenta próximo processQueue()
  3. Si version update resolver → 200 OK
  4. Si versión remota también cambió → 409 again
  5. Loop until resolved or ignored

Típicamente para:
  - Conflictos de version de actualización
  - Cuando local es más reciente
  - User quiere intentar con versión local
```

### 4.3 Ignore Local (Descartar Local)
```
Localización: sync_conflict_service.dart
Método: ignoreLocalConflict(conflictId)
Proceso:
  1. Marca conflict como 'ignored'
  2. Descarta cambio local
  3. Mantiene versión servidor
  4. No reintenta

Caso de uso:
  - User reconoce que remote es correcto
  - Quiere descartar cambio local
  - Equivalente a "server won" but user-initiated
```

### 4.4 Conflict Isolation (Products Especial)
```
Localización: sync_queue_service.dart
Comportamiento: Products 409 conflicts NO auto-retry
Proceso:
  1. Upload products scope
  2. Backend returns 409 for some records
  3. Client marques como 'pending_conflict'
  4. Queue CONTINUES processing other scopes
  5. NOT blocked waiting for product retry
  6. User resuelve conflicts manualmente desde UI

Beneficio:
  - Evita retry loop infinito para products
  - Permite que otros scopes sincen normalmente
  - Requiere resolución manual pero visible

Riesgo:
  - Products quedan estancados si no resueltos
  - User puede no notar conflicto pendiente
  - Necesita UI clara de "pending conflicts"
```

---

## 5. CLOUD PULL CHANNELS

### 5.1 Auth Cloud Pull (ALLOWED)
```
Localización: auth_service.dart
Escenario: New PC, first login
Flujo:
  1. PC intenta login
  2. Si offline → falla
  3. Si online → conecta a cloud
  4. Cloud validates email/password
  5. Retorna JWT token
  6. App persiste JWT localmente
  7. Siguiente login usa local JWT

Flag: ALLOW_CLOUD_PULL=true PARA AUTH ONLY
  - Explícitamente permitido en código
  - No controlled por flag, es hardcoded

Riesgo:
  - Si auth cloud pull falla → app no inicia
  - Mitigation: Local JWT fallback después 1º login
```

### 5.2 Data Cloud Pull (BLOCKED)
```
Localización: sync_service.dart línea 484
Escenario: Sincronizar cambios data desde cloud
Flujo:
  1. downloadUpdates() llamado
  2. Chequea ALLOW_CLOUD_PULL flag
  3. Si FALSE → retorna sin descargar (BLOCKED)
  4. Si TRUE → descarga via mergeRemoteRecords()

Flag: ALLOW_CLOUD_PULL=false (DEFAULT)
  - Línea: `'Descarga desde la nube deshabilitada (ALLOW_CLOUD_PULL=false).'`
  - También en sync_queue_service.dart línea 2137
  - Bloquea conflict recovery si false

Offline-First Principle:
  - Data descargada de cloud VIOLA offline-first
  - PC LOCAL debe ser fuente única COMMERCIAL
  - Except emergency/manual restore
```

### 5.3 Emergency Restore (MANUAL)
```
Localización: emergency_cloud_restore_service.dart
Invocación: Manual desde admin UI, requires permission
Flujo:
  1. Admin UI llama preview()
  2. Descarga /api/sync/restore/preview
  3. User previsualiza cambios
  4. Si OK → llama execute()
  5. execute() descarga completo
  6. _clearSyncQueueForRestoreScopes() → rawDelete sync_queue
  7. applyRemoteScopeRecords() → merge cloud data
  8. Marca todo synced

PELIGRO:
  - Limpia sync_queue con hard delete
  - Descarta cambios locales pendientes
  - Si local tenía venta nueva → se pierde
  - Recuperable solo con local backup

Protecciones:
  - Requiere explicit user confirm en UI
  - Requiere admin permission
  - Logged para audit
  - Recomendación: Backup sync_queue antes execute
```

---

## 6. ENDPOINTS BACKEND

### 6.1 POST /api/sync/upload
```
Localización: backend/src/modules/sync/infrastructure/controllers/sync.controller.ts
Requisición:
  POST /api/sync/upload
  Headers:
    Authorization: Bearer [JWT]
    X-Device-Id: [deviceId]
    X-Is-Primary: [true|false]
  Body:
    {
      records: [
        { scope: 'COMMERCIAL', operation: 'upsert', data: {...}, version: 123 },
        { scope: 'COMMERCIAL', operation: 'delete', data: {...}, version: 123 }
      ]
    }

Procesamiento (sync.service.ts):
  1. Extrae context (isPrimary, userId, deviceId)
  2. Para cada record:
     - Si operation=delete + isPrimary + LOCAL_MASTER_MODE:
       → Soft-delete directo, bypass version check
     - Si operation=upsert + version conflict:
       → Retorna 409 con server version
     - Si operation=upsert + version OK:
       → Inserta/actualiza PostgreSQL
  3. Retorna SyncUploadResponse

Respuesta 200 OK:
  {
    uploaded: 15,
    conflicts: [],
    failed: 0
  }

Respuesta 409 Conflict:
  {
    uploaded: 10,
    conflicts: [
      { recordId: 'X', serverVersion: 5, clientVersion: 3, reason: 'version' }
    ],
    failed: 0
  }

Respuesta 401 Unauthorized:
  → Token inválido/expirado
  → Client intenta re-login
```

### 6.2 GET /api/sync/download?lastSync=ISO
```
Localización: sync.controller.ts
Requisición:
  GET /api/sync/download?lastSync=2025-01-01T00:00:00Z
  Headers:
    Authorization: Bearer [JWT]

Query Params:
  - lastSync: ISO timestamp, cambios desde ese time
  - scope: (opcional) filtrar por scope

Procesamiento:
  1. Backend busca SELECT * WHERE updated_at > lastSync AND deleted_at IS NULL
  2. Para cada scope separadamente
  3. Retorna registros nuevos/actualizados
  4. EXCLUYE deleted_at != NULL (soft-deletes)

Respuesta 200 OK:
  {
    records: [
      { scope: 'COMMERCIAL', id: 'X', data: {...}, version: 5, syncId: 'abc-123' },
      ...
    ],
    serverTime: ISO timestamp
  }

Client Action:
  - Si ALLOW_CLOUD_PULL=false → ignora respuesta
  - Si ALLOW_CLOUD_PULL=true → mergeRemoteRecords()
```

### 6.3 POST /api/sync/restore/preview
```
Localización: reset-database.controller.ts
Propósito: Previsualizar cloud restore SIN aplicar
Requisición:
  POST /api/sync/restore/preview
  Headers: Authorization

Respuesta 200:
  {
    changes: {
      COMMERCIAL: {
        clientes: { new: 5, updated: 3, deleted: 2 },
        vendedores: { new: 1, updated: 0, deleted: 0 },
        solares: { new: 10, updated: 5, deleted: 0 },
        ventas: { new: 20, updated: 10, deleted: 5 }
      }
    }
  }

Client:
  - Muestra preview en UI
  - User decide: "Aplicar" vs "Cancelar"
  - Si "Aplicar" → llama /api/sync/restore/download
```

### 6.4 POST /api/sync/restore/download
```
Localización: reset-database.controller.ts
Propósito: Ejecutar cloud restore MANUAL
Requisición:
  POST /api/sync/restore/download
  Headers: Authorization, require admin permission

Procesamiento:
  1. Backend extrae todos registros de cloud (deleted_at IS NULL)
  2. Client-side descarga en memory
  3. _clearSyncQueueForRestoreScopes() → rawDelete sync_queue
  4. applyRemoteScopeRecords() → INSERTA en local SQLite
  5. Marca todo synced
  6. Retorna success

PELIGRO:
  - Sync_queue limpiado → cambios locales descartados
  - Si local tenía nuevas transacciones → PERDIDAS

Respuesta 200 OK:
  {
    applied: {
      clientes: 50,
      vendedores: 15,
      solares: 200,
      ventas: 500
    },
    syncStatus: 'fully_synced'
  }
```

### 6.5 POST /api/sync/restore/convert
```
(Inferido de cloud-audit.ts)
Propósito: Convertir cloud data a SQLite format
Uso: Durante audit, compatible con local DB schema
Formato: JSON compatible sqflite
```

---

## 7. CONFIGURACIÓN DE ENTORNO

### 7.1 Backend Environment Variables
```
Archivo: backend/.env (not in repo)
Variables Críticas:
  - DATABASE_URL=postgresql://...
    → Conexión PostgreSQL cloud
  - LOCAL_MASTER_MODE=true (DEFAULT)
    → PC PRIMARY wins en conflictos delete
  - ALLOW_CLOUD_PULL=false (DEFAULT)
    → Bloquea mergeRemoteRecords para COMMERCIAL
  - JWT_SECRET=[secret]
    → Token signing
  - JWT_EXPIRATION=24h
    → Token lifetime

Deployment:
  - Development: LOCAL_MASTER_MODE=true, ALLOW_CLOUD_PULL=false (DEFAULT)
  - Production: Same (offline-first enforcement)
  - Testing: Can override for testing server_won behavior
```

### 7.2 Flutter Build Flags
```
Compilación:
  flutter build windows \
    --dart-define=ALLOW_CLOUD_PULL=false \
    --dart-define=PRODUCTION_MODE=false \
    --dart-define=MANUAL_CLOUD_SYNC_ONLY=false

Defaults:
  - ALLOW_CLOUD_PULL=false (safe)
  - PRODUCTION_MODE=false (dev logging)
  - MANUAL_CLOUD_SYNC_ONLY=false (auto queue processing)

Risk:
  - Si compilado con ALLOW_CLOUD_PULL=true por error
    → App descargará datos de cloud
    → Offline-first violated
  - Necesita control CI/CD para garantizar FLAGS
```

---

## 8. TABLA COMPARATIVA: RIESGOS IDENTIFICADOS

| # | Archivo | Riesgo | Severidad | Mitigation |
|---|---------|--------|-----------|-----------|
| 1 | sync_queue_service.dart | rawDelete() en sync_queue limpia queue | ALTO | OK si solo sync_queue, PELIGRO si extiende a datos |
| 2 | emergency_cloud_restore.dart | Limpia sync_queue antes de aplicar cloud | CRÍTICO | Puede perder ventas nuevas locales no syncadas |
| 3 | sync_conflict_service.dart | server_won automático para COMMERCIAL | ALTO | Actualmente parece manual, pero código permite auto |
| 4 | sync_service.dart | downloadUpdates() respeta ALLOW_CLOUD_PULL flag | BAJO | OK si flag correcto, ALTO si flag=true |
| 5 | cloud-commercial-reset.ts | Hard delete de TODAS tablas comerciales | CRÍTICO | Tarea peligrosa, requiere confirmación reforzada |
| 6 | _hasLegacyHardDeleteError() | Detecta patrón hard-delete antiguo aún presente | MEDIO | Indica legacy code aún en codebase |
| 7 | auth_service.dart | Cloud pull para auth bootstrap | BAJO | Explícitamente intencional, separado de data |
| 8 | conflict_logs schema | Missing columns can cause runtime error | MEDIO | Auto-repaired via ensureConflictLogsSchema() |
| 9 | sync_api_client.dart | 409 handling puede loopear si no resuelto | MEDIO | Aislado para products, otros scopes continúan |
| 10 | PWA (UI) | EXCLUDED from grep search, no control audit | ALTO | PWA may not filter deleted_at properly |

---

## 9. HALLAZGOS CRÍTICOS PARA FASE 2

### 9.1 Preguntas por Responder en Fase 2
```
Para CADA scope (AUTH, COMMERCIAL):
  1. ¿Dónde se crea local? ¿Es enqueueUpsert o directo en DB?
  2. ¿Dónde se edita local? ¿Mismo mecanismo que create?
  3. ¿Dónde se elimina local? ¿Soft-delete o hard-delete?
  4. ¿Qué sync_status usa? ¿pending, pending_delete, etc?
  5. ¿Crea evento sync_queue? ¿Para tracking?
  6. ¿Qué payload sube? ¿Full record o delta?
  7. ¿Backend recibe correctamente? ¿Context correcto?
  8. ¿Backend aplica correctamente? ¿Version check?
  9. ¿Existe hard delete visible? ¿Dónde?
  10. ¿Existe soft delete visible? ¿deleted_at IS NULL?
  11. ¿Puede recibir 409? ¿Sí, bajo qué condición?
  12. ¿Si recibe 409, qué pasa? ¿Retry auto o manual?
  13. ¿Puede server_won aplicar? ¿Auto o manual?
  14. ¿Puede cloud pull revivirlo? ¿Sí si ALLOW_CLOUD_PULL=true?
  15. ¿PWA filtra correctamente? ¿deleted_at en WHERE?
  16. ¿Puede quedar huérfano? ¿Foreign key constraints?
  (más preguntas...)
```

### 9.2 Archivos Pendientes de Investigación Profunda
```
FASE 2 Búsquedas:
  [ ] Todos repos de CREATE operación por scope
  [ ] Todos repos de UPDATE operación por scope
  [ ] Todos repos de DELETE operación por scope
  [ ] PWA filters en UI (excluded from search)
  [ ] app_flags.dart all flag usages
  [ ] Migrations v4-v25 para cambios schema
  [ ] Orphan record detection queries
  [ ] Foreign key constraints

FASE 3 Búsquedas:
  [ ] Todos rawDelete llamadas, contexto
  [ ] Todos deleteMany llamadas, contexto
  [ ] Todos DELETE FROM SQL, contexto
  [ ] Todos merge remote calls, contexto
  [ ] Todos conflict resolution calls, contexto
```

---

## 10. RESUMEN ARQUITECTURA FINAL

```
┌─────────────────────────────────────────────────────────────────┐
│ FLUTTER CLIENT (Windows)                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                 │
│  │ local_db.sqlite  │      │   auth_service   │                 │
│  │                  │      │   (JWT + URL     │                 │
│  │  • clientes      │      │    fallback)     │                 │
│  │  • vendedores    │      └──────────────────┘                 │
│  │  • solares       │              ↓                             │
│  │  • ventas        │      POST /login (online)                 │
│  │  • cuotas        │      GET /status (fallback)               │
│  │  • pagos         │      Local JWT persist                    │
│  │                  │                                             │
│  └──────────────────┘                                             │
│       ↓                                                            │
│  ┌──────────────────────────────────────────────────────┐        │
│  │ sync_queue_service (ORCHESTRATION)                   │        │
│  ├──────────────────────────────────────────────────────┤        │
│  │ processQueue():                                       │        │
│  │   FOR each scope:                                     │        │
│  │     uploadScopeRecords(scope)                         │        │
│  │       → POST /api/sync/upload                         │        │
│  │       ← 200 OK | 409 Conflict | 401 Unauthorized     │        │
│  │       If 409: logUploadConflicts()                    │        │
│  │       If 200: markAsSynced()                          │        │
│  │                                                        │        │
│  │ downloadUpdates() (IF ALLOW_CLOUD_PULL=false → skip) │        │
│  │   GET /api/sync/download                              │        │
│  │   mergeRemoteRecords(payload) (if allowed)            │        │
│  └──────────────────────────────────────────────────────┘        │
│       ↓                                                            │
│  ┌──────────────────────────────────────────────────────┐        │
│  │ sync_conflict_service (CONFLICT RESOLUTION)          │        │
│  ├──────────────────────────────────────────────────────┤        │
│  │ logUploadConflicts() → INSERT conflict_logs          │        │
│  │ listOpenConflicts() → Read conflict_logs WHERE ...   │        │
│  │ resolveUsingServerVersion() → server_won (DANGER)    │        │
│  │ retryKeepLocalOverwrite() → Retry local              │        │
│  │ ignoreLocalConflict() → Discard local                │        │
│  └──────────────────────────────────────────────────────┘        │
│       ↓                                                            │
│  ┌──────────────────────────────────────────────────────┐        │
│  │ emergency_cloud_restore_service (MANUAL ONLY)        │        │
│  ├──────────────────────────────────────────────────────┤        │
│  │ preview() → GET /api/sync/restore/preview            │        │
│  │ execute() → POST /api/sync/restore/download          │        │
│  │           → rawDelete sync_queue ⚠️ PELIGRO           │        │
│  │           → applyRemoteRecords() merge data          │        │
│  └──────────────────────────────────────────────────────┘        │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                            ↓↑ HTTP
                          
┌─────────────────────────────────────────────────────────────────┐
│ BACKEND (NestJS + PostgreSQL)                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  POST /api/sync/upload  ← syn_api_client.uploadQueuedRecords()  │
│  │                                                                │
│  └→ sync.service.applyUpsertRecords()                            │
│     │                                                             │
│     ├─ detectIsDeleteMutation(record)                            │
│     │  └─ If true + isPrimary + LOCAL_MASTER_MODE=true          │
│     │     → soft-delete direkt, skip version check               │
│     │     → emit deleted event                                   │
│     │                                                             │
│     ├─ If NOT delete mutation:                                   │
│     │  ├─ Check version conflict                                 │
│     │  ├─ If conflict → 409 response                             │
│     │  └─ If version OK → INSERT/UPDATE PostgreSQL              │
│     │                                                             │
│     └─ Retorna SyncUploadResponse                                │
│                                                                   │
│  GET /api/sync/download ← sync_service.downloadUpdates()         │
│  │                                                                │
│  └─ Query PostgreSQL WHERE deleted_at IS NULL                   │
│     └─ Retorna SyncDownloadResponse                              │
│                                                                   │
│  POST /api/sync/restore/preview (admin only)                     │
│  POST /api/sync/restore/download (admin only)                    │
│                                                                   │
│  ┌───────────────────────────────────────────┐                  │
│  │ cloud-commercial-reset.ts (DANGEROUS)     │                  │
│  │ Task: DELETE ALL commercial + sync tables │                  │
│  │ Invocation: npm run task:cloud-reset      │                  │
│  │ Recovery: Backup only                     │                  │
│  └───────────────────────────────────────────┘                  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. ESTADO DE IMPLEMENTACIÓN

### 11.1 COMPLETADO ✓
- Soft-delete basic pattern (deleted_at + sync_status=pending_delete)
- LOCAL_MASTER_MODE precedence for primary device deletes
- ALLOW_CLOUD_PULL flag blocking cloud pull for commercial
- Auto-repair conflict_logs schema on open

### 11.2 PARCIALMENTE COMPLETADO ⚠️
- Hard delete protection (rawDelete still used on sync_queue, but not on data)
- Conflict resolution (manual UI choice, but server_won code path exists)
- Auth bootstrap fallback (implemented but incomplete)
- Orphan detection (exists in cloud-audit task but not integrated runtime)

### 11.3 NO COMPLETADO ✗
- PWA soft-delete filtering (excluded from this audit)
- Device authorization enforcement (not visible in this search)
- Sync_id tracking across devices (partial)
- Financial reconciliation (only audit task exists)

---

## 12. PRÓXIMAS FASES (PENDIENTES)

```
FASE 2: Auditoría por Scope/Tabla
  - Para AUTH: ¿Cómo se sincroniza? ¿Puede offline? ¿Cómo decide quién gana?
  - Para COMMERCIAL: ¿Offline-first garantizado? ¿Soft-delete total?
  
FASE 3: Auditoría de DELETE
  - Mapeo completo de todos los hard/soft delete patterns
  - Clasificación: Safe vs Insecure
  - Recomendación: Refactor inseguros

FASE 4: Auditoría de Conflictos
  - Confirmar LOCAL_MASTER_MODE applies a TODOS comercial
  - Confirmar server_won NUNCA auto-applies comercial
  - Confirmar no "ALLOW_CLOUD_PULL=true" escapes

FASE 5: Auditoría de Cloud Pull
  - Verificar ALLOW_CLOUD_PULL=false bloquea mergeRemoteRecords()
  - Verificar bootstrap excepciones para AUTH only
  - Verificar emergency restore requires admin

FASES 6-13: Dispositivos, URLs, PWA, Migraciones, Deploy, Finanzas, E2E, Report
```

---

## 13. NOTAS IMPORTANTES

1. **ESTO ES DESCUBRIMIENTO, NO VERIFICACIÓN COMPLETA**
   - Búsquedas grep pueden haber omitido código dinámico
   - PWA excluida de auditoría (excluded by .gitignore)
   - Algunos archivos no leídos completamente

2. **RIESGOS CONOCIDOS PERO ACEPTADOS**
   - emergency_cloud_restore limpia sync_queue (intencional para restore limpio)
   - server_won estrategia existe (pero parece manual UI only)
   - cloud-commercial-reset es tarea peligrosa (pero manual invocation)

3. **MITIGACIONES EN LUGAR**
   - ensureConflictLogsSchema() auto-repair en open
   - LOCAL_MASTER_MODE enforced backend
   - ALLOW_CLOUD_PULL default=false
   - Soft-delete tombstones implementados

4. **PRÓXIMO PASO: FASE 2 SCOPE AUDIT**
   - Comenzar mapping: Para CADA scope = 24 preguntas
   - AUTH scope primero (más simple)
   - COMMERCIAL scope segundo (crítico, offline-first)
   - Luego CLIENTES, VENDEDORES, SOLARES, VENTAS, etc.
