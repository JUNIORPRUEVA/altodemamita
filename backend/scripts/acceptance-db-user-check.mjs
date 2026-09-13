import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const emails = process.argv.slice(2).map((email) => email.trim().toLowerCase()).filter(Boolean);

async function main() {
  const users = await prisma.user.findMany({
    where: { email: { in: emails } },
    select: {
      email: true,
      active: true,
      deletedAt: true,
      role: true,
      _count: {
        select: {
          operatedSales: true,
          receivedPayments: true,
          annulledPayments: true,
        },
      },
    },
    orderBy: { email: 'asc' },
  });
  const result = Object.fromEntries(
    emails.map((email) => {
      const matches = users.filter((user) => user.email.toLowerCase() === email);
      return [
        email,
        {
          rows: matches.length,
          users: matches.map((user) => ({
            active: user.active,
            deletedAt: user.deletedAt?.toISOString() ?? null,
            role: user.role,
            history: user._count,
          })),
        },
      ];
    }),
  );
  console.log(JSON.stringify(result, null, 2));
}

main()
  .catch((error) => {
    console.error(error?.message ?? error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
