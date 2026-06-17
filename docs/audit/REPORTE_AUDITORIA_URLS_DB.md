# REPORTE DE AUDITORÍA - URLs, DB y Conexión

**Fecha:** 2026-06-17
**Proyecto:** SISTEMA_SOLARES (Monorepo)
**Backend URL:** https://altodemanita-altodemamita-backent.onqyr1.easypanel.host

---

## A. URL FINAL APP_LOCAL (Windows)

| Aspecto | Valor |
|---------|-------|
| **Variable usada** | `SYNC_API_BASE_URL` |
| **Archivo donde se lee** | `app_local/lib/core/config/backend_config.dart` (línea 19-22) |
| **Default (desarrollo)** | `http://localhost:3000` |
| **Valor producción** | `https://altodemanita-altodemamita-backent.onqyr1.easypanel.host` |
| **Comando build exacto** | `flutter build windows --release --dart-define=SYNC_API_BASE_URL=https://altodemanita-altodemamita-backent.onqyr1.easypanel.host` |
| **Script de build** | `tools/scripts/build_release_installer.ps1` (línea 142) ✅ CORREGIDO |
| **Log en debug** | `[BackendConfig] SYNC_API_BASE_URL=...` en `backend_config.dart` línea 104 ✅ YA EXISTE |

### Archivos que usan BASE_URL / effectiveBackendBaseUrl:
- `app_local/lib/core/config/backend_config.dart` - define y normaliza la URL
- `app_local/lib/services/sync/sync_api_client.dart` - construye endpoints `/sync/upload`, `/sync/download`, etc.
- `app_local/lib/services/sync/sync_config_repository.dart` - carga settings con `backend_config.BASE_URL`
- `app_local/lib/services/sync/initial_cloud_upload_service.dart` - verifica backend online con `/system/status`

---

## B. URL FINAL APP_OWNER (Android)

| Aspecto | Valor |
|---------|-------|
| **Variable usada** | `OWNER_API_BASE_URL` |
| **Archivo donde se lee** | `app_owner/lib/core/constants.dart` (línea 1-4) |
| **Default (desarrollo)** | `http://10.0.2.2:3000` |
| **Valor producción** | `https://altodemanita-altodemamita-backent.onqyr1.easypanel.host` |
| **Comando build exacto** | `flutter build apk --release --dart-define=OWNER_API_BASE_URL=https://altodemanita-altodemamita-backent.onqyr1.easypanel.host` |
| **Log en debug** | `[OwnerApi] OWNER_API_BASE_URL=$baseUrl` en `api_client.dart` ✅ AGREGADO |
| **Log en request** | `[OwnerApi] request url=$uri` ✅ AGREGADO |
| **Log en error** | `[OwnerApi] request failed url=$uri error=$errorMsg` ✅ AGREGADO |

### Cómo se usa:
- `app_owner/lib/app/app_shell.dart` línea 52: `const ApiClient(baseUrl)` donde `baseUrl` viene de `constants.dart`
- `app_owner/lib/core/services/api_client.dart` construye URLs: `$baseUrl/owner/dashboard`, `$baseUrl/owner/clients`, etc.

---

## C. BACKEND

| Aspecto | Estado |
|---------|--------|
| **DATABASE_URL hardcodeada** | ❌ NO. Solo en `.env.example` como placeholder |
| **Uso de dotenv** | ✅ `import 'dotenv/config'` en `src/config.ts` |
| **Prisma datasource** | ✅ `url = env("DATABASE_URL")` en `schema.prisma` |
| **Validación** | ✅ `validateConfig()` verifica que DATABASE_URL no esté vacío |
| **Dockerfile migraciones** | ❌ NO ejecutaba `npx prisma migrate deploy` → ✅ CORREGIDO |
| **Endpoint /api/system/status** | ✅ Responde 200 pero NO incluía databaseName → ✅ CORREGIDO (ahora incluye databaseName, databaseHost, databaseConfigured) |
| **Endpoint /api/system/config** | ✅ Responde 200 |
| **Endpoint /api/health** | ✅ Responde 200 |
| **Endpoint /owner/dashboard** | ❌ Responde 502 (DB no configurada o sin migraciones) |

### Diagnóstico de DB actual:
- `/api/system/status` actual NO muestra databaseName (versión antigua desplegada)
- El 502 en `/owner/dashboard` indica que la DB no está accesible o no tiene las tablas necesarias
- **El backend desplegado NO tiene el nuevo código** - necesita redeploy con los cambios

### Migraciones disponibles en `backend/prisma/migrations/`:
1. `20260616170000_initial_owner_sync` - Migración inicial
2. `20260616213000_add_company_tenant_scope` - Scope de compañía
3. `20260616220000_add_partial_unique_indexes` - Índices únicos parciales

---

## D. ANDROID - PERMISOS Y CONEXIÓN

| Aspecto | Estado |
|---------|--------|
| **INTERNET permission** | ✅ PRESENTE en `AndroidManifest.xml` línea 2 |
| **usesCleartextTraffic** | ❌ NO configurado (no necesario para HTTPS) |
| **minSdkVersion** | ✅ Flutter default (21) |
| **targetSdkVersion** | ✅ Flutter default |
| **network_security_config** | ❌ NO configurado (no necesario para HTTPS) |
| **Timeouts** | ✅ 15 segundos en `api_client.dart` |
| **Logs de error** | ✅ AGREGADOS: `[OwnerApi] connection error`, `[OwnerApi] http error`, `[OwnerApi] request failed` |

### Prueba desde PC:
- `https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api/health` → ✅ 200
- `https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api/system/status` → ✅ 200
- `https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api/system/config` → ✅ 200
- `https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/owner/dashboard` → ❌ 502

