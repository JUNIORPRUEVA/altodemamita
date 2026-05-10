# DEPLOY CHECKLIST A STAGING - LOCAL_MASTER_MODE

**Objetivo**: Activar LOCAL_MASTER_MODE en staging y validar conflicto artificial

**Fecha Target**: 10-11 de Mayo de 2026

---

## PASO 1: Backend Environment Configuration

### En EasyPanel Dashboard

1. **Acceder a**: Panel Web → Variables de Entorno → Backend Service
2. **Buscar**: `LOCAL_MASTER_MODE`
3. **Cambiar**: `LOCAL_MASTER_MODE=false` → `LOCAL_MASTER_MODE=true`
4. **Guardar** y **Redeploy** el servicio backend

```bash
# Verificar en backend logs
grep "LOCAL_MASTER_MODE" /app/logs/backend.log
# Debe mostrar: LOCAL_MASTER_MODE activo: conflictos...
```

---

## PASO 2: Verificar PC Primary en BD

### En PostgreSQL (via EasyPanel o DBeaver)

```sql
SELECT 
  device_id,
  is_primary,
  can_write,
  created_at,
  updated_at
FROM device_authorizations
WHERE is_primary = true;
```

**Esperado**: 1 fila con `is_primary=true`

Si no existe:
```sql
INSERT INTO device_authorizations (
  device_id,
  is_primary,
  can_write,
  created_at,
  updated_at
)
VALUES (
  '<device-id-from-settings>',
  true,
  true,
  NOW(),
  NOW()
);
```

---

## PASO 3: Test Manual - Conflicto Artificial

### Preparación Local

1. **Abre Settings → Técnico → Mostrar Device ID**
   - Copia el `device_id`
2. **Settings → Mostrar que es PC PRIMARY**
   - Debe mostrar: `isPrimary=true` (o similar)

### Crear Conflicto

1. **Crear cliente en local**:
   - Nombre: "TestClient_CONFLICT_20260510"
   - Phone: "555-TEST-LOCAL"

2. **Desconecta internet** (simula offline)

3. **Actualiza cliente**:
   - Phone: "555-TEST-UPDATED-LOCAL"
   - Sync sube a queue

4. **En backend BD** (DBeaver o EasyPanel):
   ```sql
   SELECT sync_id, updated_at FROM client 
   WHERE first_name = 'TestClient_CONFLICT_20260510'
   LIMIT 1;
   ```
   - Anota el `sync_id`

5. **Actualiza en BD el updatedAt al futuro** (simula que nube es más reciente):
   ```sql
   UPDATE client 
   SET updated_at = NOW() + INTERVAL '1 hour'
   WHERE sync_id = '<sync_id_from_step_4>';
   ```

6. **Reconecta internet** (vuelve online)

7. **Fuerza Sync** en app:
   - Settings → Sincronizar → Manual Sync

### Validar Resultado

- ✅ **ESPERADO**: Upload SUCCESS (no 409)
- ✅ **Log Backend**: Debe mostrar `local_master_mode activo` y allow override
- ✅ **Cliente Actualizado**: Phone debe ser "555-TEST-UPDATED-LOCAL"
- ❌ **INCORRECTO**: Si obtiene 409 error

**Si obtiene 409**:
- Verificar que `LOCAL_MASTER_MODE=true` en env
- Verificar que `isPrimary=true` en DB
- Verificar que backend fue redeployed después de cambio

---

## PASO 4: Test - Secondary PC (Opcional)

Si tienes segunda PC:

1. **Login en secondary con mismo usuario**
2. **Crea cliente diferente**: "SecondaryTest"
3. **Intenta modificar cliente de primary**:
   - Cambia phone a "555-SECONDARY-EDIT"
4. **Resultado esperado**:
   - Upload BLOQUEADO (409 porque secondary no es primary)
   - Mensaje: "Conflicto de sincronización: el servidor tiene versión más reciente"

---

## PASO 5: Validación Final

### Checklist de Validación

- [ ] Backend redeploy exitoso
- [ ] `LOCAL_MASTER_MODE=true` confirmado en env variables
- [ ] PC primary tiene `isPrimary=true` en DB
- [ ] Test conflicto: upload SUCCESS (no 409)
- [ ] Cliente actualizado con cambio local
- [ ] Logs backend muestran "local_master_mode activo"
- [ ] PWA refleja cambio dentro de 30 segundos
- [ ] Segundo login (secondary PC) respeta isPrimary=false

### Si Algo Falla

1. **Revisar logs backend**:
   ```bash
   docker logs backend-container | grep -i local_master
   docker logs backend-container | grep -i conflict
   ```

2. **Verificar env variables**:
   ```bash
   docker exec backend-container env | grep LOCAL_MASTER_MODE
   ```

3. **Restaurar a safe state**:
   ```bash
   # Revertir en EasyPanel: LOCAL_MASTER_MODE=false
   # Redeploy
   # Esperar 2 minutos
   ```

---

## PASO 6: Sign-Off

Cuando todo pase:

1. **Documentar resultados** en AUDITORIA_CERTIFICACION_FASE_ACTUAL.md
2. **Actualizar sección 9.3**:
   - ✅ LOCAL_MASTER_MODE=true en staging
   - ✅ Test conflicto artificial PASSED
   - ✅ Ready for RESTORE_FROM_CLOUD implementation

3. **Proceder a**: Implementar RESTORE_FROM_CLOUD con scope ordering

---

## ENVIRONMENT VARIABLE REFERENCE

### Backend .env (vía EasyPanel)

```env
# Modo LOCAL MASTER: la PC primaria autorizada siempre gana conflictos
LOCAL_MASTER_MODE=true

# Otros flags relacionados (mantener como están)
READ_ONLY_MODE=false
ALLOW_CLOUD_PULL=false  # ← Frontend, pero documentado para referencia
```

### Frontend (.dart-define en CLI si necesario)

```bash
flutter run \
  --dart-define=ALLOW_CLOUD_PULL=false \
  --dart-define=PRODUCTION_MODE=true \
  --dart-define=LOCAL_MASTER_MODE=true
```

---

## ROLLBACK PROCEDURE

Si necesitas revertir:

1. **En EasyPanel**:
   - LOCAL_MASTER_MODE=false
   - Redeploy

2. **Esperar 2 minutos**

3. **Validar en backend**:
   ```bash
   docker logs backend-container | grep "LOCAL_MASTER_MODE"
   ```

4. **Confirmar que vuelve a rechazar conflictos** (409)

---

**Documento**: Deploy Checklist Local Master Mode  
**Versión**: 1.0  
**Creado**: 10 de Mayo de 2026  
**Status**: READY FOR STAGING
