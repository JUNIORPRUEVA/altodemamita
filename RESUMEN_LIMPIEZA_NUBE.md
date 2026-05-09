# 🚀 LIMPIEZA CONTROLADA DE NUBE - RESUMEN EJECUTIVO

## Estado: ✅ FASES 1-3 LISTAS (Backup + Auditoría + Propuesta)

---

## ¿Qué Hice?

### Fase 1: Backup Obligatorio ✅
**Script automático que:**
- Crea dump SQL completo de PostgreSQL nube
- Valida que el archivo exista y tenga contenido
- Guarda con timestamp: `postgresql_backup_2026-05-08_14-30-45.sql`
- **Requisito**: NO continúa si el backup falla

### Fase 2: Auditoría Nube vs Local ✅
**Script que compara ambas bases de datos:**
- Cuenta registros por tabla (clientes, vendedores, solares, ventas, pagos, cuotas)
- Identifica **registros solo en nube** (candidatos a borrar)
- Identifica **registros solo en local** (falta sincronizar)
- Detecta **registros huérfanos** (pagos sin venta, cuotas sin venta, etc.)
- Detecta **posibles duplicados** (mismo cédula, múltiples IDs)
- Verifica **integridad de datos** (relaciones rotas, soft-deleted)
- Genera **reporte JSON completo** con todas las métricas

### Fase 3: Propuesta de Limpieza ✅
**Script que propone qué limpiar:**
- Muestra cuántos registros se borrarían por tabla
- Propone **orden de limpieza** (respetando dependencias)
- Calcula **riesgo** (alto/medio/bajo)
- Advierte sobre **problemas críticos**
- Recomienda **usar soft-delete o hard-delete**
- **NO BORRA NADA YET** - solo propone

---

## Cómo Ejecutar

### Paso 1: Preparar ambiente
```bash
cd backend
npm install  # Instalar dependencias
```

### Paso 2: Configurar credenciales PostgreSQL
Asegúrate de que el archivo `.env` tiene:
```
DATABASE_URL=postgresql://user:password@host:5432/database_name?schema=public
```

### Paso 3: Ejecutar auditoría
```bash
npm run task:audit:cloud-cleanup
```

### Paso 4: Revisar reporte
El script genera:
1. **Salida en consola**: Resumen ejecutivo y propuesta
2. **Archivo JSON**: `audit-reports/audit-report-YYYY-MM-DD_HH-mm-ss.json`
3. **Backup SQL**: `backups/cloud/postgresql_backup_YYYY-MM-DD_HH-mm-ss.sql`

---

## Ejemplo de Salida

```
╔════════════════════════════════════════════════════════════╗
║       📊 REPORTE DE AUDITORÍA - NUBE VS LOCAL              ║
║       Fases 1-3: Backup + Auditoría + Propuesta           ║
╚════════════════════════════════════════════════════════════╝

📦 FASE 1: ESTADO DEL BACKUP
────────────────────────────────────────────────────────────
  Estado: ✅ EXITOSO
  Archivo: postgresql_backup_2026-05-08_14-30-45.sql
  Tamaño: 2.45 MB
  Ubicación: /ruta/al/backup.sql

📈 FASE 2: CONTEOS POR TABLA
────────────────────────────────────────────────────────────

  Clientes
    NUBE:  50       registros activos | 3 eliminados
    LOCAL: 40       registros activos | 2 eliminados
    ⚠️  Diferencia: 10 registros (↑ más en nube)

  Vendedores
    NUBE:  12       registros activos | 1 eliminado
    LOCAL: 10       registros activos | 0 eliminados
    ⚠️  Diferencia: 2 registros (↑ más en nube)

  [Más tablas...]

⚠️  REGISTROS HUÉRFANOS DETECTADOS
────────────────────────────────────────────────────────────
  🔴 2 pagos sin venta asociada
  🔴 1 cuota sin venta asociada

🧹 FASE 3: PROPUESTA DE LIMPIEZA
────────────────────────────────────────────────────────────

  Total de registros en NUBE: 367
  Total de registros en LOCAL: 289

  📋 CANDIDATOS PARA LIMPIEZA:

    • clientes
      Motivo: Clientes que existen solo en nube
      Cantidad: 10 registros
      Método: Soft-delete (marked deleted)
      Dependencias: sales

    • vendedores
      Motivo: Vendedores que existen solo en nube
      Cantidad: 2 registros
      Método: Soft-delete (marked deleted)
      Dependencias: sales

    • pagos
      Motivo: Pagos sin venta asociada (huérfanos)
      Cantidad: 2 registros
      Método: Hard-delete (eliminar físicamente)

  🔗 ORDEN RECOMENDADO DE LIMPIEZA:
     payments → installments → sales → clients → sellers → products

🚨 EVALUACIÓN DE RIESGO
────────────────────────────────────────────────────────────

  Nivel de Riesgo: 🟠 MEDIUM

  💡 RECOMENDACIONES:
     • Hacer backup ANTES de ejecutar cualquier limpieza (ya hecho)
     • Ejecutar limpieza en orden de dependencias: payments → installments → sales → clients → sellers → products
     • Usar soft-delete (deleted_at) preferentemente
     • Verificar que local está actualizado antes de limpiar

═══════════════════════════════════════════════════════════════
✅ AUDITORÍA COMPLETADA - ANÁLISIS DE SOLO LECTURA
═══════════════════════════════════════════════════════════════

⚠️  IMPORTANTE:
   • NO SE HA MODIFICADO NADA EN NINGUNA BASE DE DATOS
   • El backup está disponible y verificado
   • Revisar este reporte antes de proceder a limpieza
```

