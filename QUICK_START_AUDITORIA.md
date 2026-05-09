# ⚡ QUICK START - Ejecuta la Auditoría Ahora

## 🎯 En 5 Minutos

### Paso 1: Preparar ambiente (1 min)
```bash
cd backend
npm install  # Si aún no lo hiciste
```

### Paso 2: Verificar PostgreSQL cliente (30 seg)
```bash
pg_dump --version
# Debe responder algo como: pg_dump (PostgreSQL) 13.0
# Si no funciona: instala PostgreSQL client tools desde https://www.postgresql.org/download/windows/
```

### Paso 3: Verificar DATABASE_URL (30 seg)
```bash
# Verificar que backend\.env tiene:
# DATABASE_URL=postgresql://user:password@host:5432/database?schema=public

# O las variables de entorno DB_HOST, DB_PORT, etc.
cat .env | grep DATABASE_URL
# Si está vacío: agregarla ahora
```

### Paso 4: Verificar base de datos local (30 seg)
```bash
# Windows PowerShell - buscar sistema_solares.db
Test-Path "$env:APPDATA\sistema_solares\sistema_solares.db"
# Debe responder: True
```

### Paso 5: Ejecutar auditoría (2 min)
```bash
npm run task:audit:cloud-cleanup
```

---

## 📊 Espera esto en Consola

```
╔════════════════════════════════════════════════════════════╗
║       📊 REPORTE DE AUDITORÍA - NUBE VS LOCAL              ║
╚════════════════════════════════════════════════════════════╝

📦 FASE 1: ESTADO DEL BACKUP
────────────────────────────────────────────────────────────
  Estado: ✅ EXITOSO
  Archivo: postgresql_backup_2026-05-08_14-30-45.sql
  Tamaño: 2.45 MB

📈 FASE 2: CONTEOS POR TABLA
────────────────────────────────────────────────────────────
  Clientes
    NUBE:  50       registros activos | 3 eliminados
    LOCAL: 40       registros activos | 2 eliminados
    ⚠️  Diferencia: 10 registros (↑ más en nube)
    
[... más tablas ...]

🧹 FASE 3: PROPUESTA DE LIMPIEZA
────────────────────────────────────────────────────────────
  📋 CANDIDATOS PARA LIMPIEZA:
    • clientes: 10 registros
    • vendedores: 2 registros

✅ AUDITORÍA COMPLETADA
═══════════════════════════════════════════════════════════════

📄 ARCHIVOS GENERADOS:
   • Reporte JSON: audit-reports/audit-report-YYYY-MM-DD_HH-mm-ss.json
   • Backup SQL: backups/cloud/postgresql_backup_YYYY-MM-DD_HH-mm-ss.sql
```

---

## ✅ Después de Ejecutar

### 1. Revisar Reporte (2 min)
Abrir el archivo JSON generado:
```bash
# Windows
start audit-reports\audit-report-2026-05-08_14-30-45.json

# O abrir con editor
code audit-reports\audit-report-2026-05-08_14-30-45.json
```

### 2. Buscar estos keys en JSON
```json
{
  "cloudCounts": {
    "clients": 50,
    "sellers": 12,
    "products": 8,
    "sales": 25,
    "payments": 95,
    "installments": 180
  },
  "localCounts": {
    "clients": 40,
    ...
  },
  "cleanupProposal": {
    "recordsToDelete": [
      { "table": "clients", "count": 10, ... }
    ],
    "riskAssessment": { "level": "medium" }
  }
}
```

### 3. Validar estas cosas
- [ ] `backupStatus.success` = `true`
- [ ] Backup file exists en `backups/cloud/`
- [ ] Conteos nube vs local son razonables
- [ ] No hay errores en console output
- [ ] Risk assessment no es "critical"

---

## ❌ Si Algo Falla

### Error: "DATABASE_URL no configurada"
```bash
# Abrir backend\.env
# Agregar:
DATABASE_URL=postgresql://user:password@host:5432/database?schema=public
```

### Error: "pg_dump: comando no encontrado"
```bash
# Descargar e instalar PostgreSQL Client Tools
# https://www.postgresql.org/download/windows/
# O agregar a PATH si ya está instalado
```

### Error: "Base de datos local... no encontrada"
```bash
# Cerrar Flutter desktop (usa sistema_solares.db)
# Buscar:
# - %APPDATA%\sistema_solares\sistema_solares.db
# - %LOCALAPPDATA%\sistema_solares\sistema_solares.db
# - Copiar a %APPDATA%\sistema_solares\ si es necesario
```

### Error: "ECONNREFUSED"
```bash
# Verificar que PostgreSQL nube está disponible
# Verificar que DATABASE_URL es correcto
psql -h HOST -U USER -d DATABASE -c "SELECT 1"
```

---

## 🎯 Resumen

**¿Qué hace?**
- Crea backup de PostgreSQL nube
- Compara nube vs local
- Propone qué limpiar

**¿Es seguro?**
- Sí, solo lectura
- Backup verificado
- No modifica nada

**¿Cuánto tarda?**
- 2-10 minutos

**¿Qué sigue?**
- Revisar reporte
- Si apruebas, esperar Fase 4 (limpieza)

---

## 📚 Documentación Completa

Si necesitas más detalles:
- `CLOUD_AUDIT_GUIDE.md` - Guía técnica completa
- `RESUMEN_LIMPIEZA_NUBE.md` - Resumen ejecutivo
- `PRE_EJECUCION_CHECKLIST.md` - Checklist de verificación
- `ROADMAP_LIMPIEZA_FASES_1_A_6.md` - Plan completo de las 6 fases

---

## 🚀 ¡Vamos!

```bash
cd backend
npm run task:audit:cloud-cleanup
```

El script hará el trabajo. Solo revisar el reporte cuando termine.

**¿Preguntas?** Revisar documentación o contactar al equipo.
