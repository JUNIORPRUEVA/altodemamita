# Auditoría completa — Backup Local + Nube (Sistema Solares)

Fecha: 2026-04-23

## 0) Alcance y contexto
Este repo contiene **dos sistemas** relacionados con “backup/restore”:

1) **Backup profesional (nuevo, modular)** — Local + Nube (ZIP + upload)
- En Flutter: `lib/services/professional_backup/*`
- UI de configuración/acción: `lib/features/backup/presentation/professional_backup_section.dart`
- Backend NestJS: endpoints `system/backup/*` (subida/listado/borrado) y almacenamiento en filesystem.

2) **Backup/restore legacy (existente)** — principal foco en **disco externo** + restauración segura
- En Flutter: `lib/features/backup/*`
- Incluye restore con `pre_restore`, historial, detección de discos, retención, y soporte a la pantalla de recuperación de arranque.

> Nota: La “Nube” aplica al sistema **profesional**. El legacy no implementa nube.

---

## 1) Backup profesional — Local

### 1.1 Ubicación en disco (Windows)
La base de paths se define en `AppPaths`:
- Soporte principal (por usuario): `LOCALAPPDATA\SistemaSolares\...`
  - Ver: `lib/core/resilience/app_paths.dart`

Rutas relevantes:
- Directorio backups: `<supportDirectory>/backups`
- Backups locales profesionales: `<supportDirectory>/backups/local/`
  - Ver: `LocalBackupAgent.localBackupsDirectory` en `lib/services/professional_backup/local_backup_agent.dart`

### 1.2 Nombre de archivo
- Patrón: `backup_local_YYYY-MM-DD_HH-mm.db`
- Precisión: minuto (`HH-mm`) para evitar spam por eventos cercanos.

### 1.3 Disparadores (triggers)
- Manual (desde UI): botón en `ProfessionalBackupSection`.
- Tras sync exitoso: `BackupService.onSyncFinished(SyncReport report)`.
  - Hook registrado en `lib/app/navigation/app_shell.dart` y `lib/features/auth/data/auth_service.dart`.
- Cierre de app (best-effort): `ProfessionalBackupLifecycleObserver` ejecuta `createLocalBackup` cuando el estado pasa a `detached`.
  - Ver: `lib/services/professional_backup/professional_backup_lifecycle_observer.dart`.

### 1.4 Consistencia e integridad

**Consistencia del snapshot**
- Antes de copiar:
  - Se intenta `PRAGMA wal_checkpoint(TRUNCATE)`.
  - Se cierra la DB brevemente (`AppDatabase.close()`), copia, y re-inicializa al final.

**Validación fuerte (anti-backup corrupto)**
- `BackupValidatorAgent.validateSQLiteDbFile()`:
  1) Verifica cabecera SQLite (`"SQLite format 3"`).
  2) Abre el archivo read-only con `sqflite_common_ffi`.
  3) Ejecuta `PRAGMA quick_check(1)` y exige resultado `ok`.
  - Ver: `lib/services/professional_backup/backup_validator_agent.dart`

Esto reduce el riesgo de retener copias “aparentemente correctas” que luego fallan.

### 1.5 Retención local (15)
- Se aplica después de crear backup.
- Política: mantener **los últimos 15** backups **válidos**.
- Auto-fix: elimina backups vacíos/corruptos antes de aplicar la retención.
  - Ver: `lib/services/professional_backup/backup_cleaner_agent.dart`

### 1.6 Duplicados por minuto
- Si ya existe el archivo del mismo minuto y **valida**, se reutiliza (no se recrea).
  - Ver: `lib/services/professional_backup/local_backup_agent.dart`

### 1.7 Impacto en UX / rendimiento
- El backup **cierra la DB** unos instantes para copiar (necesario para consistencia).
- Se serializa el trabajo con una cola interna (`_enqueue`) para evitar concurrencia peligrosa.
  - Ver: `lib/services/professional_backup/backup_service.dart`
- En `detached` se llama `unawaited(...)` (best-effort). No debe bloquear el cierre.

---

## 2) Backup profesional — Nube