---

## Lo que el Script HACE
✅ Crea backup PostgreSQL  
✅ Valida backup  
✅ Conecta a PostgreSQL nube (lectura)  
✅ Conecta a SQLite local (lectura)  
✅ Analiza datos  
✅ Genera reporte  

## Lo que el Script NO HACE
❌ NO modifica nada en PostgreSQL  
❌ NO modifica nada en SQLite  
❌ NO ejecuta DELETE ni UPDATE  
❌ NO elimina soft-deleted  
❌ NO sincroniza datos  

---

## Requisitos Técnicos

### Instalados:
- [x] Node.js
- [x] Prisma (backend)
- [x] PostgreSQL credentials (DATABASE_URL)

### Necesarios:
- [ ] `pg_dump` en PATH (PostgreSQL client tools)
- [ ] Base de datos local accesible (`sistema_solares.db`)

### Cómo verificar:
```bash
# PostgreSQL client disponible
pg_dump --version

# Base de datos local
dir %APPDATA%\sistema_solares\sistema_solares.db
```

---

## Después de Revisar el Reporte

### Si todo se ve bien:
1. ✅ Guardar el reporte JSON (para referencia)
2. ✅ Revisar con el equipo
3. ✅ Obtener aprobación explícita
4. ⏳ **Fase 4**: Ejecutar limpieza (script en desarrollo)

### Si hay problemas:
1. ⚠️ Hacer correcciones en local si aplica
2. ⚠️ Re-ejecutar auditoría
3. ⚠️ Repetir hasta que esté bien

### Nunca:
- ❌ Ejecutar limpieza sin revisar reporte
- ❌ Modificar nube manualmente
- ❌ Perder el backup
- ❌ Permitir nube → local durante limpieza

---

## Lo Que Falta (Fases 4-6)

### 🔄 Fase 4: Limpieza Segura (en desarrollo)
Script que ejecutará DELETE/UPDATE basado en reporte de Fase 3:
- Borrar en orden correcto (respetando dependencias)
- Usar soft-delete cuando sea apropiado
- Loguear cada operación
- Permitir rollback si algo falla

### 📥 Fase 5: Re-sincronización Local → Nube
Script que sincronizará desde PC (master) a Nube (mirror):
- Subir: clientes, vendedores, solares, ventas, cuotas, pagos
- **Bloquear**: nube → local
- Verificar integridad después

### ✔️ Fase 6: Verificación Final
Script que comparará nuevamente nube vs local:
- Validar paridad de conteos
- Verificar relaciones y balances
- Confirmar éxito
- Desactivar bloqueos si aplica

---

## Archivos Creados

```
backend/
├── src/tasks/
│   └── cloud-audit.ts                    ← Script principal de auditoría
├── scripts/
│   └── audit-cloud-data.js               ← Runner (ejecutor)
├── CLOUD_AUDIT_GUIDE.md                  ← Guía técnica completa
├── audit-reports/                        ← Reportes generados
│   └── audit-report-YYYY-MM-DD_HH-mm-ss.json
└── backups/cloud/                        ← Backups PostgreSQL
    └── postgresql_backup_YYYY-MM-DD_HH-mm-ss.sql
```

---

## 🎯 Resumen en 30 Segundos

1. **¿Qué es?**: Script que audita diferencias entre nube (PostgreSQL) y local (SQLite)
2. **¿Qué hace?**: Crea backup, compara datos, propone limpieza
3. **¿Es seguro?**: Sí - solo lectura, backup verificado, user approval required
4. **¿Cómo ejecuto?**: `npm run task:audit:cloud-cleanup`
5. **¿Qué esperar?**: Reporte con conteos, diferencias, riesgos, recomendaciones
6. **¿Después qué?**: Revisar reporte, aprobar, ejecutar Fases 4-6 (en desarrollo)

---

**Última actualización**: 2026-05-08  
**Estado**: ✅ LISTO PARA USAR - Fases 1-3 completas  
**Próximo paso**: Ejecutar auditoría y revisar reporte
