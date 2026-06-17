import { Router } from 'express';

export const systemRouter = Router();

/**
 * GET /api/system/status
 *
 * Ruta de compatibilidad para la app Windows.
 * La app espera un JSON con { initialized: true } para considerar
 * el backend como "alcanzable e inicializado".
 *
 * Ver: app_local/lib/features/auth/data/auth_service.dart
 *   _probeRemoteSystemStatus() -> body['initialized'] == true
 */
systemRouter.get('/status', (_req, res) => {
  res.json({
    ok: true,
    status: 'online',
    service: 'sistema-solares-backend',
    initialized: true,
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /api/system/config
 *
 * Ruta de compatibilidad para la app Windows.
 * Se usa como fallback cuando /system/status falla.
 * Si responde 200, la app marca el backend como "alcanzable".
 */
systemRouter.get('/config', (_req, res) => {
  res.json({
    ok: true,
    allowCloudPull: false,
    restoreFromCloud: false,
    syncDirection: 'local_to_cloud',
    tenantKey: 'alto-dona-mamita-sistema-solares',
    initialized: true,
  });
});
