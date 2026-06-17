require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

async function main() {
  const tables = ['Client', 'Seller', 'Lot', 'Sale', 'Installment', 'Payment'];
  for (const table of tables) {
    const result = await prisma.$queryRawUnsafe(`
      SELECT 
        COUNT(*)::int AS total,
        COUNT(*) FILTER (WHERE "deletedAt" IS NULL)::int AS activos,
        COUNT(*) FILTER (WHERE "deletedAt" IS NOT NULL)::int AS eliminados
      FROM "${table}"
    `);
    const row = result[0];
    console.log(`${table.padEnd(15)} total=${String(row.total).padStart(3)} activos=${String(row.activos).padStart(3)} eliminados=${String(row.eliminados).padStart(3)}`);
  }
  await prisma.$disconnect();
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
