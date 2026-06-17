# INSTRUCCIONES PARA CAMBIAR DB EN EASYPANEL

**Proyecto:** SISTEMA_SOLARES Backend
**URL Backend:** https://altodemanita-altodemamita-backent.onqyr1.easypanel.host

---

## ⚠️ IMPORTANTE: Diferencia entre .env local y EasyPanel

| Archivo | ¿Afecta al backend desplegado? |
|---------|-------------------------------|
| `backend/.env` (local) | ❌ NO. Solo sirve para desarrollo local con `npm run dev` |
| EasyPanel Environment Variables | ✅ SÍ. Es lo único que usa el backend en producción |

**Cambiar `backend/.env` NO cambia la DB del backend desplegado.**

---

## PASOS PARA CAMBIAR LA DB

### 1. Entrar a EasyPanel
- Abrir https://easypanel.io o el panel de tu instancia
- Iniciar sesión

### 2. Ir al servicio del backend
- Buscar el proyecto "altodemamita" o "sistema-solares"
- Seleccionar el servicio del backend (no la DB, no el sitio estático)

### 3. Environment Variables
- Ir a la pestaña **"Environment"** o **"Variables de entorno"**
- Buscar la variable **`DATABASE_URL`**

### 4. Cambiar DATABASE_URL
La URL debe tener este formato:
```
postgresql://usuario:contraseña@host:puerto/nombre_db?schema=public
```

Ejemplo para DB nueva `altomamita_db_preprod`:
```
postgresql://user:password@onqyr1.easypanel.host:5432/altomamita_db_preprod?schema=public
```

**Importante:** Reemplazar `user:password` con las credenciales reales.

### 5. Guardar los cambios
- Hacer clic en **"Save"** o **"Update"**

### 6. Redeploy/Rebuild
- Ir a la pestaña **"Deploy"** o **"Build"**
- Hacer clic en **"Redeploy"** o **"Rebuild"**
- Esperar a que termine el build (1-3 minutos)

### 7. Verificar
Una vez redeployado, verificar:

```bash
# Endpoint de salud
curl https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api/health

# Endpoint de status (ahora muestra databaseName)
curl https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api/system/status
```

La respuesta de `/api/system/status` debe incluir:
```json
{
  "ok": true,
  "databaseConfigured": true,
  "databaseName": "altomamita_db_preprod",
  "databaseHost": "onqyr1.easypanel.host:5432",
  "timestamp": "..."
}
```

### 8. Verificar owner endpoints
```bash
curl -H "x-company-tenant-key: alto-dona-mamita-sistema-solares" \
  https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/owner/dashboard
```

Debe responder 200 con JSON, no 502.

---

## ¿QUÉ HACE EL DOCKERFILE AHORA?

El Dockerfile actualizado ejecuta automáticamente:
```bash
npx prisma migrate deploy && node dist/server.js
```

Esto significa que **al redeployar**, Prisma ejecutará las migraciones pendientes automáticamente.

Si la DB es nueva, se crearán todas las tablas:
- Client, Seller, Lot, Sale, Installment, Payment, SyncBatch, User, Company
- `_prisma_migrations` (tabla de control de Prisma)

---

## SI LAS MIGRACIONES FALLAN

Si el redeploy falla, se puede ejecutar manualmente:

```bash
# Conectarse al contenedor via EasyPanel terminal
npx prisma migrate deploy
```

O desde local apuntando a la DB remota:
```bash
cd backend
DATABASE_URL="postgresql://user:password@host:5432/altomamita_db_preprod?schema=public" npx prisma migrate deploy
```

---

## VERIFICAR DB CON PGWEB

Si EasyPanel tiene pgweb habilitado:
1. Ir a la pestaña de la DB
2. Abrir pgweb
3. Verificar que existan las tablas listadas arriba
4. Verificar `_prisma_migrations` tenga los 3 migrations aplicados

---

## RESET DE BANDERA INITIAL_CLOUD_UPLOAD

Si se cambia la DB detrás del mismo backend URL, la app local detecta el cambio automáticamente porque compara la URL guardada vs actual en `SyncConfigRepository.isLocalUploadBootstrapCompleted()`.

Si por alguna razón no se resetea sola, ejecutar:
```bash
tools\scripts\reset_initial_cloud_upload_flag.bat
```

Esto borra las claves de SharedPreferences y fuerza una nueva sincronización inicial.

---

## FLUJO COMPLETO RECOMENDADO

1. ✅ Crear DB `altomamita_db_preprod` en EasyPanel (o la que se desee)
2. ✅ Cambiar `DATABASE_URL` en Environment Variables de EasyPanel
3. ✅ Redeploy del backend
4. ✅ Verificar `/api/system/status` → databaseName correcto
5. ✅ Verificar `/owner/dashboard` → 200 OK
6. ✅ (Opcional) Resetear bandera InitialCloudUpload en PC local
7. ✅ Abrir app_local → debe sincronizar contra la nueva DB
8. ✅ Generar nueva APK Owner con `--dart-define=OWNER_API_BASE_URL=...`
9. ✅ Instalar APK en teléfono → debe conectar al backend