---

## E. ENDPOINTS - ESTADO ACTUAL

| Endpoint | Status | Respuesta |
|----------|--------|-----------|
| `/api/health` | ✅ 200 | `{"ok":true,"service":"sistema-solares-backend"}` |
| `/api/system/status` | ✅ 200 | `{"ok":true,"status":"online","service":"sistema-solares-backend","initialized":true,"timestamp":"..."}` |
| `/api/system/config` | ✅ 200 | `{"ok":true,"allowCloudPull":false,...}` |
| `/owner/dashboard` | ❌ 502 | Error de DB - necesita migraciones |
| `/owner/clients` | ❌ 502 | Error de DB |
| `/owner/lots` | ❌ 502 | Error de DB |
| `/owner/sales` | ❌ 502 | Error de DB |

---

## F. BUILDS

### APK Owner (Android):
```bash
cd app_owner
flutter clean
flutter pub get
flutter analyze
flutter build apk --release --dart-define=OWNER_API_BASE_URL=https://altodemanita-altodemamita-backent.onqyr1.easypanel.host
```
**Ruta final:** `app_owner/build/app/outputs/flutter-apk/app-release.apk`

### Windows (app_local):
```bash
cd app_local
flutter clean
flutter pub get
flutter analyze
flutter build windows --release --dart-define=SYNC_API_BASE_URL=https://altodemanita-altodemamita-backent.onqyr1.easypanel.host
```
**Ruta final:** `app_local/build/windows/x64/runner/Release/sistema_solares.exe`

### Instalador Windows:
```bash
powershell -ExecutionPolicy Bypass -File .\tools\scripts\build_release_installer.ps1 -Build -CompileInstaller
```
**Ruta final:** `tools/installer/output/SistemaSolares_Setup_<version>.exe`

---

## G. DB - ESTADO Y MIGRACIONES

### DB que está usando el backend AHORA:
- **No se puede determinar con certeza** porque `/api/system/status` actual no incluye databaseName
- El 502 en owner/dashboard sugiere que la DB apuntada no existe o no tiene tablas
- **Después del redeploy**, `/api/system/status` mostrará: `databaseName`, `databaseHost`, `databaseConfigured`

### Para cambiar la DB:
Ver instrucciones en `docs/audit/EASYPANEL_INSTRUCCIONES.md`

### Migraciones:
- El Dockerfile ahora ejecuta `npx prisma migrate deploy` antes de iniciar ✅ CORREGIDO
- Migraciones existentes: 3 (initial_owner_sync, add_company_tenant_scope, add_partial_unique_indexes)

---

## H. BANDERA INITIAL_CLOUD_UPLOAD

| Aspecto | Detalle |
|---------|---------|
| **Dónde se guarda** | SharedPreferences de Windows: `%APPDATA%/com.example.sistema_solares/flutter_shared_preferences.json` |
| **Claves** | `sync.local_upload_bootstrap_completed`, `sync.local_upload_bootstrap_completed_at`, `sync.local_upload_bootstrap_backend_url`, `sync.local_upload_bootstrap_version` |
| **Código** | `app_local/lib/services/sync/sync_config_repository.dart` (líneas 191-250) |
| **Reset automático** | Si la URL del backend cambia, la bandera se invalida sola (compara URL guardada vs actual) |
| **Script de reset** | `tools/scripts/reset_initial_cloud_upload_flag.bat` ✅ CREADO |

---

## I. ARCHIVOS MODIFICADOS EN ESTA AUDITORÍA

| Archivo | Cambio |
|---------|--------|
| `backend/src/routes/system.routes.ts` | ✅ Agregado databaseName, databaseHost, databaseConfigured a `/api/system/status` |
| `backend/Dockerfile` | ✅ Agregado `npx prisma migrate deploy` en CMD |
| `tools/scripts/build_release_installer.ps1` | ✅ Agregado `--dart-define=SYNC_API_BASE_URL=...` al build |
| `app_owner/lib/core/services/api_client.dart` | ✅ Agregados logs de URL, request, response, errores |
| `tools/scripts/reset_initial_cloud_upload_flag.bat` | ✅ CREADO - script para resetear bandera InitialCloudUpload |
| `docs/audit/REPORTE_AUDITORIA_URLS_DB.md` | ✅ Este reporte |
| `docs/audit/EASYPANEL_INSTRUCCIONES.md` | ✅ Instrucciones EasyPanel |

---

## J. PROBLEMAS DETECTADOS Y SOLUCIONES

### Problema 1: Backend desplegado NO tiene los cambios
- **Síntoma:** `/api/system/status` no muestra databaseName
- **Solución:** Hacer redeploy del backend en EasyPanel con el nuevo código

### Problema 2: Owner endpoints dan 502
- **Síntoma:** `/owner/dashboard`, `/owner/clients`, etc. responden 502
- **Causa probable:** La DB configurada en DATABASE_URL de EasyPanel no existe o no tiene migraciones
- **Solución:** 
  1. Verificar DATABASE_URL en EasyPanel
  2. Crear la DB si no existe
  3. Hacer redeploy (el Dockerfile ahora ejecuta migraciones automáticamente)
  4. Verificar con `/api/system/status`

### Problema 3: Script de build no pasaba --dart-define
- **Síntoma:** El instalador de Windows se generaba sin la URL de producción
- **Solución:** ✅ CORREGIDO - ahora `build_release_installer.ps1` pasa `--dart-define=SYNC_API_BASE_URL=...`

### Problema 4: Sin logs de depuración en app_owner
- **Síntoma:** No se podía ver qué URL estaba usando la app ni por qué fallaba
- **Solución:** ✅ CORREGIDO - ahora `api_client.dart` tiene logs completos en debug mode
