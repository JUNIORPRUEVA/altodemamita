# 🚀 FASE 2: STRESS TESTING - PLAN DE EJECUCIÓN

**Estado**: READY TO EXECUTE  
**Próximo Paso**: Manual execution o automatización  
**Reporte Será**: FASE_2_STRESS_TEST_RESULTS.md

---

## ESCENARIOS DE STRESS TEST

### TEST A: 24 HORAS INACTIVIDAD + TOKEN EXPIRY

**Objetivo**: Validar que JWT refresh automático funciona, sin "pending eterno"

**Pasos**:
1. Login online con PC primaria (LOCAL_MASTER_MODE=true en backend)
2. Sincronizar datos exitosamente
3. Crear VENTA + CUOTA para tener pending
4. **Esperar 24 horas** (O simular: cambiar token exp en JWT)
   - Backend debe dejar pasar durante ventana de refresh (6h antes vencer)
   - App debe detectar expiry próximo
5. **Verificar**:
   - ✅ JWT refresh automático ejecutado (_requestJwtRefresh)
   - ✅ Sync reintentó automáticamente
   - ✅ Venta + Cuota sincronizadas (no stuck en pending)
   - ✅ No aparece "error de sesión" falso
   - ✅ PWA refleja cambios

**Criterios Éxito**:
- [ ] JWT refreshed sin manual login
- [ ] Queue procesada post-refresh
- [ ] 0 pending records en APP
- [ ] 0 pending en backend
- [ ] Timestamp en nube actualizado

**Criterios Fallo** (Rollback):
- [ ] Pending infinito (>24h)
- [ ] 409 Conflict infinito
- [ ] Falso "sin conexión"
- [ ] Sessions falla sin retry

---

### TEST B: FULL RESTART (App + Backend + PC)

**Objetivo**: Validar que queue persiste, no duplica, no se corrompe

**Pasos**:
1. Login online, crear VENTA + PAGOS
2. SyncQueue tiene 3 items pending (cuotas)
3. **CLOSE APP** (graceful, mediante File > Exit)
4. **STOP BACKEND** (si es local) o simular desconexión
5. **RESTART PC** (O simulate via app restart)
6. **START BACKEND** (si stopped)
7. **REOPEN APP**
8. **Verificar**:
   - ✅ Queue items persisten en SQLite
   - ✅ No duplicados (contar en sync_queue table)
   - ✅ Sync reintenta automáticamente
   - ✅ No corruption en database

**Criterios Éxito**:
- [ ] sync_queue table no vacía post-restart
- [ ] rowcount(sync_queue) == 3 (no duplicados)
- [ ] Sync ejecuta automáticamente en app open
- [ ] PWA datos consistente con SQLite

**Criterios Fallo**:
- [ ] Queue vacía sin razón
- [ ] Duplicados en queue
- [ ] Database corrupted error
- [ ] Records no sincronizados

---

### TEST C: INTERNET INTERMITENTE (ON/OFF CYCLES)

**Objetivo**: Validar no duplica uploads, no race conditions, no orphan data

**Pasos**:
1. Login online, crear VENTA + CUOTA
2. Iniciar sync manual
3. **DESCONECTAR INTERNET** (simular: deshabilitar red)
   - Sync detecta offline → entra en pending
   - Timer sigue intentando periodicamente
4. **ESPERAR 10 SEG**
5. **RECONECTAR INTERNET**
   - Connectivity listener dispara handleConnectivityChanged
   - Sync reintenta
6. **REPETIR 5 VECES** (ON/OFF cycles)
7. **Verificar**:
   - ✅ Solo 1 venta en nube (no duplicados)
   - ✅ No upload parcial
   - ✅ No orphan records (venta sin cuotas, o viceversa)

**Criterios Éxito**:
- [ ] rowcount(sales where sync_id=X) == 1 en nube
- [ ] rowcount(installments for this sale) == todas presentes
- [ ] No partial uploads (all or nothing)
- [ ] Queue no corrupted tras cycles

**Criterios Fallo**:
- [ ] Duplicates en nube
- [ ] Orphan records
- [ ] Partial payment data
- [ ] Connectivity subscription muere

---

### TEST D: ARTIFICIAL CONFLICT (Nube más reciente, local viejo, PRIMARY PC uploads)

**Objetivo**: Validar LOCAL_MASTER_MODE funciona: local_wins sin 409

