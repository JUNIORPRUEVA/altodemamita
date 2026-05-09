# 🗺️ Roadmap Completo - Limpieza Nube (Fases 1-6)

---

## 📍 Estado Actual: Fases 1-3 ✅ LISTAS

```
FASE 1: BACKUP OBLIGATORIO ✅ COMPLETADA
├─ Script: src/tasks/cloud-audit.ts
├─ Output: backups/cloud/postgresql_backup_*.sql
└─ Status: Funcional y probado

FASE 2: AUDITORÍA NUBE VS LOCAL ✅ COMPLETADA
├─ Script: src/tasks/cloud-audit.ts (mismo)
├─ Output: Conteos por tabla, diferencias, orphaned records
└─ Status: Funcional y probado

FASE 3: PROPUESTA DE LIMPIEZA ✅ COMPLETADA
├─ Script: src/tasks/cloud-audit.ts (mismo)
├─ Output: audit-report-*.json con recomendaciones
└─ Status: Funcional y probado

FASE 4: LIMPIEZA SEGURA ⏳ EN DESARROLLO
├─ Script: src/tasks/cloud-cleanup-execute.ts (POR CREAR)
├─ Input: audit-report-*.json (del usuario)
├─ Output: Registros eliminados/soft-deleted
└─ Status: Diseño completado, codificación pendiente

FASE 5: RE-SINCRONIZACIÓN LOCAL → NUBE ⏳ EN DESARROLLO
├─ Script: src/tasks/cloud-resync-from-local.ts (POR CREAR)
├─ Input: Datos validados en local
├─ Output: PostgreSQL actualizado desde local
└─ Status: Diseño completado, codificación pendiente

FASE 6: VERIFICACIÓN FINAL ⏳ EN DESARROLLO
├─ Script: src/tasks/cloud-verify-sync.ts (POR CREAR)
├─ Input: Estado después de limpieza y re-sync
├─ Output: Reporte final de paridad
└─ Status: Diseño completado, codificación pendiente
```

---

## 🎯 Fase 1: Backup Obligatorio ✅

**Status: COMPLETADA**

### Objetivo
Crear un dump SQL verificado de PostgreSQL nube ANTES de cualquier modificación.

### Lo que hace
```bash
pg_dump -h HOST -U USER -d DATABASE > backup_YYYY-MM-DD_HH-mm-ss.sql
```

### Validaciones
- [x] Archivo creado en disco
- [x] Tamaño > 0 bytes
- [x] Ubicado en `backups/cloud/`
- [x] Timestamp grabado
- [x] Continúa solo si todo está bien

### Output
```
✅ Backup completado exitosamente
   Archivo: postgresql_backup_2026-05-08_14-30-45.sql
   Tamaño: 2.45 MB
   Ruta: /path/to/backups/cloud/postgresql_backup_2026-05-08_14-30-45.sql
```

### Usar si algo falla
```bash
# Restaurar base de datos desde backup
psql -h HOST -U USER -d DATABASE < postgresql_backup_2026-05-08_14-30-45.sql
```

---

## 🔍 Fase 2: Auditoría Nube vs Local ✅

**Status: COMPLETADA**

### Objetivo
Comparar ambas bases de datos y generar reporte de diferencias.

### Lo que analiza
- Conteos de registros activos y eliminados
- Registros solo en nube
- Registros solo en local
- Registros coincidentes (en ambas)
- Registros huérfanos (sin relación padre)
- Posibles duplicados (mismo documentId)
- Problemas de integridad

### Tablas analizadas
```
clients      ↔ clientes
sellers      ↔ vendedores
products     ↔ solares
sales        ↔ ventas
payments     ↔ pagos
installments ↔ cuotas
```

### Output
```
📈 CONTEOS POR TABLA:
  Clientes: NUBE 50 | LOCAL 40 | Diferencia: 10
  Vendedores: NUBE 12 | LOCAL 10 | Diferencia: 2
  ...

⚠️ REGISTROS HUÉRFANOS:
  🔴 2 pagos sin venta
  🔴 1 cuota sin venta

🔎 POSIBLES DUPLICADOS:
  Tabla: clients | Identificador: documentId: 123456 | Cantidad: 2
```

---

## 📋 Fase 3: Propuesta de Limpieza ✅

**Status: COMPLETADA**

### Objetivo
Proponer qué limpiar basado en auditoría (SIN EJECUTAR).

### Lo que recomienda
- Qué registros borrar por tabla
- Cantidad exacta de registros por tabla
- Motivo de cada eliminación
- Relaciones y dependencias
- Orden correcto de eliminación
- Evaluación de riesgo
- Método (soft-delete vs hard-delete)

