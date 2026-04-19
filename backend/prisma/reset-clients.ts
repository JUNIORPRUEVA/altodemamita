import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const execute = process.argv.includes('--execute');

  const before = await collectCounts();
  console.log('Backend counts before reset:');
  console.log(JSON.stringify(before, null, 2));

  if (!execute) {
    console.log('Dry run only. Re-run with --execute to apply the reset.');
    return;
  }

  const timestamp = new Date();

  await prisma.$transaction(async (tx) => {
    await tx.payment.updateMany({
      where: { deletedAt: null },
      data: { deletedAt: timestamp },
    });

    await tx.installment.updateMany({
      where: { deletedAt: null },
      data: { deletedAt: timestamp },
    });

    await tx.sale.updateMany({
      where: { deletedAt: null },
      data: { deletedAt: timestamp },
    });

    await tx.client.updateMany({
      where: { deletedAt: null },
      data: { deletedAt: timestamp },
    });

    await tx.product.updateMany({
      where: { deletedAt: null },
      data: {
        stock: 1,
        isActive: true,
      },
    });
  });

  const after = await collectCounts();
  console.log('Backend counts after reset:');
  console.log(JSON.stringify(after, null, 2));
}

async function collectCounts() {
  const [clients, sales, installments, payments, products] = await Promise.all([
    prisma.client.count({ where: { deletedAt: null } }),
    prisma.sale.count({ where: { deletedAt: null } }),
    prisma.installment.count({ where: { deletedAt: null } }),
    prisma.payment.count({ where: { deletedAt: null } }),
    prisma.product.count({ where: { deletedAt: null } }),
  ]);

  const duplicateDocuments = await prisma.$queryRawUnsafe<Array<{ document_id: string; total: number }>>(
    "SELECT COALESCE(NULLIF(TRIM(document_id), ''), '__EMPTY__') AS document_id, COUNT(*)::int AS total FROM clients WHERE deleted_at IS NULL GROUP BY 1 HAVING COUNT(*) > 1 ORDER BY total DESC, document_id ASC LIMIT 20",
  );

  return {
    clients,
    sales,
    installments,
    payments,
    products,
    duplicateDocuments,
  };
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });