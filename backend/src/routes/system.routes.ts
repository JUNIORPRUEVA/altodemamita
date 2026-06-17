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
 *
 * Ahora también incluye información de la DB actual (sin secretos).
 */
systemRouter.get('/status', (_req, res) => {
  const databaseUrl = process.env.DATABASE_URL || '';
  let databaseName = 'unknown';
  let databaseHost = 'unknown';

  try {
    // Parsear DATABASE_URL para extraer host y database name sin credenciales
    // Formato típico: postgresql://user:password@host:port/database?schema=public
    const match = databaseUrl.match(
      /postgresql:\/\/[^:]+:[^@]+@([^/]+)\/([^?]+)/,
    );
    if (match) {
      databaseHost = match[1]; // host:port
      databaseName = match[2]; // database name
    }
  } catch {
    // Si falla el parseo, mostrar valores por defecto
  }

  res.json({
    ok: true,
    status: 'online',
    service: 'sistema-solares-backend',
    initialized: true,
    databaseConfigured: databaseUrl.length > 0,
    databaseName,
    databaseHost,
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