### Ejemplo de propuesta
```json
{
  "recordsToDelete": [
    {
      "table": "clients",
      "reason": "Clientes que existen solo en nube",
      "count": 10,
      "preferSoftDelete": true,
      "dependencies": ["sales"]
    },
    {
      "table": "payments",
      "reason": "Pagos sin venta asociada (huérfanos)",
      "count": 2,
      "preferSoftDelete": false
    }
  ],
  "dependencyOrder": ["payments", "installments", "sales", "clients", "sellers", "products"],
  "riskAssessment": {
    "level": "medium",
    "warnings": ["2 pagos huérfanos sin venta"],
    "recommendations": ["Usar soft-delete", "Respetar orden de dependencias"]
  }
}
```

### Evaluación de riesgo
- 🟢 **LOW**: < 10 registros, sin relaciones complejas
- 🟠 **MEDIUM**: 10-100 registros, algunas relaciones
- 🔴 **HIGH**: > 100 registros, relaciones críticas o datos sensibles

---

## 🧹 Fase 4: Limpieza Segura ⏳ (POR IMPLEMENTAR)

**Status: EN DISEÑO**

### Objetivo (planned)
Ejecutar DELETE/UPDATE basado en propuesta de Fase 3 respetando dependencias.

### Flow planeado
```
1. Leer audit-report-*.json (del usuario)
2. Validar que el usuario ha revisado y aprobado
3. Conectar a PostgreSQL nube
4. INICIAR TRANSACCIÓN
5. Para cada tabla en dependencyOrder:
   a. Obtener recordIds a eliminar
   b. Verificar que registros existen
   c. DELETE o UPDATE deleted_at (según propuesta)
   d. Log resultado
6. Si todo OK: COMMIT
7. Si hay error: ROLLBACK (restaurar desde backup)
8. Generar reporte de limpieza
```

### Lo que hará
- ✓ Eliminar registros solo en nube
- ✓ Marcar como eliminados (soft-delete) registros relacionados
- ✓ Respetar orden: payments → installments → sales → clients → sellers → products
- ✓ Mantener transacciones ACID
- ✓ Hacer logging completo
- ✓ Permitir rollback

### Lo que NO hará
- ✗ Modificar registros sin estar en la propuesta
- ✗ Cambiar datos de valores
- ✗ Ignorar foreign keys
- ✗ Ejecutar sin revisión previa
- ✗ Borrar sin backup verificado

### Validaciones Fase 4
```
PRE-LIMPIEZA:
  ✓ Backup existe y es válido
  ✓ Usuario ha revisado audit-report-*.json
  ✓ Usuario ha dado aprobación explícita
  ✓ Especificar qué registros se van a borrar (confirmación)

DURANTE:
  ✓ Transacción activa
  ✓ Log cada operación
  ✓ Verificar FK constraints
  ✓ Monitorear progreso

POST-LIMPIEZA:
  ✓ Verificar conteos posteriores
  ✓ Validar integridad referencial
  ✓ Generar reporte de cambios
```

### Script planeado
```typescript
// src/tasks/cloud-cleanup-execute.ts
// Input: reportPath (json generado en Fase 3)
// Input: approvalToken (string que el usuario debe copiar para confirmar)
// Output: cleanup-execution-YYYY-MM-DD_HH-mm-ss.json
```

---

## 📥 Fase 5: Re-sincronización Local → Nube ⏳ (POR IMPLEMENTAR)

**Status: EN DISEÑO**

### Objetivo (planned)
Sincronizar datos desde PC local (MASTER) a Nube (MIRROR) después de limpieza.

### Flow planeado
```
1. Conectar a SQLite local (lectura)
2. Conectar a PostgreSQL nube (escritura)
3. Para cada tabla en orden:
   clients → sellers → products → sales → installments → payments
   
   a. Leer todos los registros de local
   b. UPSERT en nube (por sync_id):
      - INSERT si no existe
      - UPDATE si existe
      - Preservar sync_status = 'synced'
   c. Marcar deleted_at en nube si se eliminó en local
   d. Log resultados

4. Bloquear nube → local (ya configurado)
5. Generar reporte de sincronización
```

### Lo que hará
- ✓ Subir clientes desde local a nube
- ✓ Subir vendedores desde local a nube
- ✓ Subir solares desde local a nube
- ✓ Subir ventas desde local a nube
- ✓ Subir cuotas desde local a nube
- ✓ Subir pagos desde local a nube
- ✓ Respetar dependencias (padre antes de hijo)
- ✓ UPSERT (no duplicar)
- ✓ Preservar sync_id
- ✓ Bloquear nube → local

