/**
 * Provisiona la base de datos EXCLUSIVA de pruebas (UAT).
 *
 * A diferencia de `uat-setup-users.ts` / `uat-seed.ts`, este script crea la
 * empresa si no existe, de modo que la UAT puede correr sobre una base nueva
 * SIN ningun dato real de clientes.
 *
 * Salvaguardas:
 *  - Exige ACCEPTANCE_DATABASE_URL apuntando a 127.0.0.1 / localhost.
 *  - Exige que el nombre de la base termine en `_uat` (no `_acpt` ni prod).
 */
import { PrismaClient } from "@prisma/client";

const dbUrl = process.env.ACCEPTANCE_DATABASE_URL ?? "";
if (!dbUrl) {
  console.error("Falta ACCEPTANCE_DATABASE_URL.");
  process.exit(2);
}
if (!/(127\.0\.0\.1|localhost)/.test(dbUrl)) {
  console.error("Rechazado: solo base local de pruebas.");
  process.exit(2);
}
if (!/_uat(\?|$)/.test(dbUrl)) {
  console.error("Rechazado: la base debe ser de pruebas (nombre terminado en _uat).");
  process.exit(2);
}

const TENANT_KEY = "alto-dona-mamita-sistema-solares";
const COMPANY_NAME = process.env.UAT_COMPANY_NAME ?? "EMPRESA DE PRUEBA UAT";

const prisma = new PrismaClient({ datasources: { db: { url: dbUrl } } });

async function main() {
  const company = await prisma.company.upsert({
    where: { tenantKey: TENANT_KEY },
    update: { name: COMPANY_NAME, active: true },
    create: {
      tenantKey: TENANT_KEY,
      name: COMPANY_NAME,
      active: true,
    },
    select: { id: true, name: true },
  });

  await prisma.companyProfile.upsert({
    where: { companyId: company.id },
    update: { name: COMPANY_NAME },
    create: {
      companyId: company.id,
      syncId: "uat-company-profile",
      name: COMPANY_NAME,
    },
  }).catch((error) => {
    console.warn("companyProfile omitido:", error.message);
  });

  const counts = {
    clients: await prisma.client.count({ where: { companyId: company.id } }),
    sales: await prisma.sale.count({ where: { companyId: company.id } }),
    payments: await prisma.payment.count({ where: { companyId: company.id } }),
  };

  console.log(
    JSON.stringify(
      { companyId: company.id, companyName: company.name, counts },
      null,
      2,
    ),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