### 2.1 Configuración
Se guarda en JSON para evitar migraciones:
- Archivo: `<supportDirectory>/config/professional_backup_settings.json`
  - Ver: `lib/services/professional_backup/professional_backup_settings_repository.dart`

Defaults:
- `localBackupEnabled: true`
- `cloudBackupEnabled: true` (la nube viene **encendida** por defecto)
- Hora: 02:00
  - Ver: `lib/services/professional_backup/professional_backup_settings.dart`

### 2.2 Scheduler diario (2:00 AM por defecto)
- Implementación: `Timer` de un solo disparo, que al ejecutar reprograma el siguiente.
- Robustez: `try/catch` interno para que un fallo de backup nunca crashee la app.
  - Ver: `lib/services/professional_backup/backup_scheduler_agent.dart`

Comportamiento “catch-up”:
- En `BackupService.initialize()` se intenta `runCloudBackupIfDue()` por si la app arrancó después de la hora programada.

### 2.3 Frecuencia (una vez por día)
- `runCloudBackupIfDue()` compara `lastCloudBackupDate` con la fecha calendario (`YYYY-MM-DD`).
- El job programado **respeta** esta regla (no fuerza bypass).
  - Ver: `lib/services/professional_backup/backup_service.dart`

### 2.4 Snapshot, ZIP e integridad
Flujo:
1) Copia un snapshot DB a temp: `<supportDirectory>/temp/cloud_snapshot_YYYY-MM-DD.db`.
2) Valida el `.db` (cabecera + `quick_check`).
3) Empaqueta ZIP con `archive`.
4) Valida ZIP (firma `PK...`).
5) Sube el ZIP por multipart.
- Ver: `lib/services/professional_backup/cloud_backup_agent.dart`

### 2.5 Upload HTTP
- Endpoint: `POST {baseUrl}/system/backup/upload`
- Auth: `Authorization: Bearer <jwtToken>` (desde settings de sync)
- Cliente: `dart:io` `HttpClient` (sin dependencias extras)
- Timeout conexión: 20s

### 2.6 Reintentos (máx 2)
- Política de retry controlada:
  - Reintenta (hasta 2) en `SocketException`, `TimeoutException`, `HttpException`.
  - Reintenta también si el backend responde 408/429/5xx.
  - No reintenta en errores no transitorios.
  - Backoff: 750ms * intento.
- Ver: `lib/services/professional_backup/backup_service.dart`

### 2.7 Resultado y persistencia “último día ok”
- Si sube con 2xx, guarda `lastCloudBackupDate` en settings JSON.

### 2.8 Seguridad / exposición de rutas
- En UI, mensajes muestran solo el **nombre de archivo** (no path completo).
- Errores de “DB no encontrada” no filtran rutas absolutas.

---

## 3) Backend (NestJS) — Nube

### 3.1 Endpoints
Base: `/system/backup`
- `POST /upload` — recibe multipart `file`
- `GET /list` — lista archivos
- `DELETE /:id` — borra por nombre

Implementación:
- Controller: `backend/src/modules/system-backup/infrastructure/controllers/system-backup.controller.ts`
- Service: `backend/src/modules/system-backup/application/services/system-backup.service.ts`

### 3.2 Autorización
- Protegido por permisos: `RequirePermissions(PERMISSIONS.syncManage)`
- `assertOperationalAccess(...)` (control de acceso operacional)

### 3.3 Almacenamiento (filesystem)
- Directorio configurable:
  - `CLOUD_BACKUPS_DIR` o `SYSTEM_BACKUP_STORAGE_DIR`
- Default actual: `os.tmpdir()/cloud_backups`
  - Ver: `backend/src/modules/system-backup/system-backup.paths.ts`

**Riesgo importante (durabilidad)**
- En contenedores, `/tmp` suele ser **efímero**. Si no se configura el env var con un volumen persistente, los backups pueden perderse tras reinicios.

Recomendación operativa:
- En producción, configurar `CLOUD_BACKUPS_DIR=/cloud_backups` y montar un volumen persistente a esa ruta.