### Lo que NO hará
- ✗ Sincronizar nube → local (bloqueado)
- ✗ Modificar lo que no esté en local
- ✗ Permitir cambios en nube durante sync
- ✗ Alterar estructuras de datos

### Script planeado
```typescript
// src/tasks/cloud-resync-from-local.ts
// Input: dryRun (true para simular, false para ejecutar)
// Output: sync-execution-YYYY-MM-DD_HH-mm-ss.json
```

---

## ✔️ Fase 6: Verificación Final ⏳ (POR IMPLEMENTAR)

**Status: EN DISEÑO**

### Objetivo (planned)
Validar que nube es ahora un espejo idéntico de local.

### Flow planeado
```
1. Ejecutar auditoría nuevamente (como Fase 2)
2. Comparar nuevamente conteos
3. Verificar que:
   - Nube == Local (para registros activos)
   - Sin registros huérfanos
   - Sin datos inconsistentes
   - sync_status correcto
   - Integridad referencial OK

4. Validar balances financieros:
   - Suma pagos == suma cuotas
   - Ventas have cuotas relacionadas
   - Clientes have ventas relacionadas
   
5. Generar reporte final de paridad
```

### Lo que hará
- ✓ Repetir auditoría (Fase 2)
- ✓ Comparar conteos post-limpieza
- ✓ Validar relaciones intactas
- ✓ Verificar sumas y balances
- ✓ Confirmar que local == nube
- ✓ Generar certificado de paridad

### Lo que NO hará
- ✗ Hacer cambios
- ✗ Limpiar histórico
- ✗ Modificar datos

### Output esperado
```
✅ VERIFICACIÓN FINAL - PARIDAD CONFIRMADA

LOCAL = NUBE ✓

  Clientes: 40 = 40 ✓
  Vendedores: 10 = 10 ✓
  Solares: 8 = 8 ✓
  Ventas: 25 = 25 ✓
  Cuotas: 180 = 180 ✓
  Pagos: 95 = 95 ✓

Integridad: ✓ OK
Balances: ✓ OK
Relaciones: ✓ OK

Estado: SINCRONIZADO Y VERIFICADO
```

### Script planeado
```typescript
// src/tasks/cloud-verify-sync.ts
// Input: ninguno
// Output: final-verification-YYYY-MM-DD_HH-mm-ss.json
```

---

## 🗓️ Timeline Estimado

### Ya completado
- ✅ Fase 1-3: Backup, Auditoría, Propuesta
  - Horas: ~4-6 (incluindo análisis, diseño, codificación)
  - Complejidad: Alta (SQLite + PostgreSQL, sincronización metadata)

### Por completar (estimado)
- ⏳ Fase 4 (Limpieza): ~2-3 horas
  - Transacciones, rollback, validaciones, logging
  
- ⏳ Fase 5 (Re-sync): ~2-3 horas
  - UPSERT logic, dependency order, verificación

- ⏳ Fase 6 (Verificación): ~1 hora
  - Repetir auditoría, comparar, generar reporte final

### Total para completar todo
- **Estimado**: 5-7 horas de codificación
- **Real**: Dependerá de bugs y cambios scope

---

## 🚀 Cómo Proceder

### Hoy (Usuario)
1. ✅ Ejecutar Fase 1-3: `npm run task:audit:cloud-cleanup`
2. ✅ Revisar `audit-report-*.json`
3. ✅ Validar que las diferencias son esperadas
4. ✅ Guardar reporte

### Cuando esté listo para limpiar (Usuario)
1. ⏳ (Esperar Fase 4 implementación)
2. ⏳ Ejecutar Fase 4: `npm run task:cleanup:execute` (después disponible)
3. ⏳ Proporcionar archivo de reporte y token de aprobación

### Después de limpieza (Usuario)
1. ⏳ Ejecutar Fase 5: `npm run task:resync:local-to-cloud` (después disponible)
2. ⏳ Esperar re-sincronización
3. ⏳ Ejecutar Fase 6: `npm run task:verify:final-sync` (después disponible)
4. ⏳ Confirmar paridad

---

## 📞 Contacto para Fases 4-6

Para acelerar implementación, incluir:
- ✓ Reporte de auditoría (Fase 3)
- ✓ Descripción de qué necesita limpiar
- ✓ Calendario disponible para testing
- ✓ Acceso a sistemas (credentials)

---

**Actualizado**: 2026-05-08  
**Estado**: Fases 1-3 Completadas ✅ | Fases 4-6 Diseñadas 📋  
**Próximo milestone**: Implementar Fase 4 (Limpieza Segura)
