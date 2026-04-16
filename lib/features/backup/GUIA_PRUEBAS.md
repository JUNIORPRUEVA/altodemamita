# GUÍA DE PRUEBAS RÁPIDAS - MÓDULO DE BACKUP

## Pre-requisitos
- Android Studio / VS Code con Flutter
- Windows 10/11
- Si posible, 2 unidades de disco disponibles (C: primaria + D: o externa)

---

## TEST 1: Compilación Sin Errores ✅

```bash
cd c:\Users\PC\Desktop\SISTEMA_SOLARES
flutter clean
flutter pub get
flutter run -d windows
```

**Resultado esperado**:
- Aplicación inicia sin errores
- En consola: `[MAIN] Backup system initialized`
- En consola: `[LIFECYCLE]` y `[BACKUP_CONTROLLER]` logs aparecen

---

## TEST 2: Detección de Discos 🖥️

**Pasos**:
1. Navegar a Configuración → Copia de Seguridad
2. Observar sección "Estado del Sistema"

**Validaciones**:
- ✅ Aparecen discos conectados (mínimo C:)
- ✅ Muestra nombre: "Windows (Sistema)" para C:
- ✅ Barra de progreso de espacio
- ✅ Muestra "XX% usado"
- ✅ Si 2+ discos: marca primario vs secundario
- ✅ Si hay D: externa → sugiere para backup

**Si falla**:
- Revisar console logs `[BACKUP_CONTROLLER]`
- PowerShell puede estar deshabilitado → ejecutar:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

---

## TEST 3: Configuración Guardada ✅

**Pasos**:
1. En UI de Backup → verá "Ruta de Backup" sugerida
2. Cierre aplicación completamente
3. Reabre aplicación
4. Vuelva a Configuración → Copia de Seguridad

**Validaciones**:
- ✅ La ruta de backup se mantiene igual
- ✅ Configuración persistió en disco
- ✅ Log inicial muestra ruta cargada

**Verification**:
```powershell
# Ver config guardada
$configPath = "$env:APPDATA\SistemaSolares\backup_config.json"
Get-Content $configPath | ConvertFrom-Json | ConvertTo-Json
```

---

## TEST 4: Crear Backup Manual 📦

**Pasos**:
1. En Backup Page → sección "Acciones Rápidas"
2. Clic en botón **"Crear Copia de Seguridad Ahora"**
3. Confirma en diálogo
4. Espera (puede tomar 5-30 segundos según BD)

**Validaciones**:
- ✅ Botón muestra "Creando copia de seguridad..."
- ✅ Luego muestra ✓ éxito con fecha/tamaño
- ✅ Aparece en "Historial de Backups" arriba
- ✅ Console log: `[BACKUP] Backup creado exitosamente:`

**En Explorador**:
```powershell
# Ver backup creado
$backupPath = "$env:USERPROFILE\Backups\SistemaSolares"
Get-ChildItem -Path $backupPath -Recurse -Filter "*.db"

# Debería mostrar:
# sistema_solares_manual_20260327-143022.db
#  sistema_solares_manual_20260327-143022.db.verified
```

---

## TEST 5: Historial de Backups 📋

**Pasos**:
1. Crear 3 backups manuales seguidos (rápido)
2. Ver sección "Historial de Backups"

**Validaciones**:
- ✅ Muestra "3" arriba indicando cantidad
- ✅ Lista en orden DESCENDENTE (más nuevo primero)
- ✅ Muestra fecha, tamaño, tipo (Manual)
- ✅ Icon de Backup para cada uno
- ✅ Menú ⋮ en cada backup

---

## TEST 6: Política de Retención 🗑️

**Pasos**:
1. Configurar retención a 2 (en lugar de 10)
   - Clic "Cambiar" en "Backups a Retener"
   - Slider a 2
   - Guardar
2. Crear 4 backups manuales
3. Ver historial

**Validaciones**:
- ✅ Historial muestra solo 2 backups (los más nuevos)
- ✅ Console muestra: `[RETENTION] Eliminando 2 backup(s) antigua(s)`
- ✅ Los archivos viejos desaparecen de disco

**Verification**:
```powershell
(Get-ChildItem -Path "$env:USERPROFILE\Backups\SistemaSolares\manual" -Filter "*.db").Count
# Debería mostrar: 2
```

---

## TEST 7: Restauración con Pre-Backup 🔄

