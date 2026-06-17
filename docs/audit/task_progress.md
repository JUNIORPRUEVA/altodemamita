                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             # Plan de Blindaje de Sincronización

## Diagnóstico Inicial

### Estado actual de allowCloudPull=false ✅ (ya implementado)
- `app_flags.dart`: `allowCloudPull` default false
- `sync_service.dart`: `_downloadFromCloudEnabled` respeta la flag
- `sync_manager.dart`: initial sync condicionado a `allowCloudPull`
- `sync_queue_service.dart`: mergeRemoteRecords post-upload condicionado
- `_attemptConflictRecoveryDownload`: protegido por `allowCloudPull`

### Problemas a corregir

1. **LotRepository.findByBlockAndLotNumber** - No busca por block+number combinado, solo por lotNumber
2. **LotRepository.save** - Usa validación incorrecta de duplicados
3. **Backend sync.routes.ts** - No valida duplicados activos por block+number o document
4. **Faltan índices únicos parciales en PostgreSQL**
5. **Faltan logs de duplicados** con información clara
6. **Owner APK** - URL hardcodeada a producción, debería ser configurable
