require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();

async function main() {
  // 1. Total counts
  const counts = await p.$queryRawUnsafe(`SELECT COUNT(*)::int as total, COUNT(*) FILTER (WHERE "deletedAt" IS NULL)::int as activos, COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)::int as eliminados FROM "Lot"`);
  console.log('=== Conteos globales de Lot ===');
  console.log(JSON.stringify(counts, null, 2));

  // 2. Active lots with company info
  const activeLots = await p.$queryRawUnsafe(`
    SELECT l.id, l."syncId", l.block, l.number, l.status, l."companyId", c.name as company_name, c."tenantKey"
    FROM "Lot" l
    LEFT JOIN "Company" c ON c.id = l."companyId"
    WHERE l."deletedAt" IS NULL
  `);
  console.log('\n=== Solares activos (deletedAt IS NULL) ===');
  console.log(JSON.stringify(activeLots, null, 2));

  // 3. Lots for company ALTO_MAMITA
  const altoMamitaLots = await p.$queryRawUnsafe(`
    SELECT COUNT(*)::int as total, COUNT(*) FILTER (WHERE "deletedAt" IS NULL)::int as activos, COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)::int as eliminados
    FROM "Lot" l
    JOIN "Company" c ON c.id = l."companyId"
    WHERE c."tenantKey" = 'alto_mamita'
  `);
  console.log('\n=== Solares para ALTO_MAMITA ===');
  console.log(JSON.stringify(altoMamitaLots, null, 2));

  // 4. All companies
  const companies = await p.$queryRawUnsafe(`SELECT id, name, "tenantKey" FROM "Company"`);
  console.log('\n=== Compañías ===');
  console.log(JSON.stringify(companies, null, 2));

  await p.$disconnect();
}

main().catch(e => {
  console.error(e.message);
  return p.$disconnect();
});