### 3.4 Retención (4 días)
- Política: elimina archivos con `mtime` menor al cutoff de 4 días.
- Se ejecuta:
  - al iniciar el módulo (`onModuleInit`) +
  - cada 6 horas (timer) +
  - adicionalmente en `listBackups()`.

Esto evita acumulación incluso si no hay tráfico.

### 3.5 Sanitización y path traversal
- Upload: el nombre se sanea (caracteres inválidos → `_`).
- Delete: valida `path.basename(id) === id` antes de `unlink`.

### 3.6 Límite de tamaño
- Multer `fileSize`: 1GB.

---

## 4) Sistema legacy — Backup local a disco externo + restore

### 4.1 Propósito
- Backups orientados a **disaster recovery** (disco externo / unidad secundaria).
- Restore con medidas de seguridad (`pre_restore`).

### 4.2 Integración con lifecycle
- `BackupLifecycleObserver` crea backups automáticos en:
  - “startup” (al `resumed` la primera vez)
  - “shutdown” (al `paused/hidden/detached`)
- Ver: `lib/features/backup/presentation/backup_lifecycle_observer.dart`

### 4.3 Integración con recuperación de arranque
- `StartupRecoveryService` repara config/historial, valida DB, y ofrece restauración como último recurso.
- Ver: `lib/core/resilience/startup_recovery_service.dart`

### 4.4 Integridad
- `createBackup` valida tamaño copiado y marca `.verified`.
- `restoreFromBackup` crea `pre_restore` si hay estado actual utilizable, borra sidecars WAL/SHM/JOURNAL, restaura, y corre `PRAGMA integrity_check`.
- Ver: `lib/features/backup/services/backup_service.dart`

### 4.5 Retención legacy
- Conserva hasta `maxBackupRetention` (configurable) y limpia entradas fallidas.

---

## 5) Pruebas (evidencia)
Se ejecutaron pruebas enfocadas (Windows) y pasaron:
- `test/backup_controller_test.dart`
- `test/local_persistence_production_test.dart`
- `test/read_only_configuration_hardening_test.dart`
- `test/resilience_recovery_test.dart`

> Nota Windows: a veces Flutter puede crashear con native assets (`sqlite3.dll` errno=183) si quedan procesos `dart/flutter_tester` vivos o el archivo queda bloqueado. En ese caso, detener procesos y borrar `build/native_assets` suele resolver.

---

## 6) Hallazgos clave y recomendaciones

### ✅ Lo que está “bien resuelto”
- Backups profesionales locales con integridad fuerte (`quick_check`).
- Retención local 15 con auto-limpieza de corruptos/vacíos.
- Scheduler nube robusto (no crashea y respeta “una vez por día”).
- Reintentos cloud controlados (máx 2) y sólo para fallos transitorios.
- Backend con retención automática aun sin tráfico.
- Sanitización básica y protección de path traversal en delete.

### ⚠️ Riesgos / pendientes recomendados
1) **Durabilidad del storage cloud en backend**
   - Si no se configura `CLOUD_BACKUPS_DIR`, se usa `/tmp/...`.
   - Recomendado: volumen persistente (ej. `/cloud_backups`).

2) **Cifrado**
   - Los backups (local y cloud) no están cifrados en reposo. Si se requiere compliance, agregar cifrado (y gestión de claves) sería el siguiente paso.

3) **Aislamiento multi-tenant (si aplica)**
   - El backend guarda backups en una carpeta común. Si en el futuro hay multi-empresa/instancias en el mismo backend, conviene segregar por tenant/instancia.

4) **Observabilidad**
   - Si se requiere auditoría operativa, agregar logging estructurado en backend (subidas, borrados, limpieza) y métricas.

---

## 7) Checklist de verificación manual (producción)
1) Activar backup nube en la sección “Backup profesional”.
2) Confirmar que la sincronización está configurada (baseUrl + token).
3) Forzar que pase la hora programada o esperar el trigger; verificar que:
   - `professional_backup_settings.json` se actualiza con `lastCloudBackupDate`.
   - El backend lista el archivo en `GET /system/backup/list`.
4) Simular backups viejos en backend y confirmar limpieza automática (4 días).
5) Verificar que local mantiene máximo 15 archivos en `<supportDirectory>/backups/local`.