**Pasos**:
1. Tener 2+ backups en historial
2. Seleccionar uno antiguo → Menú ⋮ → "Restaurar"
3. Confirma advertencia
4. Espera validación

**Validaciones**:
- ✅ Aviso claro: "Se creará copia de seguridad antes"
- ✅ Muestra fecha/tamaño del backup a restaurar
- ✅ Durante restauración: status "Restaurando..."
- ✅ Post-restauración: ✓ "Base de datos restaurada"
- ✅ Console: `[RESTORE] Backup de seguridad creado:`
- ✅ Historial incluye nueva entrada tipo "pre_restore"

**Verificar seguridad**:
```powershell
# Ver backup pre_restore creado
Get-ChildItem -Path "$env:USERPROFILE\Backups\SistemaSolares\pre_restore\*"
# Debería haber al menos 1 archivo del mismo tamaño que BD
```

---

## TEST 8: Auto-Backup en Startup ⚙️

**Pasos**:
1. En Backup → Configuración → activar "Backup Automático"
2. Activar "Al iniciar aplicación"
3. Cierre aplicación completamente
4. Cierre Android Studio / VS Code
5. Espere 5 segundos
6. Reabre: `flutter run -d windows`

**Validaciones**:
- ✅ Console inicial: `[LIFECYCLE] App resumed`
- ✅ Seguido de: `[STARTUP_BACKUP] Iniciando...`
- ✅ Log: `[STARTUP_BACKUP] ✓ Backup de startup creado:`
- ✅ Historial muestra nuevo backup tipo "Inicio"

---

## TEST 9: Auto-Backup en Shutdown ⚙️

**Pasos**:
1. En Backup → Configuración → activar "Al cerrar aplicación"
2. Cierre aplicación (clic X en ventana)
3. Espere 3 segundos

**Validaciones**:
- ✅ Antes de cerrar: puede ver log `[SHUTDOWN_BACKUP]`
- ✅ Si abre logs del último run: verá `[SHUTDOWN_BACKUP] ✓ Backup`
- ✅ Historial post-reapertura: nuevo backup tipo "Cierre"

---

## TEST 10: Disco Secundario No Disponible 🚨

**Pasos**:
1. Si tienen D: externa → desconecten
2. Reabre aplicación
3. Vayan a Backup Page

**Validaciones**:
- ✅ En "Estado del Sistema" solo muestra C: (primario)
- ✅ Advierte: "⚠️ No se detectó unidad secundaria"
- ✅ En "Acciones Rápidas" botón deshabilitado
- ✅ Mensaje: "Se necesita unidad secundaria"
- ✅ pero NO rompe: puede cambiar ruta a C:\Backups
- ✅ Clic "Cambiar" en ruta → puede usar C: como fallback

**Validar fallback**:
- Después de cambiar ruta a C:\Backups\SistemaSolares
- Crear backup manual → DEBE FUNCIONAR
- Archivo guardado en C:

---

## TEST 11: Espacio Insuficiente 🚨

**Pasos**:
1. En Backup → Configuración → Cambiar ruta a carpeta con < 100 MB
2. Intentar crear backup

**Validaciones**:
- ✅ Error claro: "Espacio insuficiente"
- ✅ Muestra "Requerido: XX MB, Disponible: YY MB"
- ✅ Backup NO se crea
- ✅ BD no se daña
- ✅ Historial registra como fallido

---

## TEST 12: Integridad de Backup ✓

