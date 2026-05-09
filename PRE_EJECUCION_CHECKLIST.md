# ✅ PRE-EJECUCIÓN CHECKLIST - Auditoría de Datos Nube

**Antes de ejecutar el script de auditoría, verificar todos estos puntos:**

---

## 📋 Verificaciones Previas

### 1. Dependencias Node.js ✓
```bash
cd backend
npm --version  # Debe estar instalado
node --version  # v14+
npm list @prisma/client  # Debe estar en package.json
```
- [ ] Node.js instalado (v14+)
- [ ] npm instalado
- [ ] `npm install` ejecutado en `backend/`
- [ ] Todas las dependencias resueltas

### 2. PostgreSQL Cliente (pg_dump) ✓
```bash
pg_dump --version  # Ej: pg_dump (PostgreSQL) 13.0
```
- [ ] `pg_dump` disponible en PATH
- [ ] Responde a `pg_dump --version`
- [ ] Si no está: descargar PostgreSQL client desde https://www.postgresql.org/download/windows/

### 3. Credenciales PostgreSQL Nube ✓

**Opción A: Usar DATABASE_URL en .env**
```bash
# backend/.env
DATABASE_URL=postgresql://user:password@host:5432/database?schema=public
```

**Opción B: Variables de entorno individuales**
```bash
# backend/.env
DB_HOST=host
DB_PORT=5432
DB_USERNAME=user
DB_PASSWORD=password
DB_NAME=database
DB_SCHEMA=public
```

Verificar:
```bash
# Probar conectividad
psql -h HOST -U USER -d DATABASE -c "SELECT version();"
# Debe responder con versión de PostgreSQL
```

- [ ] `DATABASE_URL` configurada en `.env` O variables `DB_*`
- [ ] Credenciales correctas (user, password, host, port, database)
- [ ] Conexión a PostgreSQL funciona (`psql ... SELECT version();`)
- [ ] Usuario tiene permisos de lectura en PostgreSQL

### 4. Base de Datos Local ✓

Ubicaciones buscadas automáticamente:
```
%APPDATA%\sistema_solares\sistema_solares.db
%LOCALAPPDATA%\sistema_solares\sistema_solares.db
Program Files\SistemaSolares\data\sistema_solares.db
```

Verificar:
```bash
# Windows PowerShell
Test-Path "$env:APPDATA\sistema_solares\sistema_solares.db"
# Debe responder: True
```

