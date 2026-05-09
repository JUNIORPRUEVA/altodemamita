# 🔍 Auditoría Controlada de Datos en Nube
## Sistema de Limpieza Segura: Nube → Local Master

**Estado: LOCAL MASTER → CLOUD MIRROR**
- La base de datos local (PC principal) es la fuente autorizada
- La nube es un espejo que debe coincidir con local
- Se ha bloqueado nube → local para datos comerciales
- Esta auditoría prepara la sincronización inversa controlada

---

## 📋 Fases del Proceso

### ✅ Fase 1: Backup Obligatorio de PostgreSQL Nube
- **Acción**: Crear dump SQL completo de la base de datos PostgreSQL en la nube
- **Archivo**: `backups/cloud/postgresql_backup_YYYY-MM-DD_HH-mm-ss.sql`
- **Validación**: Verificar que existe y tiene contenido
- **Requisito**: NO continuar si falla

### ✅ Fase 2: Auditoría Nube vs Local
- **Comparar conteos** por tabla:
  - `clients` / `clientes`
  - `sellers` / `vendedores`
  - `products` / `solares`
  - `sales` / `ventas`
  - `payments` / `pagos`
  - `installments` / `cuotas`
  
- **Detectar anomalías**:
  - Registros solo en nube (candidatos a borrar)
  - Registros solo en local (falta sincronizar)
  - Registros coincidentes (paridad)
  - Duplicados (mismo documentId, múltiples syncIds)
  - Registros soft-deleted (con deleted_at)
  - Registros huérfanos (sin relación padre)

- **Generar reporte** con métricas completas

### ✅ Fase 3: Propuesta de Limpieza
- **NO borrar todavía**
- Mostrar:
  - ✓ Qué tablas se limpiarían
  - ✓ Cuántos registros se borrarían/archivarían
  - ✓ Qué relaciones dependen de esos registros
  - ✓ Riesgos identificados
  - ✓ Orden correcto de limpieza por dependencias
  - ✓ Recomendaciones

---

## 🚀 Cómo Ejecutar

### Opción 1: Script npm (recomendado)
```bash
cd backend
npm run task:audit:cloud-cleanup
```

### Opción 2: Ejecutar directamente
```bash
cd backend
node scripts/audit-cloud-data.js
```

### Opción 3: Con ts-node
```bash
cd backend
npx ts-node src/tasks/cloud-audit.ts
```

---

## ⚙️ Requisitos Previos

### 1. Dependencias Node.js
```bash
cd backend
npm install
```

Asegura que tengas:
- `@prisma/client`
- `sqlite` (para conexión a base de datos local)
- `sqlite3` 

### 2. Credenciales PostgreSQL Nube
El script usa `process.env.DATABASE_URL`. Asegúrate de que esté configurado:

**En `.env`:**
```
DATABASE_URL="postgresql://user:password@host:port/database?schema=public"
```

O variables de entorno individuales:
```
DB_HOST=host
DB_PORT=5432
DB_USERNAME=user
DB_PASSWORD=password
DB_NAME=database
DB_SCHEMA=public
```

### 3. Acceso a Base de Datos Local
El script buscará `sistema_solares.db` en:
- `%APPDATA%\sistema_solares\`
- `%LOCALAPPDATA%\sistema_solares\`
- `Program Files\SistemaSolares\data\`
- Rutas relativas comunes

**Si no la encuentra:** Especificar manualmente en código o hacer backup y copiar a ruta conocida.

### 4. PostgreSQL cliente
Se necesita `pg_dump` disponible en PATH para hacer el backup:

```bash
# Windows: verificar
pg_dump --version

# Si no está disponible, instalar PostgreSQL tools desde:
# https://www.postgresql.org/download/windows/
```

---

## 📊 Salida del Reporte

### Ubicación de archivos:
```
backend/
├── audit-reports/
│   └── audit-report-2026-05-08_14-30-45.json    ← Reporte JSON completo
└── backups/
    └── cloud/
        └── postgresql_backup_2026-05-08_14-30-45.sql   ← Backup SQL