**Setup** (Manual DB manipulation):
1. Crear CLIENTE en LOCAL (SQLite) con updatedAt = 2026-05-10 00:00:00
2. Crear CLIENTE en NUBE con updatedAt = 2026-05-10 12:00:00 (más nuevo)
3. Modificar CLIENTE en LOCAL (no incrementar timestamp, dejar viejo)
4. **PC Primaria** intenta sync upload

**Esperado** (con LOCAL_MASTER_MODE=true):
```
isLocalMaster = isPrimary && ENV['LOCAL_MASTER_MODE'] === 'true'
// isLocalMaster = true
if (existingMs > incomingMs && !isLocalMaster) {  // → skipped
  throw 409  // ← NO LANZAR
}
// ✅ Accept local version
```

**Verificar**:
- ✅ NO 409 error
- ✅ Nube updatedAt actualizada a timestamp LOCAL
- ✅ No "server_won" strategy
- ✅ conflictLog? Check resolution = "local_wins"

**Criterios Éxito**:
- [ ] Upload succeeds (200 OK)
- [ ] Nube record updated to local timestamp
- [ ] conflictLog empty (no manual strategy logged)

**Criterios Fallo**:
- [ ] 409 Conflict thrown
- [ ] server_won in conflictLog
- [ ] Nube no actualizada

---

### TEST E: COMMERCIAL DELETE (Clients, Sellers, Products, Sales, Payments, Installments)

**Objetivo**: Validar deletes propagan sin re-aparecer, sin inconsistencias

**Pasos** (Ejecutar para cada scope):
1. Create entity (e.g., CLIENTE + VENTA + CUOTA + PAGO)
2. **DELETE CLIENTE** → app marks deletedAt
3. Sync upload
4. **Verify**:
   - ✅ deletedAt persisted en SQLite
   - ✅ deletedAt persisted en nube
   - ✅ Cliente no aparece en listings (UI oculta)
   - ✅ Associated SALES ocultas (cascade soft-delete logic)

**Scope Audit**:
- [ ] CLIENTS: delete → deletedAt set → hidden en listado
- [ ] SELLERS: delete → deletedAt set → productos sin vendedor
- [ ] PRODUCTS: delete → deletedAt set → no usable en nuevas ventas
- [ ] SALES: delete → deletedAt set → cuotas ocultas
- [ ] INSTALLMENTS: delete → deletedAt set (rare case)
- [ ] PAYMENTS: delete → deletedAt set (rare case)

**Criterios Éxito**:
- [ ] 0 hard deletes en DB (only soft via deletedAt)
- [ ] cascadas correctas (cliente delete → venta hidden)
- [ ] Nube refleja deletedAt changes

**Criterios Fallo**:
- [ ] Hard delete ejecutado (data perdida)
- [ ] Cascade broken (cliente deleted pero ventas still show)
- [ ] Reaparición de borrados tras sync

---

### TEST F: PWA STABILITY (No tiembla, no rebuild masivo, read-only, performance)

**Objetivo**: Validar PWA accesible sin degradación, sin aggressive polling

