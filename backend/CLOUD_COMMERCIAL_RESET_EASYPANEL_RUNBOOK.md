# Cloud Commercial Reset - EasyPanel Runbook

Este runbook define ejecucion segura en entorno backend real de EasyPanel.

## 1) Donde se debe ejecutar

Si DATABASE_URL usa host interno Docker (por ejemplo altodemamita_altomamita-postgres:5432), el script debe ejecutarse dentro del contenedor/servicio backend en EasyPanel.

No ejecutar desde PC local con ese host interno.

## 2) Reglas de seguridad

- Dry-run obligatorio antes de execute.
- Backup SQL obligatorio antes de borrar (lo hace el script en execute).
- Execute solo con CONFIRM_CLOUD_COMMERCIAL_RESET=true.
- No se tocan tablas de auth/permisos:
  - users
  - roles
  - permissions
  - user_roles
  - role_permissions
  - company_profiles
  - authorized_devices
- No toca base local.
- No activa cloud pull.
- No correr automaticamente al desplegar.

## 3) Opcion A - EasyPanel con terminal interactiva (recomendada)

1. Abrir EasyPanel.
2. Ir a Project del backend.
3. Entrar al Service backend.
4. Abrir Terminal/Console del servicio.
5. Verificar que estas en /app (si no, ejecutar cd /app).
6. Ejecutar dry-run:
   - npm run task:cloud-commercial-reset:dry-run
7. Revisar salida y reporte JSON generado en:
   - /app/cloud-commercial-reset-reports/
8. Si apruebas, ejecutar limpieza real con confirmacion explicita:
   - CONFIRM_CLOUD_COMMERCIAL_RESET=true npm run task:cloud-commercial-reset:execute
9. Verificar conteos finales en salida y en reporte JSON final.
10. Confirmar que backup existe en:
   - /app/backups/cloud-commercial-reset/

## 4) Opcion B - EasyPanel sin terminal interactiva

Usar ejecucion controlada manual, sin automatizar deploy.

### 4.1 Preparar comando temporal

Comando del proceso (temporal):

- npm run task:cloud-commercial-reset:controlled

Variables de entorno temporales para dry-run:

- RUN_CLOUD_COMMERCIAL_RESET_TASK=true
- CLOUD_COMMERCIAL_RESET_MODE=dry-run
- CONFIRM_CLOUD_COMMERCIAL_RESET=false

Variables de entorno temporales para execute:

- RUN_CLOUD_COMMERCIAL_RESET_TASK=true
- CLOUD_COMMERCIAL_RESET_MODE=execute
- CONFIRM_CLOUD_COMMERCIAL_RESET=true

### 4.2 Flujo recomendado

1. Duplicar el servicio backend como Job/Task manual (si EasyPanel lo permite), o editar temporalmente el comando del servicio.
2. Ejecutar primero dry-run con variables dry-run.
3. Descargar/revisar reporte JSON de dry-run.
4. Ejecutar luego execute con variables execute.
5. Verificar reporte final y backup.
6. Restaurar inmediatamente el comando original del backend (node dist/main.js o entrypoint normal) y quitar variables temporales.

## 5) Rutas de artefactos

- Reportes dry-run/execute:
  - /app/cloud-commercial-reset-reports/
- Backups SQL:
  - /app/backups/cloud-commercial-reset/

## 6) Restaurar backup si algo sale mal

Dentro del entorno con acceso a PostgreSQL:

- psql "$DATABASE_URL" -f "/app/backups/cloud-commercial-reset/<archivo>.sql"

## 7) Validaciones posteriores obligatorias

1. Login web/PWA funcionando.
2. Usuarios y permisos intactos.
3. Datos comerciales en 0 en nube (clients, sellers, products/lots, sales, installments, payments y tablas comerciales relacionadas que existan).
4. Sync local -> nube vuelve a subir nuevos datos correctamente.
5. Cloud pull sigue bloqueado en cliente (ALLOW_CLOUD_PULL=false).