**Pasos**:
1. Crear un backup
2. Ir a ruta:  `$env:USERPROFILE\Backups\SistemaSolares\manual\`
3. Verificar archivo `.verified`

**Validaciones**:
```powershell
Get-Content "sistema_solares_manual_20260327.db.verified"
# Output: 2026-03-27T14:30:22.000Z|5242880|5242880
#         (timestamp|databaseSize|backupSize)
```
- ✅ Tamaño database === tamaño backup (idénticos)

---

## TEST 13: Rendimiento ⚡

**Pasos**:
1. Sincronizar consola para ver logs de tiempo
2. Crear 3 backups seguidos
3. Medir tiempo transcurrido por cada uno

**Métricas esperadas**:
- BD pequeña (<1MB): < 500ms por backup
- BD media (10MB): < 2s por backup
- BD grande (100MB): < 20s por backup
- No debe congelarse UI en ningún caso

---

## TEST 14: Logging y Debugging 🔍

**En Console/Debug**:
```
[MAIN] Backup system initialized
[BACKUP_CONTROLLER] Discos detectados: 2
[BACKUP_CONTROLLER] Disco primario: C:
[BACKUP_CONTROLLER] Disco secundario: D:
[BACKUP] Iniciando backup de tipo: manual
[BACKUP] Tamaño de base de datos: 15.50 MB
[BACKUP] Verificando espacio disponible...
[BACKUP] Cerrando base de datos para backup...
[BACKUP] Copiando archivo de base de datos...
[BACKUP] Backup creado exitosamente: 15.50 MB
[RETENTION] Aplicando política de retención...
[RETENTION] ✓ Espacio disponible en backup: 250.75 GB
[BACKUP] Reabriendo base de datos...
[BACKUP_CONTROLLER] ✓ Backup creado exitosamente
```

**Validación**:
- ✅ Logs tienen prefijo [SECTION]
- ✅ Cada sección es independiente
- ✅ Puedes seguir el flujo completo

---

## TEST 15: Recuperación ante Errores 🛡️

**Scenario A**: Crear backup, desconectar disco durante el proceso
- **Resultado esperado**: Error graceful, BD aún accesible, retry posible

**Scenario B**: Simular DB corrupta en backup
- **Resultado esperado**: Validate integridad falla, user alerta, fallback a pre_restore

**Scenario C**: rename/delete archivo .verified
- **Resultado esperado**: Advierte al restaurar, pero permite continuar

---

## TABLA DE LOGS ESPERADOS

| Acción | Log esperado | Severidad |
|--------|--------------|-----------|
| Iniciar app | `[MAIN] Backup system initialized` | INFO |
| Abrir Backup Page | `[BACKUP_CONTROLLER] Discos detectados: X` | INFO |
| Crear backup | `[BACKUP] Tamaño de base de datos:` | INFO |
| Completar backup | `[BACKUP] ✓ Backup creado exitosamente` | SUCCESS |
| Restaurar | `[RESTORE] Iniciando restauración...` | INFO |
| Pre-restore | `[RESTORE] Backup de seguridad creado:` | SUCCESS |
| Retención activa | `[RETENTION] Eliminando X backup(s)` | INFO |
| Espacio bajo | `[RETENTION] ⚠️ Espacio libre bajo` | WARNING |
| Auto-startup | `[STARTUP_BACKUP] ✓ Backup creado` | SUCCESS |
| Auto-shutdown | `[SHUTDOWN_BACKUP] ✓ Backup creado` | SUCCESS |
| Error discos | `Error getting disk info for D:` | ERROR |
| Error restore | `[RESTORE] ERROR: ...` | ERROR |

---

## CHECKLIST FINAL

- [ ] Compilación sin errores
- [ ] Discos detectados correctamente
- [ ] Configuración persiste entre sesiones
- [ ] Backup manual crea archivos
- [ ] Historial muestra backups creados
- [ ] Retención elimina backups antiguos
- [ ] Restauración funciona y crea pre_restore
- [ ] Auto-backup startup se activa
- [ ] Auto-backup shutdown se activa
- [ ] Sin disco secundario: fallback a primario
- [ ] Espacio insuficiente: error claro
- [ ] Integridad validada (archivo .verified)
- [ ] Rendimiento aceptable
- [ ] Logs aparecen en consola
- [ ] Recovery ante errores funciona

✅ **Si todos los tests pasan: Módulo LISTO para producción**

---

## DEBUGGING SI ALGO FALLA

### "Backup no aparece en historial"
```powershell
# Revisar archivo JSON
cat "$env:APPDATA\SistemaSolares\backup_history.json"
# Debería mostrar array con BackupMetadata
```

### "Disco no se detecta"
```powershell
# Verificar PowerShell funciona
Get-Volume -DriveLetter C
# Si da error → ExecutionPolicy issue
```

### "Pre-backup no se crea"
```powershell
# Ver directorio pre_restore
ls "$env:USERPROFILE\Backups\SistemaSolares\pre_restore\"
# Debería haber archivos
```

### "Logs no aparecen"
- Buscar "flutter: " en console (filter)
- Verificar "Debug Console" está activo
- Activar verbose: `flutter run -d windows -v`

---

**INSTRUCCIONES**: Run through these tests in order. Si alguno falla, documentá el log de error y comparte para debugging.