**Si no la encuentra:**
- [ ] Localizar `sistema_solares.db` manualmente
- [ ] Copiar a ruta conocida (ej: `%APPDATA%\sistema_solares\`)
- [ ] Cerrar Flutter desktop (para no bloquear el archivo)
- [ ] Cerrar cualquier herramienta SQLite (SQLiteAdmin, etc.)

- [ ] `sistema_solares.db` existe y es accesible
- [ ] No está siendo usada por Flutter desktop u otra app
- [ ] Tiene datos (no está vacío)

### 5. Espacio en Disco ✓
```bash
# Backup aproximadamente igual tamaño a PostgreSQL actual
# Estimar: SELECT pg_database_size('database_name') / 1024 / 1024 as mb;
```

- [ ] Suficiente espacio en `C:` para backup
- [ ] Mínimo: 500 MB libres (ajustar según tamaño real de DB)

### 6. Permisos de Carpetas ✓

Script necesita crear:
- [ ] `backend/audit-reports/` (permisos de escritura)
- [ ] `backend/backups/cloud/` (permisos de escritura)

Verificar:
```bash
# Si no existen, npm lo hará automáticamente
# Si existen, verificar que son escribibles
```

### 7. Conectividad ✓

- [ ] Conexión a Internet estable
- [ ] PostgreSQL nube accesible
- [ ] Sin firewall bloqueando puerto 5432
- [ ] VPN conectada si es necesario

---

## 🚀 Ejecución

### Opción 1: Comando npm (recomendado)
```bash
cd backend
npm run task:audit:cloud-cleanup
```

Verificar en `package.json`:
```json
{
  "scripts": {
    "task:audit:cloud-cleanup": "node scripts/audit-cloud-data.js"
  }
}
```

**Si no existe:** Agregarlo a package.json manualmente.

### Opción 2: Node direct
```bash
cd backend
node scripts/audit-cloud-data.js
```

### Opción 3: TypeScript direct
```bash
cd backend
npx ts-node src/tasks/cloud-audit.ts
```

---

## ⏱️ Tiempo Estimado

- Backup: 1-5 minutos (según tamaño DB)
- Auditoría: 30 segundos - 2 minutos
- **Total**: 2-10 minutos

---

## 📊 Esperado en Salida

### Consola (stdout)
```
📦 FASE 1: BACKUP OBLIGATORIO...
  ⏳ Realizando backup de PostgreSQL...
  ✅ Backup completado exitosamente
    Archivo: postgresql_backup_2026-05-08_14-30-45.sql
    Tamaño: 2.45 MB

📊 Contando registros en NUBE...
  ✓ Completado

📊 Contando registros en LOCAL...
  ✓ Completado

[Reporte completo con tablas y propuesta...]

✅ AUDITORÍA COMPLETADA - ANÁLISIS DE SOLO LECTURA
═══════════════════════════════════════════════════════════════

📄 ARCHIVOS GENERADOS:
   • Reporte JSON: audit-reports/audit-report-YYYY-MM-DD_HH-mm-ss.json
   • Backup SQL: backups/cloud/postgresql_backup_YYYY-MM-DD_HH-mm-ss.sql
```

### Archivos Creados
```
backend/
├── audit-reports/
│   └── audit-report-2026-05-08_14-30-45.json   (~100KB JSON)
└── backups/cloud/
    └── postgresql_backup_2026-05-08_14-30-45.sql  (~2.45 MB)
```

---

## 🔴 Posibles Errores

| Error | Causa | Solución |
|-------|-------|----------|
| `DATABASE_URL no configurada` | Falta variable de entorno | Agregar a `.env` |
| `pg_dump: comando no encontrado` | PostgreSQL client no instalado | Instalar PostgreSQL client |
| `Base de datos local... no encontrada` | SQLite no ubicada | Buscar y copiar a ruta conocida |
| `ECONNREFUSED / FATAL: Ident authentication failed` | Credenciales incorrectas o servidor no responde | Verificar DATABASE_URL, verificar servidor |
| `SQLITE_IOERR` | Base de datos bloqueada | Cerrar Flutter desktop, reintentar |
| `EACCES / Permission denied` | Sin permisos en carpetas | Verificar permisos en `audit-reports/` y `backups/` |

---

## ✅ Green Lights (Proceder)

- [x] Todas las verificaciones pasaron
- [x] No hay errores en los pasos anteriores
- [x] Backup SQL creado y verificado
- [x] Reporte JSON generado
- [x] Consola muestra "AUDITORÍA COMPLETADA"

**SIGUIENTE PASO**: Revisar `audit-report-YYYY-MM-DD_HH-mm-ss.json` y consola output

---

## 🚫 Red Lights (DETENER)

- [ ] ❌ Base de datos nube no accesible
- [ ] ❌ Credenciales incorrectas (DATABASE_URL)
- [ ] ❌ Backup falló o está vacío
- [ ] ❌ Base de datos local no encontrada
- [ ] ❌ Errores de compilación TypeScript
- [ ] ❌ Permisos insuficientes

**ANTES DE PROCEDER**: Resolver todos los red lights

---

## 🔐 Seguridad - Confirmación Final

**Antes de ejecutar, confirmar:**

- [x] Este es un script de **SOLO LECTURA**
- [x] NO se modificará nada en PostgreSQL durante la auditoría
- [x] NO se modificará nada en SQLite durante la auditoría
- [x] Se creará un backup SQL completo (verificable)
- [x] El usuario DEBE revisar el reporte antes de cualquier limpieza
- [x] Fases 4+ (limpieza) requieren aprobación explícita

---

## 📝 Después de Ejecutar

### Immediato:
1. ✅ Revisar salida en consola (buscar "AUDITORÍA COMPLETADA")
2. ✅ Verificar archivos generados existen
3. ✅ Guardar ruta del backup en lugar seguro

### En 5 minutos:
1. ✅ Abrir `audit-report-YYYY-MM-DD_HH-mm-ss.json` en editor
2. ✅ Revisar secciones:
   - Backup status (¿exitoso?)
   - Conteos (¿diferencias esperadas?)
   - Orphaned records (¿registros huérfanos?)
   - Cleanup proposal (¿qué se limpiaría?)
   - Risk assessment (¿nivel de riesgo?)

### Para decisión de limpieza:
1. ✅ Revisar reporte con equipo
2. ✅ Validar que local está actualizado
3. ✅ Obtener aprobación explícita
4. ✅ Guardar reporte como referencia
5. ⏳ Ejecutar Fase 4 (limpieza) - cuando esté listo

---

**Actualizado**: 2026-05-08  
**Estado**: ✅ LISTO PARA VERIFICACIÓN PRE-EJECUCIÓN  
**Siguiente**: Ejecutar `npm run task:audit:cloud-cleanup` y revisar reporte
