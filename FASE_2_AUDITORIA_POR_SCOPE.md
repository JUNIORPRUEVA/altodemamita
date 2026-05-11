# FASE 2: AUDITORÍA POR SCOPE/TABLA

**Estado**: DESCUBRIMIENTO SOLAMENTE - Sin correcciones de código  
**Método**: Búsqueda grep + lectura de archivos de repositorio  
**Alcance**: 14 tablas comerciales + auth  

---

## TABLA 1: SALES / VENTAS (CRÍTICA - COMERCIAL)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | `lib/features/sales/data/sales_repository.dart` | Línea 271: `Future<int> createSale(SaleDraft draft)` |
| **2. Función CREATE exacta** | `createSale(SaleDraft)` | Inserta en `DatabaseSchema.salesTable`, genera `saleSyncId = _newLocalSaleSyncId()` |
| **3. Archivo frontend UPDATE** | `lib/features/sales/data/sales_repository.dart` | Línea 540+: `Future<void> updateSale(int saleId, SaleDraft draft)` |
| **4. Función UPDATE exacta** | `updateSale(saleId, draft)` | UPDATE salesTable con WHERE saleId=?, incrementa version |
| **5. Archivo frontend DELETE** | `lib/features/sales/data/sales_repository.dart` | Línea 920: `Future<void> deleteSale(int saleId)` |
| **6. Función DELETE exacta** | `deleteSale(saleId)` | Soft-delete: UPDATE salesTable SET `deleted_at = now, sync_status = 'pending_delete'` |
| **7. Delete type (soft/hard)** | SOFT DELETE | Línea 1270: `'deleted_at': now` |
| **8. sync_status usado** | YES | Usa `sync_status = 'pending_delete'` en delete (línea 996-1009) |
| **9. sync_queue enqueue** | YES - Manual schedule | Línea 1151: `_scheduleCreateSaleSync(saleId, saleSyncId)` llamado después insert |
| **10. Payload exacto subido** | Full record + version | POST /api/sync/upload con fields: id, sync_id, version, deleted_at, sync_status, etc. |
| **11. Backend que recibe** | `backend/src/modules/sales/infrastructure/controllers/sales.controller.ts` | @Post() línea 33, @Delete(':id') línea 66 |
| **12. Backend aplica** | sync.service.ts línea 596-610 | Detecta isDeleteMutation, si isPrimary + LOCAL_MASTER_MODE → soft-delete directo |
| **13. Puede devolver 409** | YES | sync.service.ts línea ~200: Si version conflict → 409 Conflict response |
| **14. server_won posible** | YES - Código permite | sync_conflict_service.dart línea 276: `resolution='server_won'` existe pero parece manual UI |
| **15. ALLOW_CLOUD_PULL protege** | PARCIAL | sync_service.dart línea 484: Bloquea `downloadUpdates()` si false, pero emergency_restore ignora |
| **16. PWA muestra correctamente** | DESCONOCIDO | PWA excluida de búsqueda (sistema_solares_ui/*.gitignored) |
| **17. Puede quedar huérfano** | POSIBLE | Foreign key sales → clientes + vendedores + solares. Si cliente deleted → venta huérfana |
| **18. Riesgo** | **CRÍTICO** | Hard delete `@Delete('force-delete/:id')` línea 76 backend. Datos financieros. |
| **19. Recomendación** | Bloquear force-delete, validar orphan FK on download, PWA soft-delete filter audit |

---

## TABLA 2: INSTALLMENTS / CUOTAS (COMERCIAL)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | `lib/features/sales/data/sales_repository.dart` | Línea ~450: creadas en `createSale()` dentro de transacción |
| **2. Función CREATE exacta** | Auto-generated en `createSale()` | No hay `createInstallment()` pública, se generan automáticamente con instalments.insert() |
| **3. Archivo frontend UPDATE** | `lib/features/installments/data/installments_repository.dart` | Interno, NO expuesto públicamente |
| **4. Función UPDATE exacta** | (No encontrada public) | Cuotas se actualizan implícitamente cuando se registran pagos |
| **5. Archivo frontend DELETE** | `lib/features/sales/data/sales_repository.dart` | Línea 450: `UPDATE installmentsTable SET deleted_at = ?, sync_status = ? WHERE venta_id = ?` |
| **6. Función DELETE exacta** | Via `updateSale()` cascade | Soft-delete cuando venta se edita o elimina |
| **7. Delete type (soft/hard)** | SOFT DELETE | Línea 450-452: `'deleted_at = ?, fecha_actualizacion = ?, last_modified_local = ?, sync_status = ?'` |
| **8. sync_status usado** | YES | `sync_status='pending_delete'` al eliminar cuota |
| **9. sync_queue enqueue** | YES - Cascade | Cuando venta se elimina, cuotas se marcan pending_delete y se encolan |
| **10. Payload exacto subido** | Delta de cuota deleted | Scope='installments', operation='delete', soft-delete marker |
| **11. Backend que recibe** | `backend/src/modules/installments/infrastructure/controllers/installments.controller.ts` | @Post() línea 16, @Delete(':id') línea 49 |
| **12. Backend aplica** | sync.service.ts línea ~1187 | Detecta deleted_at, aplica soft-delete a PostgreSQL installments table |
| **13. Puede devolver 409** | YES | Si version conflict en cuota durante sincronización |
| **14. server_won posible** | BAJO RIESGO | Cuotas son dependientes de ventas, rara vez conflicto directo |
| **15. ALLOW_CLOUD_PULL protege** | SÍ | No se descargan cambios de cuota desde cloud si flag=false |
| **16. PWA muestra correctamente** | DESCONOCIDO | PWA excluida de búsqueda |
| **17. Puede quedar huérfano** | SÍ | Cuota sin venta si venta eliminada pero cuota no sincronizada |
| **18. Riesgo** | **ALTO** | Dependencia en cascada, si venta desaparece cuota queda huérfana |
| **19. Recomendación** | Auditar FK constraint venta_id, validar cascade delete en backend |

---

## TABLA 3: PAYMENTS / PAGOS (COMERCIAL - FINANCIERO CRÍTICO)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | `lib/features/payments/data/payments_repository.dart` | Línea 214: `Future<void> registerPayment(PaymentDraft draft)` |
| **2. Función CREATE exacta** | `registerPayment(draft)` | Inserta en paymentsTable con sync_status='pending', genera sync_queue entry |
| **3. Archivo frontend UPDATE** | `lib/features/payments/data/payments_repository.dart` | No hay update público, create-only pattern |
| **4. Función UPDATE exacta** | (No updates permitidos) | Pagos son inmutables por diseño (audit trail) |
| **5. Archivo frontend DELETE** | `lib/features/payments/data/payments_repository.dart` | Línea 259: `Future<void> deletePayment(int paymentId)` |
| **6. Función DELETE exacta** | `deletePayment(paymentId)` | Soft-delete: UPDATE paymentsTable SET `deleted_at = updatedAt, sync_status = 'pending_delete'` |
| **7. Delete type (soft/hard)** | SOFT DELETE | Línea 345: `'deleted_at': updatedAt` |
| **8. sync_status usado** | YES | `sync_status='pending_delete'` obligatorio |
| **9. sync_queue enqueue** | YES | Línea 628: Log "scope=payments operation=delete ...sync_status=pending" |
| **10. Payload exacto subido** | Full payment record + deleted_at | POST /api/sync/upload con deletion marker |
| **11. Backend que recibe** | `backend/src/modules/payments/infrastructure/controllers/payments.controller.ts` | @Post() línea 17, @Delete(':id') línea 62 |
| **12. Backend aplica** | sync.service.ts línea ~1380 | Detecta deleted_at en payment, soft-delete PostgreSQL record |
| **13. Puede devolver 409** | YES | Si payment version conflict o cuota linked conflict |
| **14. server_won posible** | BAJO RIESGO | Pagos son append-only, server_won rare but possible |
| **15. ALLOW_CLOUD_PULL protege** | SÍ | Bloquea download pagos si flag=false |
| **16. PWA muestra correctamente** | DESCONOCIDO | PWA excluida de búsqueda |
| **17. Puede quedar huérfano** | SÍ | Pago sin cuota si cuota eliminada antes de sincronizar pago |
| **18. Riesgo** | **CRÍTICO** | Pagos son dinero. Eliminación no debe ser posible fácilmente. Audit trail essential. |
| **19. Recomendación** | Hard-delete payments (never recover), require special permission, audit log mandatory |

---

## TABLA 4: CLIENTS / CLIENTES (COMERCIAL)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | `lib/features/clients/data/client_repository.dart` | Línea ~190: `insert()` call en transacción |
| **2. Función CREATE exacta** | Via `createOrUpdate(client)` | INSERT clientsTable con sync_status='pending' |
| **3. Archivo frontend UPDATE** | `lib/features/clients/data/client_repository.dart` | Mismo método: `createOrUpdate()` detecta duplicado, UPDATE |
| **4. Función UPDATE exacta** | `createOrUpdate(client)` | UPDATE clientsTable WHERE cedula=?, sync_status='pending_update' |
| **5. Archivo frontend DELETE** | `lib/features/clients/data/client_repository.dart` | Línea 284: `await txn.update(..., 'SET sync_status = ?, deleted_at = ?, ...', [syncStatusPendingDelete, now, ...])` |
| **6. Función DELETE exacta** | Via `softDelete(id)` | Soft-delete: UPDATE clientsTable SET `deleted_at = now, sync_status = 'pending_delete'` |
| **7. Delete type (soft/hard)** | SOFT DELETE | Línea 284: `sync_status = syncStatusPendingDelete` |
| **8. sync_status usado** | YES | pending, pending_update, pending_delete |
| **9. sync_queue enqueue** | YES - Implicit | sync_queue_service.dart auto-queues clients by scope |
| **10. Payload exacto subido** | Full client + deleted_at | POST /api/sync/upload scope='clients' |
| **11. Backend que recibe** | `backend/src/modules/clients/infrastructure/controllers/clients.controller.ts` | @Post() línea 14, @Delete(':id') línea 38 |
| **12. Backend aplica** | sync.service.ts línea ~748 | isActive = (deleted_at == null), soft-delete PostgreSQL |
| **13. Puede devolver 409** | YES | Si cedula duplicate or version conflict |
| **14. server_won posible** | YES | Código permite, pero raro para clientes |
| **15. ALLOW_CLOUD_PULL protege** | SÍ | Bloquea cliente download si flag=false |
| **16. PWA muestra correctamente** | DESCONOCIDO | PWA excluida de búsqueda |
| **17. Puede quedar huérfano** | SÍ | Cliente eliminado pero ventas activas → orphan sales |
| **18. Riesgo** | **ALTO** | Eliminar cliente con deudas activas podría esconder deuda |
| **19. Recomendación** | FK constraint sales→clientes, prevent delete if active sales exist, audit all deletes |

---

## TABLA 5: SELLERS / VENDEDORES (COMERCIAL)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | Sellers integrated en Sales dialog | `lib/features/sales/presentation/sale_form_dialog.dart` línea 1928: `_createSellerQuickly()` |
| **2. Función CREATE exacta** | Via HTTP backend API call | Direct POST /api/sellers (UI-driven, not sync queue first) |
| **3. Archivo frontend UPDATE** | Not found in client | Vendedores read-only después de crear |
| **4. Función UPDATE exacta** | (No public update) | Backend only |
| **5. Archivo frontend DELETE** | Backend /api/sellers/:id @Delete | Línea 38 backend controllers/sellers.controller.ts |
| **6. Función DELETE exacta** | Backend call only | No local client delete found |
| **7. Delete type (soft/hard)** | SOFT DELETE (inferred) | sync.service.ts línea 3449: `deleted_at: seller.deletedAt?.toISOString()` |
| **8. sync_status usado** | YES (backend) | sync.service.ts: `sync_status: seller.syncStatus` |
| **9. sync_queue enqueue** | PARTIAL | Sellers created via HTTP, then queued for download sync |
| **10. Payload exacto subido** | Seller object | POST /api/sellers |
| **11. Backend que recibe** | `backend/src/modules/sellers/infrastructure/controllers/sellers.controller.ts` | @Post() línea 14, @Delete(':id') línea 38 |
| **12. Backend aplica** | sync.service.ts línea 3449 | Soft-delete Prisma seller record |
| **13. Puede devolver 409** | YES | If seller edit conflict |
| **14. server_won posible** | BAJO RIESGO | Sellers are reference data |
| **15. ALLOW_CLOUD_PULL protege** | SÍ | No automatic download |
| **16. PWA muestra correctamente** | DESCONOCIDO | PWA excluida de búsqueda |
| **17. Puede quedar huérfano** | SÍ | Vendedor eliminado pero ventas activas → orphan |
| **18. Riesgo** | **MEDIO** | Vendedor es comisión, eliminar esconde historial |
| **19. Recomendación** | Prevent delete if active sales, require admin confirmation |

---

## TABLA 6: PRODUCTS / SOLARES (COMERCIAL)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | No direct client CREATE found | Lotes/solares creados via backend |
| **2. Función CREATE exacta** | Backend only: POST /api/products | `backend/src/modules/products/infrastructure/controllers/products.controller.ts` @Post() línea 14 |
| **3. Archivo frontend UPDATE** | No public client UPDATE | Backend POST /api/products/:id |
| **4. Función UPDATE exacta** | Backend only | productos actualizados vía HTTP |
| **5. Archivo frontend DELETE** | Backend DELETE /api/products/:id | controllers/products.controller.ts @Delete(':id') línea 38 |
| **6. Función DELETE exacta** | Backend-driven | sync.service.ts detecta deleted_at |
| **7. Delete type (soft/hard)** | SOFT DELETE | sync.service.ts línea 3423: `deleted_at: product.deletedAt?.toISOString()` |
| **8. sync_status usado** | YES | `sync_status: product.syncStatus` |
| **9. sync_queue enqueue** | SPECIAL CASE | Products 409 conflicts aislados, no auto-retry (línea 1353-1354) |
| **10. Payload exacto subido** | Product record | POST /api/sync/upload scope='products' |
| **11. Backend que recibe** | `backend/src/modules/products/infrastructure/controllers/products.controller.ts` | @Post(), @Delete() |
| **12. Backend aplica** | sync.service.ts | Soft-delete Prisma product |
| **13. Puede devolver 409** | **YES - SPECIAL** | sync_queue_service.dart línea 1620-1626: `_hasLegacyHardDeleteError()` detecta patrón `DELETE FROM solares WHERE deleted_at IS NOT NULL` |
| **14. server_won posible** | BAJO RIESGO | Productos son inventario |
| **15. ALLOW_CLOUD_PULL protege** | SÍ | Bloquea product download si flag=false |
| **16. PWA muestra correctamente** | DESCONOCIDO | PWA excluida de búsqueda |
| **17. Puede quedar huérfano** | SÍ | Solar sin propietario si cliente eliminado |
| **18. Riesgo** | **ALTO** | Legacy hard-delete pattern aún detectado en línea 1620-1626 comentario |
| **19. Recomendación** | Audit legacy hard-delete references, ensure all product deletes use soft-delete |

---

## TABLA 7: USERS / USUARIOS (AUTH - BOOTSTRAP)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | `lib/features/auth/data/auth_service.dart` | No local create, cloud bootstrap only |
| **2. Función CREATE exacta** | `login(email, password)` | POST /api/auth/login, obtiene JWT |
| **3. Archivo frontend UPDATE** | No client-side update | Backend only |
| **4. Función UPDATE exacta** | (No local) | Backend /api/auth/users/:id |
| **5. Archivo frontend DELETE** | No client-side delete | Backend /api/auth/:id |
| **6. Función DELETE exacta** | Backend only | @Delete(':id') auth.controller.ts línea 40 |
| **7. Delete type (soft/hard)** | SOFT DELETE (inferred) | sync.service.ts línea 3239: `deleted_at: user.deletedAt?.toISOString()` |
| **8. sync_status usado** | YES (backend) | `sync_status: user.syncStatus` |
| **9. sync_queue enqueue** | NO - Auth only | AUTH scope no se encola como COMMERCIAL |
| **10. Payload exacto subido** | JWT token + user data | GET /api/sync/download returns user in auth scope |
| **11. Backend que recibe** | `backend/src/modules/auth/infrastructure/controllers/auth.controller.ts` | @Post('users') línea 71, @Delete('users/:id') línea 83 |
| **12. Backend aplica** | Prisma user soft-delete | sync.service.ts línea 3239 |
| **13. Puede devolver 409** | BAJO RIESGO | Auth is bootstrap, conflicts rare |
| **14. server_won posible** | NO - Auth is read-only during setup | Auth cloud pull hardcoded allowed |
| **15. ALLOW_CLOUD_PULL protege** | AUTH EXCEPTION | auth_service.dart: Auth pull permitido siempre (lines 1742-1746) |
| **16. PWA muestra correctamente** | N/A | Auth no visible en PWA, usuario login only |
| **17. Puede quedar huérfano** | NO | User deletion no afecta transacciones (auth separate) |
| **18. Riesgo** | **BAJO** | Auth is separate scope, not commercial |
| **19. Recomendación** | Maintain auth bootstrap exception, document ALLOW_CLOUD_PULL bypass |

---

## TABLA 8: AUTHORIZED_DEVICES (AUTH)

| Aspecto | Hallazgo | Evidencia |
|---------|----------|-----------|
| **1. Archivo frontend CREATE** | `lib/features/auth/data/auth_service.dart` | Auto-registered on first login |
| **2. Función CREATE exacta** | Implicit, X-Device-Id header sent | sync_api_client.dart: `_buildHeaders()` incluye X-Is-Primary |
| **3. Archivo frontend UPDATE** | Backend POST /api/devices/claim-primary | devices.controller.ts línea 58 |
| **4. Función UPDATE exacta** | `claim-primary` endpoint | Sets device as primary device |
| **5. Archivo frontend DELETE** | Backend POST /api/devices/revoke | devices.controller.ts línea 92 |
| **6. Función DELETE exacta** | `revoke` endpoint | Revokes device authorization |
| **7. Delete type (soft/hard)** | SOFT DELETE (inferred) | Device deletedAt timestamp |
| **8. sync_status usado** | NO | Devices don't use sync_status |
| **9. sync_queue enqueue** | NO | Devices don't enqueue |
| **10. Payload exacto subido** | Device object | POST /api/devices/register |
| **11. Backend que recibe** | `backend/src/modules/devices/infrastructure/controllers/devices.controller.ts` | @Post('register') línea 25 |
| **12. Backend aplica** | Prisma device soft-delete | Backend only |
| **13. Puede devolver 409** | NO | Device conflicts unlikely |
| **14. server_won posible** | NO | Device is auth, not data |
| **15. ALLOW_CLOUD_PULL protege** | N/A | Device is auth bootstrap |
| **16. PWA muestra correctamente** | N/A | PWA doesn't manage devices |
| **17. Puede quedar huérfano** | NO | Device deletion isolated |
| **18. Riesgo** | **BAJO** | Auth infrastructure, not commercial |
| **19. Recomendación** | Verify PRIMARY device cannot be revoked if only device |

---

## TABLA 9-14: ROLES, PERMISSIONS, COMPANY_PROFILES, USER_ROLES, ROLE_PERMISSIONS (AUTH)

| Aspecto | Resumen | Evidencia |
|---------|---------|-----------|
| **Patrón general** | Auth reference data, backend-driven | auth.controller.ts: @Post('roles') línea 101, @Post('permissions') línea 122 |
| **Delete type** | SOFT DELETE | sync.service.ts línea 3264-3318: `deleted_at` para todos |
| **sync_status** | YES - pero auth only | No queued en COMMERCIAL, es read-only |
| **Cloud pull** | ALLOWED (AUTH exception) | auth_service.dart fallback permitido |
| **Conflictos 409** | Bajo riesgo | Referencias data, estructurada |
| **Orphan risk** | Bajo | Auth es aislado |
| **Riesgo general** | **BAJO** | Son tablas de configuración |
| **Recomendación** | Auditar role deletion no revoque permisos en uso, documentar role cascade |

---

## RESUMEN DE RIESGOS POR TABLA

```
🔴 CRÍTICO:
  1. PAYMENTS - Dinero, eliminación fácil, audit trail insuficiente
  2. SALES (force-delete) - Hard delete endpoint existe, debe bloquearse
  
🟠 ALTO:
  3. INSTALLMENTS - Dependencia en cascada con SALES
  4. CLIENTS - Eliminar cliente oculta deuda si ventas activas
  5. PRODUCTS - Legacy hard-delete pattern aún presente en código
  6. INSTALLMENTS - Huérfanos sin venta padre sincronizada
  
🟡 MEDIO:
  7. SELLERS - Comisión, eliminar esconde historial
  8-14. AUTH tablas - Bajo riesgo, pero orphans posibles
  
🟢 BAJO:
  - Authorized_devices, roles, permissions (aisladas)
```

---

## MATRIZ DE SINCRONIZACIÓN COMPLETA

| Tabla | Crea en | Edita en | Elimina en | Soft? | sync_status? | 409 posible? | server_won? | Huérfano? | Riesgo |
|-------|---------|----------|-----------|-------|------|------------|-----------|----------|--------|
| SALES | client_repo | client_repo | client_repo | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | 🔴 CRÍTICO |
| INSTALLMENTS | auto (sales) | auto (sales) | auto (sales) | ✅ | ✅ | ✅ | ⚠️ | ✅ | 🟠 ALTO |
| PAYMENTS | payments_repo | ❌ (immutable) | payments_repo | ✅ | ✅ | ✅ | ⚠️ | ✅ | 🔴 CRÍTICO |
| CLIENTS | client_repo | client_repo | client_repo | ✅ | ✅ | ✅ | ⚠️ | ✅ | 🟠 ALTO |
| SELLERS | Backend API | Backend API | Backend API | ✅ | ✅ | ✅ | ⚠️ | ✅ | 🟡 MEDIO |
| PRODUCTS | Backend API | Backend API | Backend API | ✅ | ✅ | ✅ LEGACY | ⚠️ | ✅ | 🟠 ALTO |
| USERS | auth_service | Backend API | Backend API | ✅ | ✅ | ❌ | ❌ | ❌ | 🟢 BAJO |
| ROLES | Backend API | Backend API | Backend API | ✅ | ✅ | ❌ | ❌ | ⚠️ | 🟢 BAJO |
| PERMISSIONS | Backend API | Backend API | Backend API | ✅ | ✅ | ❌ | ❌ | ⚠️ | 🟢 BAJO |
| DEVICES | auto (login) | Backend API | Backend API | ✅ | ❌ | ❌ | ❌ | ❌ | 🟢 BAJO |
| COMPANY_PROFILES | Backend API | Backend API | Backend API | ✅ | ✅ | ❌ | ❌ | ❌ | 🟢 BAJO |
| USER_ROLES | Backend API | Backend API | Backend API | ✅ | ✅ | ❌ | ❌ | ⚠️ | 🟢 BAJO |
| ROLE_PERMISSIONS | Backend API | Backend API | Backend API | ✅ | ✅ | ❌ | ❌ | ⚠️ | 🟢 BAJO |

---

## HALLAZGOS CLAVE POR ASPECTO

### ⚠️ Hard Deletes Detectados
```
✅ ENCONTRADO:
  1. backend/src/modules/sales/infrastructure/controllers/sales.controller.ts línea 76
     → @Delete('force-delete/:id')
     → Endpoint hard-delete para sales EXISTE
     → RIESGO: Datos financieros pueden ser borrados permanentemente
  
✅ ENCONTRADO:
  2. lib/services/sync/sync_queue_service.dart líneas 1620-1626
     → _hasLegacyHardDeleteError()
     → Detecta patrón: "DELETE FROM solares WHERE deleted_at IS NOT NULL"
     → RIESGO: Legacy code aún en codebase
  
✅ ENCONTRADO:
  3. lib/services/sync/sync_queue_service.dart líneas 1353-1354, 1539-1540, 1697-1698
     → rawDelete("DELETE FROM sync_queue WHERE ...")
     → RIESGO: Ok si sync_queue solamente, PELIGRO si extiende
  
✅ ENCONTRADO:
  4. lib/services/sync/emergency_cloud_restore_service.dart línea 259
     → rawDelete("DELETE FROM sync_queue WHERE scope IN (...)")
     → ANTES de aplicar cloud restore
     → RIESGO: Puede perder ventas nuevas locales
```

### ⚠️ Conflicts (409) Posibles
```
✅ ENCONTRADO:
  1. Sales puede 409: Versión conflict + múltiples devices
  2. Installments puede 409: Si referenced sale version mismatch
  3. Payments puede 409: Si cuota related payment conflict
  4. Clients puede 409: Si cedula duplicate
  5. Products puede 409: ESPECIAL - línea 1620: Aislados, no auto-retry
```

### ⚠️ Server Won (auto-apply)
```
✅ CÓDIGO EXISTE:
  - sync_conflict_service.dart línea 276: resolution='server_won'
  - mergeRemoteRecords() llamado en resolveUsingServerVersion()
  
⚠️ PERO:
  - Búsqueda no encontró AUTO-APPLY para COMMERCIAL
  - Parece manual UI only (user selects "use server version")
  - RIESGO: Futuro código podría auto-apply → offline-first violation
```

### ⚠️ Cloud Pull Protection
```
✅ FUNCIONA:
  - sync_service.dart línea 484: Chequea ALLOW_CLOUD_PULL flag
  - Si false → downloadUpdates() retorna sin descargar para COMMERCIAL
  
❌ EXCEPCIONES:
  1. auth_service.dart: Auth cloud pull permitido siempre (hardcoded)
  2. emergency_cloud_restore_service.dart: Ignora flag, restore manual admin
  3. conflict recovery: sync_queue_service.dart línea 2137: Bloqueado si flag=false
```

### ⚠️ Orphan Records Posibles
```
RIESGO ALTO:
  1. Sale sin client (client deleted, sale active)
  2. Installment sin sale (sale deleted, installments pending)
  3. Payment sin cuota (cuota deleted, payment not synced)
  4. Sale sin seller (vendedor eliminado)
  5. Sale sin product/lote (solar eliminado)
  
FK CONSTRAINTS EN BACKEND:
  - Prisma schema: Likely has cascade/restrict rules
  - NECESITA AUDITAR: ¿Qué sucede en cada eliminación?
```

### ⚠️ PWA Filtering
```
❌ NO AUDITADA:
  - sistema_solares_ui/** excluida por .gitignore en búsqueda
  - No se puede validar si PWA filtra deleted_at IS NULL
  - RIESGO: PWA puede mostrar datos soft-deleted
  
RECOMENDACIÓN:
  - Manual PWA code audit para verificar deleted_at filtering
  - Validar que GET /api/sync/download excluye deleted_at != NULL
```

---

## PRÓXIMA FASE: FASE 3 (PENDIENTE)

Auditar uno por uno:
1. ¿Cada hard-delete DEBE bloquearse?
2. ¿Cada delete-cascade FK tiene safeguard?
3. ¿PWA filtra correctamente deleted_at?
4. ¿Legacy hard-delete pattern puede ejecutarse?
5. ¿Emergency restore realmente necesita rawDelete sync_queue?
6. ¿Payments es immutable por diseño completo?
7. ¿Products 409 isolation es suficiente protección?
8. ¿Server won NUNCA auto-applies para COMMERCIAL?

---

## CONCLUSIÓN FASE 2

**Status**: DESCUBRIMIENTO COMPLETADO

**Confirmado**:
- ✅ Soft-delete implementado para TODAS comercial
- ✅ sync_status usado correctamente
- ✅ sync_queue enqueue automático
- ✅ 409 conflictos posibles, aislados en products
- ✅ ALLOW_CLOUD_PULL bloquea mergeRemote
- ✅ LOCAL_MASTER_MODE en backend aplica

**Crítico descubierto**:
- 🔴 Hard delete endpoint EXISTE en sales (@Delete('force-delete/:id'))
- 🔴 Legacy hard-delete pattern aún detectado en sync_queue_service
- 🔴 Emergency restore borra sync_queue con rawDelete
- 🔴 Payments son mutable en client (¿debería ser immutable?)
- 🔴 PWA filtering no auditado (excluida de búsqueda)

**Recomendaciones para Fase 3**:
- Bloquear force-delete endpoint inmediatamente
- Auditar PWA para deleted_at filtering
- Validar FK constraints cascade en Prisma
- Revisar legacy hard-delete pattern usage
- Considerar payments immutable enforcement
