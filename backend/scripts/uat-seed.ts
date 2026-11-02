/**
 * FASE 06B — Fixture DESECHABLE para la UAT de Windows.
 *
 * Crea registros claramente marcados ("UAT-") dentro de la empresa de
 * ACEPTACION existente, sin tocar los registros reales de aceptacion:
 *   - Cliente "UAT CLIENTE DESECHABLE" (con venta financiada y pagos)
 *   - Cliente "UAT CLIENTE DUPLICADO"  (mismo documento, para fusionar)
 *   - Solar  "UAT" numero "1" (vendido, ligado a la venta)
 *   - Solar  "UAT" numero "2" (disponible, para pruebas de estado)
 *
 * Venta: 4 cuotas al 1 % mensual, inicial pagada.
 * Pagos: 1 cuota (con interes/capital) y 1 abono a capital.
 *
 * Solo base local de aceptacion. Idempotente: borra y recrea sus propios
 * registros (marcados con syncId que empieza por "uat-").
 */
import { PrismaClient } from "@prisma/client";

const dbUrl = process.env.ACCEPTANCE_DATABASE_URL ?? "";
if (!dbUrl) {
  console.error("Falta ACCEPTANCE_DATABASE_URL.");
  process.exit(2);
}
if (!/(127\.0\.0\.1|localhost)/.test(dbUrl)) {
  console.error("Rechazado: solo Acceptance local.");
  process.exit(2);
}

const prisma = new PrismaClient({ datasources: { db: { url: dbUrl } } });
const RUN = process.env.UAT_RUN ?? "uat-fixture";

function money(value: number) {
  return Math.round(value * 100) / 100;
}

async function cleanup(companyId: string) {
  const sales = await prisma.sale.findMany({
    where: { companyId, syncId: { startsWith: "uat-" } },
    select: { id: true, syncId: true },
  });
  const saleIds = sales.map((s) => s.id);
  const saleSyncIds = sales.map((s) => s.syncId);

  if (saleIds.length > 0) {
    await prisma.payment.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.lateFeeSnapshot.deleteMany({
      where: { saleSyncId: { in: saleSyncIds } },
    }).catch(() => undefined);
    await prisma.installment.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.sale.deleteMany({ where: { id: { in: saleIds } } });
  }
  await prisma.lot.deleteMany({
    where: { companyId, syncId: { startsWith: "uat-" } },
  });
  await prisma.client.deleteMany({
    where: { companyId, syncId: { startsWith: "uat-" } },
  });
  await prisma.authoritativeOperation.deleteMany({
    where: { companyId, operationKey: { startsWith: "uat-" } },
  });
}

