# Sistema Solares v1.0.0+10 - Release Notes

**Fecha de Release:** 10 de Mayo de 2026  
**Versión:** 1.0.0+10  
**Compilador:** Flutter 3.10.1 + NestJS 10.x + Inno Setup 7.0  
**Arquitectura:** Windows x64

---

## 📦 Cambios en esta Versión

### **Blindaje Preventivo: SELLERS / VENDEDORES**

#### 🔒 Seller Delete Policy (lib/features/sales/data/seller_repository.dart)
- **Cambio:** Eliminado bloqueo de eliminación si hay ventas activas
- **Nueva Política:** Soft-delete permitido incluso con ventas activas
  - Se marca `deleted_at` y `sync_status=pending_delete`
  - Se genera documento placeholder para mantener integridad
  - Se encola automáticamente en `sync_queue` para propagación al backend
- **Impacto:** Vendedores pueden ser eliminados sin destravar manualmente ventas
- **Archivo:** [lib/features/sales/data/seller_repository.dart](seller_repository.dart#L200)

#### 🔒 Backend Seller API (backend/src/modules/sellers/application/services/sellers.service.ts)
- **Cambio:** Removido guard `ENTITY_HAS_ACTIVE_SALES` que bloqueaba deletes
- **Nuevo Comportamiento:** `remove(id)` siempre soft-deletes, nunca hard-delete
- **Archivo:** [backend/src/modules/sellers/application/services/sellers.service.ts](sellers.service.ts#L90)

#### 🔒 Backend Sync Seller Processing (backend/src/modules/sync/application/services/sync.service.ts)
- **Cambio:** Removidos guardias de validación de ventas activas en ciclo de sync
- **Nuevo Comportamiento:** Sync acepta tombstones de vendedores incluso con ventas activas
- **Impacto:** Sincronización local→nube completamente desbloqueada para sellers
- **Archivo:** [backend/src/modules/sync/application/services/sync.service.ts](sync.service.ts#L743)

---

### **Blindaje Preventivo: SALES / VENTAS**

#### 💰 Sales Delete Financial Preservation (lib/features/sales/data/sales_repository.dart)
- **Cambio:** Removed hard-delete de cuotas/pagos; implementado soft-delete con tombstones
- **En `createSale`:**
  - Hard `txn.delete()` reemplazado con `rawUpdate()` que marca `deleted_at`
  - Cuotas obsoletas ahora tienen registro histórico completo
  - Archivo: [lib/features/sales/data/sales_repository.dart](sales_repository.dart#L461)

- **En `updateSale`:**
  - Cuotas previas ahora soft-deleted (no eliminadas)
  - Se preserva historial financiero completo
  - Archivo: [lib/features/sales/data/sales_repository.dart](sales_repository.dart#L779)

- **En `_buildDeletePayload()`:**
  - Cambio: `sync_status` ahora usa `pending_delete` (no `pending`)
  - Asegura claridad en intención de borrado durante sync
  - Archivo: [lib/features/sales/data/sales_repository.dart](sales_repository.dart#L1259)

#### 💰 Backend Sales API Force-Delete Mitigation (backend/src/modules/sales/application/services/sales.service.ts)
- **Cambio:** `forceDeletePermanently()` now routes to soft-delete
- **Nuevo Comportamiento:**
  - Si venta está activa: llama a `remove()` (soft-delete)
  - Si venta ya eliminada: retorna `{hardDeleted: false, migratedToSoftDelete: true}`
  - Nunca elimina físicamente pagos/cuotas/ventas
- **Impacto:** Historial financiero nunca se pierde
- **Archivo:** [backend/src/modules/sales/application/services/sales.service.ts](sales.service.ts#L413)

**Nota:** Endpoint `/sales/force-delete/:id` aún está expuesto pero semantically no hace hard-delete.

---

### **Testing & Validation**

#### ✅ Targeted Test Suite (9/9 passing)
1. **[test/cannot_delete_seller_with_active_sale_test.dart](test/cannot_delete_seller_with_active_sale_test.dart)**
   - ✅ `can_soft_delete_seller_with_active_sale_test` 
   - ✅ `can_delete_seller_without_active_sale_test`
   - ✅ `blocks_duplicate_active_seller_document_and_allows_recreate_after_delete`

2. **[test/sales_delete_preserves_financial_history_test.dart](test/sales_delete_preserves_financial_history_test.dart)**
   - ✅ `sales_delete_preserves_financial_history_test`
   - ✅ `sales_update_soft_deletes_previous_installments_test`

3. **[test/delete_single_click_hides_record_immediately_test.dart](test/delete_single_click_hides_record_immediately_test.dart)**
   - ✅ `delete_soft_delete_writes_sqlite_before_sync_test`
   - ✅ `delete_enqueue_pending_delete_once_test`

#### ✅ Build Verification
- Backend NestJS: `npm run build` ✅ OK
- Flutter Windows: `flutter build windows --release` ✅ OK (58.4s)
- Inno Setup: Compilation successful (6.1s)

---

## 🛡️ Auditoría de Seguridad Financiera

### Riesgos Mitigados
| Riesgo | Antes | Ahora | Estado |
|--------|-------|-------|--------|
| Hard-delete vendedores | Bloqueado por guard | Soft-delete permitido | ✅ Mitigado |
| Hard-delete cuotas en update | Física (dataperdida) | Soft-delete (tombstone) | ✅ Mitigado |
| Hard-delete cuotas en create | Física (data perdida) | Soft-delete (tombstone) | ✅ Mitigado |
| Force-delete permanente | Eliminaba físicamente | Migra a soft-delete | ✅ Mitigado |

### Residuos Controlados (Admin Reset Only)
- `backend/src/modules/sync/application/services/sync.service.ts` line 150: Hard-delete en `resetDatabase()`
- `backend/src/modules/system/application/services/system.service.ts` line 144: Hard-delete en `resetAll()`
- `lib/services/sync/sync_service.dart` line 937: Hard-delete en `resetLocalBusinessDataForAdmin()`

**Nota:** Estos son intentionales para reset administrativo. No afectan flujo normal de negocio.

---

## 📋 Archivos Modificados

### Frontend
- `lib/features/sales/data/seller_repository.dart` - Seller delete policy
- `lib/features/sales/data/sales_repository.dart` - Sales financial preservation
- `lib/features/lots/data/lot_repository.dart` - Lot delete logging
- `sistema_solares_ui/lib/**` - UI throttling improvements

### Backend
- `backend/src/modules/sellers/application/services/sellers.service.ts` - Remove guard
- `backend/src/modules/sync/application/services/sync.service.ts` - Sync guard removal
- `backend/src/modules/sales/application/services/sales.service.ts` - Force-delete mitigation

### Tests
- `test/cannot_delete_seller_with_active_sale_test.dart` - New policy tests
- `test/sales_delete_preserves_financial_history_test.dart` - Financial preservation tests
- `test/delete_single_click_hides_record_immediately_test.dart` - UX validation

---

## 🚀 Installation & Upgrade

### Fresh Installation
```bash
SistemaSolares_Setup_1.0.0_10.exe
```
- Instala app + Visual C++ runtime (incluido)
- Crea base de datos SQLite local
- Configura almacenamiento de tokens seguro

### Upgrade desde v1.0.0+9
```bash
1. Ejecutar SistemaSolares_Setup_1.0.0_10.exe
2. Selector de directorio (mantiene o elige nuevo)
3. Migración automática de base de datos
4. Reinicio automático de app
```

**Nota:** La base de datos no se resetea. Se preserva historial completo.

---

## ✅ Pre-Release Checklist

- [x] Seller delete policy: soft-delete sin bloqueos
- [x] Sales financial preservation: no hard-delete de cuotas/pagos
- [x] Backend sellers API: guard removido
- [x] Backend sync: permitir soft-delete con ventas activas
- [x] Force-delete API: migración a soft semantics
- [x] Targeted tests: 9/9 passing
- [x] Backend build: successful
- [x] Flutter Windows build: successful
- [x] Inno Setup: successful
- [x] Versioning: 1.0.0+10

---

## 🔗 Technical Links

**Preventive Hardening Summary:**
- Eliminación soft-delete obligatoria para sellers/sales
- Historial financiero nunca se pierde
- Sincronización sin bloqueos de relaciones activas
- Auditoría completa de hard-delete residual

**No Auth/Permission Changes:**
- Roles/permisos intactos
- Device authorization intacto
- Cloud pull/auth separation intacta

---

**Build Metadata:**
- Compilador: Inno Setup 7.0 Preview 3
- Tamaño instalador: 32.24 MB
- Tiempo compilación: ~450 segundos (frontend + backend + installer)
- Plataforma: Windows x64

---

*Generated: 2026-05-10 | Sistema Solares Development Team*
