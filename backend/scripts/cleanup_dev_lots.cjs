// Script de limpieza DEV: Marcar como eliminados solares de prueba que no existen en SQLite local
// Ejecutar: node scripts/cleanup_dev_lots.cjs (desde backend/)
// Carga DATABASE_URL desde .env automáticamente

const fs = require('fs');
const path = require('path');

// Cargar .env manualmente
const envPath = path.join(__dirname, '..', '.env');
if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, 'utf-8');
  for (const line of envContent.split('\n')) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#')) {
      const eqIdx = trimmed.indexOf('=');
      if (eqIdx > 0) {
        const key = trimmed.slice(0, eqIdx).trim();
        let value = trimmed.slice(eqIdx + 1).trim();
        if ((value.startsWith('"') && value.endsWith('"')) || 
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.slice(1, -1);
        }
        if (!process.env[key]) {
          process.env[key] = value;
        }
      }
    }
  }
}

const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  console.log('=== DIAGNÓSTICO COMPLETO DE SOLARES EN DEV ===\n');

  // 1. Conteo general
  console.log('--- 1. Conteo general de Lot ---');
  const generalCount = await prisma.$queryRawUnsafe(`
    SELECT
      COUNT(*)::int AS total,
      COUNT(*) FILTER (WHERE "deletedAt" IS NULL)::int AS activos,
      COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)::int AS eliminados
    FROM "Lot"
  `);
  console.log(JSON.stringify(generalCount, null, 2));

  // 2. Buscar los syncId específicos (activos o no)
  console.log('\n--- 2. Búsqueda de syncId específicos ---');
  const testSyncIds = [
    'offline-test-88',
    'z99-test-1781655670425',
    'test-lot-n11-002'
  ];
  for (const sid of testSyncIds) {
    const lots = await prisma.$queryRawUnsafe(`
      SELECT id, "syncId", block, number, status, "deletedAt", "updatedAt"
      FROM "Lot"
      WHERE "syncId" = '${sid}'
    `);
    if (lots.length > 0) {
      console.log(`  ${sid}: ENCONTRADO`, JSON.stringify(lots));
    } else {
      console.log(`  ${sid}: NO ENCONTRADO`);
    }
  }

  // 3. Últimos 20 registros (activos o no)
  console.log('\n--- 3. Últimos 20 registros de Lot (todos) ---');
  const recentLots = await prisma.$queryRawUnsafe(`
    SELECT id, "syncId", block, number, status, "deletedAt", "updatedAt"
    FROM "Lot"
    ORDER BY "updatedAt" DESC
    LIMIT 20
  `);
  console.log(JSON.stringify(recentLots, null, 2));

  // 4. Conteo por status
  console.log('\n--- 4. Conteo por status ---');
  const byStatus = await prisma.$queryRawUnsafe(`
    SELECT status, COUNT(*)::int AS total
    FROM "Lot"
    GROUP BY status
    ORDER BY status
  `);
  console.log(JSON.stringify(byStatus, null, 2));
}

main()
  .catch(e => {
    console.error('Error:', e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
