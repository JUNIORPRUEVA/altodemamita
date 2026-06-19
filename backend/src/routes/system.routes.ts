import crypto from "node:crypto";
import { Router } from "express";
import { config } from "../config";
import { resolveCompanyByTenantKey } from "../companyIdentity";
import { prisma } from "../prisma";

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
systemRouter.get("/status", async (_req, res) => {
  const databaseUrl = process.env.DATABASE_URL || "";
  let databaseName = "unknown";
  let databaseHost = "unknown";

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

  const tenantKey = config.companyTenantKey;
  const cloudFingerprint = crypto
    .createHash("sha256")
    .update(`${databaseHost}:${databaseName}:${tenantKey}`)
    .digest("hex");

  let cloudData = {
    clients: 0,
    sellers: 0,
    lots: 0,
    sales: 0,
    installments: 0,
    payments: 0,
    syncBatches: 0,
  };

  try {
    const company = await resolveCompanyByTenantKey(tenantKey);
    const where = { companyId: company.id, deletedAt: null };
    const [
      clients,
      sellers,
      lots,
      sales,
      installments,
      payments,
      syncBatches,
    ] = await Promise.all([
      prisma.client.count({ where }),
      prisma.seller.count({ where }),
      prisma.lot.count({ where }),
      prisma.sale.count({ where }),
      prisma.installment.count({ where }),
      prisma.payment.count({ where }),
      prisma.syncBatch.count({ where: { companyId: company.id } }),
    ]);
    cloudData = {
      clients,
      sellers,
      lots,
      sales,
      installments,
      payments,
      syncBatches,
    };
  } catch (error) {
    console.error("[SystemStatus] cloudData count failed", error);
  }

  const initialUploadRequired =
    cloudData.clients === 0 &&
    cloudData.sellers === 0 &&
    cloudData.lots === 0 &&
    cloudData.sales === 0 &&
    cloudData.installments === 0 &&
    cloudData.payments === 0 &&
    cloudData.syncBatches === 0;

  res.json({
    ok: true,
    status: "online",
    service: "sistema-solares-backend",
    initialized: true,
    databaseConfigured: databaseUrl.length > 0,
    databaseName,
    databaseHost,
    tenantKey,
    cloudFingerprint,
    cloudData,
    initialUploadRequired,
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
systemRouter.get("/config", (_req, res) => {
  res.json({
    ok: true,
    allowCloudPull: false,
    restoreFromCloud: false,
    syncDirection: "local_to_cloud",
    tenantKey: "alto-dona-mamita-sistema-solares",
    initialized: true,
  });
});