```

### Estructura del reporte JSON:
```json
{
  "timestamp": "2026-05-08 14:30:45",
  "backupStatus": {
    "success": true,
    "filename": "postgresql_backup_...",
    "size": 1234567,
    "path": "/full/path/to/backup.sql"
  },
  "cloudCounts": {
    "clients": 45,
    "sellers": 8,
    "products": 12,
    "sales": 23,
    "payments": 67,
    "installments": 89,
    "clientsDeleted": 3,
    ...
  },
  "localCounts": {
    "clients": 40,
    ...
  },
  "comparison": {
    "tables": {
      "clients": {
        "cloudCount": 45,
        "localCount": 40,
        "onlyInCloud": 5,
        "onlyInLocal": 0,
        "matched": 40,
        "cloudDeleted": 3,
        "localDeleted": 1
      },
      ...
    },
    "orphanedRecords": {
      "paymentsWithoutSale": 2,
      "installmentsWithoutSale": 0,
      "salesWithoutClient": 0,
      "salesWithoutProduct": 0
    },
    "possibleDuplicates": [...],
    "dataIntegrity": [...]
  },
  "cleanupProposal": {
    "totalCloudRecords": 244,
    "totalLocalRecords": 189,
    "recordsToDelete": [
      {
        "table": "clients",
        "reason": "Clientes que existen solo en nube",
        "count": 5,
        "dependencies": ["sales"],
        "preferSoftDelete": true
      }
    ],
    "dependencyOrder": ["payments", "installments", "sales", "clients", ...],
    "riskAssessment": {
      "level": "medium",
      "criticalIssues": [],
      "warnings": ["2 pagos huérfanos sin venta"],
      "recommendations": [...]
    },
    "estimatedImpact": {...}
  }
}
```

---

## 🔐 Seguridad

### Garantías:
1. ✅ **Solo lectura** - No modifica nada
2. ✅ **Backup obligatorio** - Antes de cualquier acción
3. ✅ **Backup verificado** - Se comprueba tamaño > 0
4. ✅ **Análisis previo** - Generar reporte antes de limpiar
5. ✅ **Aprobación explícita** - Usuario debe revisar y aprobar

### Lo que el script HACE:
- ✓ Crea backup PostgreSQL con `pg_dump`
- ✓ Se conecta a PostgreSQL (lectura)
- ✓ Se conecta a SQLite local (lectura)
- ✓ Analiza datos
- ✓ Genera reporte JSON

### Lo que el script NO HACE (aún):
- ✗ No modifica nada en PostgreSQL
- ✗ No modifica nada en SQLite
- ✗ No ejecuta DELETE ni UPDATE
- ✗ No ejecuta limpieza de soft-deleted
- ✗ No sincroniza datos
- ✗ No cambia configuraciones

---

## 🔄 Flujo Completo (6 Fases)

```
FASE 1: BACKUP ✅
└─→ pg_dump de nube
└─→ Guardar timestamp
└─→ Verificar archivo

FASE 2: AUDITORÍA ✅
└─→ Conectar a PostgreSQL nube
└─→ Conectar a SQLite local
└─→ Comparar tablas
└─→ Detectar orfandad/duplicados
└─→ Generar reporte

FASE 3: PROPUESTA ✅
└─→ Analizar diferencias
└─→ Proponer limpieza
└─→ Evaluar riesgos
└─→ Generar recomendaciones
└─→ **MOSTRAR REPORTE (USUARIO REVISA)**

FASE 4: LIMPIEZA SEGURA ⏳ (PENDIENTE - CON APROBACIÓN)
└─→ Limpiar tablas hijas: pagos, cuotas, detalles
└─→ Luego ventas
└─→ Luego clientes, vendedores, solares
└─→ Respetar relaciones y FK
└─→ Preferir soft-delete

FASE 5: RE-ESPEJO LOCAL → NUBE ⏳ (PENDIENTE)
└─→ Sincronizar desde PC principal
└─→ Subir clientes, vendedores, solares, ventas, cuotas, pagos
└─→ **NO permitir nube → local**
└─→ Verificar paridad

FASE 6: VERIFICACIÓN FINAL ⏳ (PENDIENTE)
└─→ Comparar nuevamente nube vs local
└─→ Verificar conteos
└─→ Verificar relaciones y balances
└─→ Confirmar éxito
```

---

## 📝 Próximos Pasos (Después de Revisar Reporte)

### Si la propuesta está bien:
1. ✅ Guardar el reporte JSON
2. ✅ Revisar con el equipo
3. ✅ Obtener aprobación explícita
4. ✅ Ejecutar Fase 4 (limpieza con el reporte guardado)

### Si hay problemas:
1. ⚠️ Revisar qué está mal
2. ⚠️ Hacer correcciones en local si aplica
3. ⚠️ Re-ejecutar auditoría
4. ⚠️ Repetir hasta que esté bien

### Nunca:
- ❌ Ejecutar limpieza sin revisar reporte
- ❌ Modificar nube manualmente
- ❌ Perder el backup
- ❌ Permitir nube → local durante limpieza

---

## 🆘 Troubleshooting

### "DATABASE_URL no configurada"
```bash
# Verificar en backend/.env
echo $DATABASE_URL
# O establecer manualmente
export DATABASE_URL="postgresql://user:pass@host:5432/db"
```

### "pg_dump: comando no encontrado"
```bash
# Windows: agregar PostgreSQL al PATH
# O: instalar cliente PostgreSQL desde https://www.postgresql.org/download/windows/

# Verificar instalación
pg_dump --version
```

### "Base de datos local no encontrada"
```bash
# Buscar manualmente
# Usuario debe indicar ruta en el código o copiar a ubicación conocida
# Rutas buscadas:
# - %APPDATA%\sistema_solares\
# - %LOCALAPPDATA%\sistema_solares\
# - Program Files\SistemaSolares\data\
```

### "Error connecting to PostgreSQL"
```bash
# Verificar credenciales en DATABASE_URL
# Verificar que servidor está disponible
psql -h host -U user -d database -c "SELECT version();"
```

### "SQLITE_IOERR" o "database is locked"
```bash
# Cerrar cualquier app usando sistema_solares.db
# - Flutter desktop
# - SQLiteAdmin
# - Otros clientes SQLite
# Reintentar auditoría
```

---

## 📞 Contacto

Para reportar problemas o sugerencias en la auditoría, incluir:
- ✓ Reporte JSON generado
- ✓ Mensaje de error completo
- ✓ Versión de base de datos (query: `SELECT version();` en PostgreSQL)
- ✓ Cantidad de registros en local vs nube

---

**Última actualización**: 2026-05-08
**Autor**: Sistema de Auditoría Automatizado
**Estado**: En desarrollo - Fases 1-3 listas