async function main() {
  const company = await prisma.company.findFirst({
    where: { tenantKey: "alto-dona-mamita-sistema-solares" },
    select: { id: true },
  });
  if (!company) throw new Error("No existe la empresa de aceptacion.");

  await cleanup(company.id);

  const client = await prisma.client.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-client`,
      name: "UAT CLIENTE DESECHABLE",
      document: "999-0000001-1",
      phone: "8090000001",
      address: "DIRECCION UAT",
      version: 1,
    },
  });

  const duplicate = await prisma.client.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-client-dup`,
      name: "UAT CLIENTE DUPLICADO",
      document: "999-0000002-2",
      phone: "8090000002",
      address: "DIRECCION UAT DUP",
      version: 1,
    },
  });

  const lot = await prisma.lot.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-lot-1`,
      block: "UAT",
      number: "1",
      area: 200,
      price: 500000,
      status: "vendido",
      version: 1,
    },
  });

  const lot2 = await prisma.lot.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-lot-2`,
      block: "UAT",
      number: "2",
      area: 150,
      price: 375000,
      status: "disponible",
      version: 1,
    },
  });

  const salePrice = 500000;
  const initialPaid = 50000;
  const financed = money(salePrice - initialPaid);
  const installments = 4;
  const monthlyRate = 0.01;
  const fixedPayment = money(
    (financed * monthlyRate) / (1 - Math.pow(1 + monthlyRate, -installments)),
  );
  const saleDate = new Date("2026-06-01T00:00:00.000Z");

  const sale = await prisma.sale.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-sale`,
      clientId: client.id,
      lotId: lot.id,
      clientSyncId: client.syncId,
      lotSyncId: lot.syncId,
      saleDate,
      status: "activa",
      total: salePrice,
      initialRequiredAmount: initialPaid,
      initialPaid,
      initialPendingAmount: 0,
      financedBalance: financed,
      balance: financed,
      monthlyInterestRate: 1,
      installmentCount: installments,
      version: 1,
    },
  });

  let balance = financed;
  const created = [];
  for (let index = 1; index <= installments; index += 1) {
    const interest = money(balance * monthlyRate);
    const principal =
      index === installments ? money(balance) : money(fixedPayment - interest);
    const total = money(principal + interest);
    const ending = money(balance - principal);
    const dueDate = new Date(saleDate);
    dueDate.setUTCMonth(dueDate.getUTCMonth() + index);
    const inst = await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-inst-${index}`,
        saleId: sale.id,
        saleSyncId: sale.syncId,
        installmentNumber: index,
        dueDate,
        openingBalance: balance,
        principalAmount: principal,
        interestAmount: interest,
        totalAmount: total,
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        endingBalance: ending,
        status: "pendiente",
        version: 1,
      },
    });
    created.push({ inst, principal, interest, total });
    balance = ending;
  }

  // Pago 1: cuota 1 completa (interes + capital).
  const first = created[0];
  await prisma.installment.update({
    where: { id: first.inst.id },
    data: {
      paidAmount: first.total,
      paidPrincipalAmount: first.principal,
      paidInterestAmount: first.interest,
      status: "pagada",
      version: 2,
    },
  });
  await prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-pay-1`,
      saleId: sale.id,
      clientId: client.id,
      installmentId: first.inst.id,
      saleSyncId: sale.syncId,
      installmentSyncId: first.inst.syncId,
      paidAt: new Date("2026-07-05T00:00:00.000Z"),
      amount: first.total,
      method: "efectivo",
      paymentType: "cuota",
      principalApplied: first.principal,
      interestApplied: first.interest,
      lateFeeApplied: 0,
      version: 1,
    },
  });

  // Pago 2: abono a capital de 20.000 sobre la cuota 2.
  const capitalAbono = 20000;
  const second = created[1];
  const secondInterest = second.interest;
  await prisma.installment.update({
    where: { id: second.inst.id },
    data: {
      paidAmount: secondInterest + capitalAbono,
      paidPrincipalAmount: capitalAbono,
      paidInterestAmount: secondInterest,
      status: "parcial",
      version: 2,
    },
  });
  await prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-pay-2`,
      saleId: sale.id,
      clientId: client.id,
      installmentId: second.inst.id,
      saleSyncId: sale.syncId,
      installmentSyncId: second.inst.syncId,
      paidAt: new Date("2026-08-05T00:00:00.000Z"),
      amount: money(secondInterest + capitalAbono),
      method: "transferencia",
      paymentType: "cuota",
      principalApplied: capitalAbono,
      interestApplied: secondInterest,
      lateFeeApplied: 0,
      version: 1,
    },
  });

  const pendingBalance = money(financed - first.principal - capitalAbono);
  await prisma.sale.update({
    where: { id: sale.id },
    data: { balance: pendingBalance, version: 2 },
  });

  console.log(
    JSON.stringify(
      {
        clientId: client.id,
        clientSyncId: client.syncId,
        duplicateClientId: duplicate.id,
        lotId: lot.id,
        lotSyncId: lot.syncId,
        lot2Id: lot2.id,
        saleId: sale.id,
        saleSyncId: sale.syncId,
        financed,
        fixedPayment,
        pendingBalance,
      },
      null,
      2,
    ),
  );
  await prisma.$disconnect();
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exit(1);
});