**Pasos**:
1. Backend + APP configuradas
2. **ABRIR PWA en Chrome** (https://nube.app/admin)
3. **Observar 10 minutos**:
   - ¿Rebuilds UI constantemente?
   - ¿Request spam a /api/sync/download?
   - ¿Memory crece?
   - ¿Responsive click to action?
4. **Crear transacción en APP** (nuevo pago)
5. **Observar PWA**: ¿Refleja cambio en <10 seg?
6. **Intentar mutar en PWA** (click delete, edit):
   - ✅ Debe rechazar (read-only) o permitir solo admin actions
   - ✅ No debe sobreescribir data APP

**Verificar Chrome DevTools**:
- [ ] Network: GET /api/sync/download freq normal (no spam)
- [ ] Performance: FCP <1s, LCP <2s
- [ ] Memory: no crecimiento lineal (graph estable)
- [ ] Console: 0 errors, 0 warnings reiterativos

**Criterios Éxito**:
- [ ] PWA renders stable (no flickering)
- [ ] Network requests <1 req/30s (not spamming)
- [ ] Memory stable
- [ ] Data refleja APP changes <10s

**Criterios Fallo**:
- [ ] PWA flickering
- [ ] Network: >1 request/sec
- [ ] Memory: linear growth
- [ ] Mutations from PWA override APP

---

### TEST G: MEMORY & TIMERS AUDIT (Leaks, zombies, subscriptions)

**Objetivo**: Validar no hay zombie timers, no memory leak, listeners limpios

**Tools Needed**:
- Dart DevTools (memory timeline)
- Dart Observatory (isolate profiler)
- Backend: Node.js memory snapshot

**Pasos** (App):
1. **Open Dart DevTools**: `flutter run --profile`
2. **Take baseline memory snapshot**
3. **Sync 50 transactions** (loop: create + sync + verify)
4. **GC trigger** (manual in DevTools)
5. **Take memory snapshot #2**
6. **Repeat steps 3-5 for 5 cycles**
7. **Analyze**:
   - ✅ Memory returns to baseline (no leak)
   - ✅ Timers not duplicated (check _retryTimer count)
   - ✅ Listeners disposed (check subscription count)

**Pasos** (Backend):
1. **Monitor Node process**: `node --inspect`
2. **Chrome DevTools**: chrome://inspect
3. **Loop**: call /api/sync/upload 100x
4. **Take heap snapshot**
5. **GC**
6. **Repeat**, compare snapshots
7. **Verify**: no growing detached DOM, no accumulating listeners

**Criterios Éxito**:
- [ ] Memory baseline post-GC ≤ 10% of peak
- [ ] 0 zombie timers
- [ ] 0 orphaned listeners
- [ ] Heap snapshots similar size

**Criterios Fallo**:
- [ ] Memory never returns to baseline
- [ ] Timers duplicated (_retryTimer count > 1)
- [ ] Listeners accumulate (count grows)
- [ ] Heap snapshot grows each cycle

---

### TEST H: AUTH BOOTSTRAP (Clean PC, Online Auth-Only, Offline, No Commercial Auto-Download)

**Objetivo**: Validar scopes separadas: auth-only on first login, commercial blocked offline

**Setup**:
1. **Clean PC**: delete SQLite database
2. **Start APP** → Login offline mode
3. **Verify**: 
   - ✅ Auth bootstrap triggered (ALLOW_AUTH_BOOTSTRAP=true)
   - ✅ Auth-only scopes downloaded (users, roles, permissions)
   - ✅ Commercial scopes NOT downloaded (clients, sales, payments)

4. **Login online**:
   - ✅ Full sync permitted (commercial scopes download allowed)

5. **Go offline again**:
   - ✅ Commercial edits still allowed (LOCAL first)
   - ✅ Sync queue builds pending
   - ✅ Offline UI works

**Verificar SyncService**:
```dart
static const bool _downloadFromCloudEnabled = allowCloudPull;  // false by default
// ALLOW_CLOUD_PULL must be false to block downloads
```

**Criterios Éxito**:
- [ ] First login (offline) → auth-only scopes present
- [ ] Commercial scopes absent initially
- [ ] Online sync fills commercial
- [ ] Offline edits persist (not rejected)
- [ ] Scope ordering respected

**Criterios Fallo**:
- [ ] Commercial scopes downloaded offline (breach)
- [ ] Auth-only missing after online sync
- [ ] Offline edits rejected
- [ ] Scope ordering violated

---

## MATRIZ DE EJECUCIÓN

| Test | Duración | Automatizable | Criterios | Riesgo |
|------|----------|---------------|-----------|----|
| A | 24h | ⚠️ Partial (simular token) | 3/5 | Bajo |
| B | 5 min | ✅ Sí | 4/4 | Bajo |
| C | 5 min | ✅ Sí | 3/4 | Bajo |
| D | 2 min | ✅ Sí (DB manipulation) | 3/3 | Bajo |
| E | 10 min | ✅ Sí | 6/6 | Medio |
| F | 10 min | ⚠️ Manual (observación) | 4/4 | Bajo |
| G | 30 min | ⚠️ Partial (DevTools) | 5/5 | Medio |
| H | 5 min | ✅ Sí | 6/6 | Bajo |

---

## PRÓXIMOS PASOS

### Fase 2.1: Ejecutar Tests A-D (Rápidos, Core Functionality)
- Validar JWT, restart, connectivity, conflicts
- **Expected Time**: 20 mins
- **Expected Result**: All pass ✅

### Fase 2.2: Ejecutar Tests E-H (Comprehensive)
- Validar deletes, PWA, memory, auth
- **Expected Time**: 1 hour
- **Expected Result**: All pass ✅ (or identify specific issues)

### Fase 3: Hardening Mínimo (Solo si falla algún test)
- Aplicar fixes únicamente a failing tests
- NO refactor masivo

### Fase 4: Final Report
- Compilar resultados
- Generar APPROVE/REJECT para RESTORE_FROM_CLOUD

---

**Status**: ✅ PLAN COMPLETO, READY FOR EXECUTION

**Documento**: FASE_2_STRESS_TEST_PLAN.md  
**Version**: 1.0  
**Generated**: 2026-05-10 16:50 UTC-3
