/**
 * FASE 06B — Fixture DESECHABLE y AMPLIADO para la UAT de Windows.
 *
 * Crea 11 clientes marcados con "UAT" (nada de datos reales) dentro de la
 * empresa de PRUEBAS, cada uno con una operacion financiera distinta para poder
 * ejercitar todas las pantallas y acciones administrativas:
 *
 *   UAT 01 DESECHABLE   venta financiada: cuota 1 pagada + abono a capital
 *   UAT 02 CONTADO      venta al contado cobrada (pago NO anulable)
 *   UAT 03 APARTADO     apartado con inicial pendiente
 *   UAT 04 MORA         venta impaga con cuotas vencidas y mora acumulada
 *   UAT 05 PARCIALES    cuota pagada con 3 pagos parciales
 *   UAT 06 LIQUIDADA    venta con todas las cuotas pagadas (saldo 0)
 *   UAT 07 CANCELADA    venta cancelada con un pago ANULADO
 *   UAT 08 MORA PAGADA  pago que incluye mora + interes + capital
 *   UAT 09 SIN VENTAS   cliente sin operaciones
 *   UAT 10 DUPLICADO    mismo documento que UAT 01 (para fusionar)
 *   UAT 11 INICIAL      inicial pagada en dos abonos (apartado + abono inicial)
 *
 * Solares UAT-1 .. UAT-8 con estados vendido / disponible / reservado.
 *
 * Solo base local de pruebas. Idempotente: borra y recrea sus propios
 * registros (syncId que empieza por "uat-").
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

const prisma = new PrismaClient({ datasources: { db: { url: dbUrl } } });
const RUN = process.env.UAT_RUN ?? "uat-fixture";

function money(value: number) {
  return Math.round(value * 100) / 100;
}

function addMonths(base: Date, months: number) {
  const next = new Date(base);
  next.setUTCMonth(next.getUTCMonth() + months);
  return next;
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
    await prisma.lateFeeSnapshot
      .deleteMany({ where: { saleSyncId: { in: saleSyncIds } } })
      .catch(() => undefined);
    await prisma.lateFeeWaiver
      .deleteMany({ where: { saleSyncId: { in: saleSyncIds } } })
      .catch(() => undefined);
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

type Company = { id: string };

async function createClient(
  company: Company,
  syncSuffix: string,
  name: string,
  document: string,
  phone: string,
  address = "DIRECCION DE PRUEBA UAT",
) {
  return prisma.client.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-${syncSuffix}`,
      name,
      document,
      phone,
      address,
      version: 1,
    },
  });
}

async function createLot(
  company: Company,
  number: string,
  area: number,
  price: number,
  status: string,
) {
  return prisma.lot.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-lot-${number}`,
      block: "UAT",
      number,
      area,
      price,
      status,
      version: 1,
    },
  });
}

/**
 * Crea una venta financiada con su cronograma EXACTO (la ultima cuota amortiza
 * el saldo de apertura completo, igual que el motor del backend).
 */
async function createFinancedSale(input: {
  company: Company;
  clientId: string;
  clientSyncId: string;
  lotId: string | null;
  lotSyncId: string | null;
  saleSyncSuffix: string;
  saleDate: Date;
  price: number;
  initialPaid: number;
  initialPending?: number;
  count: number;
  rate?: number;
  status?: string;
}) {
  const {
    company,
    clientId,
    clientSyncId,
    lotId,
    lotSyncId,
    saleSyncSuffix,
    saleDate,
    price,
    initialPaid,
    initialPending = 0,
    count,
    rate = 0.01,
    status = "activa",
  } = input;

  const financed = money(price - initialPaid);
  const fixedPayment = money(
    count > 0 ? (financed * rate) / (1 - Math.pow(1 + rate, -count)) : 0,
  );

  const sale = await prisma.sale.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-${saleSyncSuffix}`,
      clientId,
      lotId,
      clientSyncId,
      lotSyncId,
      saleDate,
      status,
      total: price,
      initialRequiredAmount: money(initialPaid + initialPending),
      initialPaid,
      initialPendingAmount: initialPending,
      financedBalance: financed,
      balance: financed,
      monthlyInterestRate: rate * 100,
      installmentCount: count,
      version: 1,
    },
  });

  let balance = financed;
  const schedule: Array<{
    inst: { id: string; syncId: string };
    opening: number;
    principal: number;
    interest: number;
    total: number;
    dueDate: Date;
  }> = [];

  for (let index = 1; index <= count; index += 1) {
    const interest = money(balance * rate);
    const principal =
      index === count ? money(balance) : money(fixedPayment - interest);
    const total = money(principal + interest);
    const ending = money(balance - principal);
    const dueDate = addMonths(saleDate, index);
    const inst = await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-${saleSyncSuffix}-inst-${index}`,
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
    schedule.push({
      inst,
      opening: balance,
      principal,
      interest,
      total,
      dueDate,
    });
    balance = ending;
  }

  return { sale, schedule, financed, fixedPayment };
}

/** Aplica un pago sobre una cuota: actualiza la cuota y crea el movimiento. */
async function payInstallment(input: {
  company: Company;
  saleId: string;
  saleSyncId: string;
  clientId: string;
  clientSyncId: string;
  installment: { id: string; syncId: string };
  principal: number;
  interest: number;
  lateFee?: number;
  paidAt: Date;
  paymentType?: string;
  method?: string;
  syncSuffix: string;
}) {
  const {
    company,
    saleId,
    saleSyncId,
    clientId,
    clientSyncId,
    installment,
    principal,
    interest,
    lateFee = 0,
    paidAt,
    paymentType = "cuota",
    method = "efectivo",
    syncSuffix,
  } = input;

  const amount = money(principal + interest + lateFee);
  const current = await prisma.installment.findUnique({
    where: { id: installment.id },
    select: {
      paidAmount: true,
      paidPrincipalAmount: true,
      paidInterestAmount: true,
      totalAmount: true,
      version: true,
    },
  });
  if (!current) throw new Error(`Cuota inexistente: ${installment.id}`);

  const paidAmount = money(Number(current.paidAmount) + amount);
  const paidPrincipal = money(Number(current.paidPrincipalAmount) + principal);
  const paidInterest = money(Number(current.paidInterestAmount) + interest);
  const total = Number(current.totalAmount);
  const status = paidAmount + 0.009 >= total ? "pagada" : "parcial";

  await prisma.installment.update({
    where: { id: installment.id },
    data: {
      paidAmount,
      paidPrincipalAmount: paidPrincipal,
      paidInterestAmount: paidInterest,
      status,
      version: current.version + 1,
    },
  });

  return prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-${syncSuffix}`,
      saleId,
      clientId,
      installmentId: installment.id,
      saleSyncId,
      clientSyncId,
      installmentSyncId: installment.syncId,
      paidAt,
      amount,
      method,
      paymentType,
      principalApplied: principal,
      interestApplied: interest,
      lateFeeApplied: lateFee,
      version: 1,
    },
  });
}

async function main() {
  const company = await prisma.company.findFirst({
    where: { tenantKey: "alto-dona-mamita-sistema-solares" },
    select: { id: true },
  });
  if (!company) throw new Error("No existe la empresa de pruebas.");

  await cleanup(company.id);

  const summary: Array<Record<string, unknown>> = [];

  // --- Solares -----------------------------------------------------------
  const lots = {
    l1: await createLot(company, "1", 200, 500000, "vendido"),
    l2: await createLot(company, "2", 150, 375000, "vendido"),
    l3: await createLot(company, "3", 180, 450000, "vendido"),
    l4: await createLot(company, "4", 160, 400000, "reservado"),
    l5: await createLot(company, "5", 220, 250000, "vendido"),
    l6: await createLot(company, "6", 140, 180000, "vendido"),
    l7: await createLot(company, "7", 190, 300000, "vendido"),
    l8: await createLot(company, "8", 170, 350000, "vendido"),
    l9: await createLot(company, "9", 175, 320000, "disponible"),
  };

  // --- 01 DESECHABLE: cuota 1 pagada + abono a capital -------------------
  const c1 = await createClient(
    company,
    "client",
    "UAT 01 DESECHABLE",
    "999-0000001-1",
    "8090000001",
  );
  {
    const { sale, schedule, financed, fixedPayment } = await createFinancedSale({
      company,
      clientId: c1.id,
      clientSyncId: c1.syncId,
      lotId: lots.l1.id,
      lotSyncId: lots.l1.syncId,
      saleSyncSuffix: "sale",
      saleDate: new Date("2026-06-01T00:00:00.000Z"),
      price: 500000,
      initialPaid: 50000,
      count: 4,
    });

    await payInstallment({
      company,
      saleId: sale.id,
      saleSyncId: sale.syncId,
      clientId: c1.id,
      clientSyncId: c1.syncId,
      installment: schedule[0].inst,
      principal: schedule[0].principal,
      interest: schedule[0].interest,
      paidAt: new Date("2026-07-05T00:00:00.000Z"),
      syncSuffix: "pay-1",
    });

    const capitalAbono = 20000;
    await payInstallment({
      company,
      saleId: sale.id,
      saleSyncId: sale.syncId,
      clientId: c1.id,
      clientSyncId: c1.syncId,
      installment: schedule[1].inst,
      principal: capitalAbono,
      interest: schedule[1].interest,
      paidAt: new Date("2026-08-05T00:00:00.000Z"),
      method: "transferencia",
      syncSuffix: "pay-2",
    });

    const pending = money(financed - schedule[0].principal - capitalAbono);
    await prisma.sale.update({
      where: { id: sale.id },
      data: { balance: pending, version: 2 },
    });

    summary.push({
      cliente: "UAT 01 DESECHABLE",
      operacion: "Financiada 4 cuotas: cuota 1 pagada + abono capital 20,000",
      saldo: pending,
      cuotaFija: fixedPayment,
    });
  }

  // --- 02 CONTADO: venta al contado cobrada (NO anulable) ----------------
  const c2 = await createClient(
    company,
    "client-contado",
    "UAT 02 CONTADO",
    "999-0000003-3",
    "8090000003",
  );
  {
    const price = 300000;
    const sale = await prisma.sale.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-sale-contado`,
        clientId: c2.id,
        lotId: lots.l2.id,
        clientSyncId: c2.syncId,
        lotSyncId: lots.l2.syncId,
        saleDate: new Date("2026-09-10T00:00:00.000Z"),
        status: "pagada",
        total: price,
        initialRequiredAmount: price,
        initialPaid: price,
        initialPendingAmount: 0,
        financedBalance: 0,
        balance: 0,
        monthlyInterestRate: 0,
        installmentCount: 0,
        version: 1,
      },
    });
    await prisma.payment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-pay-contado`,
        saleId: sale.id,
        clientId: c2.id,
        saleSyncId: sale.syncId,
        clientSyncId: c2.syncId,
        paidAt: new Date("2026-09-10T10:00:00.000Z"),
        amount: price,
        method: "efectivo",
        paymentType: "contado",
        principalApplied: price,
        interestApplied: 0,
        lateFeeApplied: 0,
        version: 1,
      },
    });
    summary.push({
      cliente: "UAT 02 CONTADO",
      operacion: "Venta al contado 300,000 (pago NO anulable individualmente)",
      saldo: 0,
    });
  }

  // --- 03 APARTADO: inicial pendiente -----------------------------------
  const c3 = await createClient(
    company,
    "client-apartado",
    "UAT 03 APARTADO",
    "999-0000004-4",
    "8090000004",
  );
  {
    const price = 400000;
    const initialRequired = 80000;
    const apartadoPagado = 20000;
    const sale = await prisma.sale.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-sale-apartado`,
        clientId: c3.id,
        lotId: lots.l4.id,
        clientSyncId: c3.syncId,
        lotSyncId: lots.l4.syncId,
        saleDate: new Date("2026-10-20T00:00:00.000Z"),
        status: "apartado",
        total: price,
        initialPercentage: 20,
        initialRequiredAmount: initialRequired,
        initialPaid: apartadoPagado,
        initialPendingAmount: money(initialRequired - apartadoPagado),
        reservationMinimumAmount: apartadoPagado,
        reservationPaidAmount: apartadoPagado,
        initialPaymentDeadline: new Date("2026-12-20T00:00:00.000Z"),
        financedBalance: 0,
        balance: money(price - apartadoPagado),
        monthlyInterestRate: 1,
        installmentCount: 0,
        version: 1,
      },
    });
    await prisma.payment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-pay-apartado`,
        saleId: sale.id,
        clientId: c3.id,
        saleSyncId: sale.syncId,
        clientSyncId: c3.syncId,
        paidAt: new Date("2026-10-20T09:30:00.000Z"),
        amount: apartadoPagado,
        method: "efectivo",
        paymentType: "apartado",
        principalApplied: apartadoPagado,
        interestApplied: 0,
        lateFeeApplied: 0,
        version: 1,
      },
    });
    summary.push({
      cliente: "UAT 03 APARTADO",
      operacion: "Apartado 20,000 de un inicial de 80,000 (60,000 pendientes)",
      saldo: money(price - apartadoPagado),
    });
  }

  // --- 04 MORA: cuotas vencidas sin pagos -------------------------------
  const c4 = await createClient(
    company,
    "client-mora",
    "UAT 04 MORA",
    "999-0000005-5",
    "8090000005",
  );
  {
    const { sale, schedule, financed } = await createFinancedSale({
      company,
      clientId: c4.id,
      clientSyncId: c4.syncId,
      lotId: lots.l5.id,
      lotSyncId: lots.l5.syncId,
      saleSyncSuffix: "sale-mora",
      saleDate: new Date("2025-01-15T00:00:00.000Z"),
      price: 250000,
      initialPaid: 25000,
      count: 3,
    });
    const first = schedule[0];
    await prisma.lateFeeSnapshot
      .create({
        data: {
          companyId: company.id,
          clientSyncId: c4.syncId,
          saleSyncId: sale.syncId,
          installmentSyncId: first.inst.syncId,
          calculatedAt: new Date("2026-10-01T00:00:00.000Z"),
          baseBalance: first.total,
          overdueDays: 300,
          graceDays: 5,
          lateFeeDays: 295,
          dailyRate: 0.005,
          calculatedLateFee: money(first.total * 0.005 * 295),
          eventType: "CALCULO_AUTOMATICO",
        },
      })
      .catch(() => undefined);
    summary.push({
      cliente: "UAT 04 MORA",
      operacion: "3 cuotas vencidas sin pagos (mora acumulada)",
      saldo: financed,
    });
  }

  // --- 05 PARCIALES: una cuota pagada con 3 abonos ----------------------
  const c5 = await createClient(
    company,
    "client-parciales",
    "UAT 05 PARCIALES",
    "999-0000006-6",
    "8090000006",
  );
  {
    const { sale, schedule, financed } = await createFinancedSale({
      company,
      clientId: c5.id,
      clientSyncId: c5.syncId,
      lotId: lots.l3.id,
      lotSyncId: lots.l3.syncId,
      saleSyncSuffix: "sale-parciales",
      saleDate: new Date("2026-07-01T00:00:00.000Z"),
      price: 150000,
      initialPaid: 15000,
      count: 3,
    });
    const target = schedule[0];
    const partPrincipal = money(target.principal / 2);
    const partInterest = money(target.interest / 2);
    const secondPrincipal = money(partPrincipal / 2);
    const lastPrincipal = money(target.principal - partPrincipal - secondPrincipal);
    const lastInterest = money(target.interest - partInterest);

    await payInstallment({
      company,
      saleId: sale.id,
      saleSyncId: sale.syncId,
      clientId: c5.id,
      clientSyncId: c5.syncId,
      installment: target.inst,
      principal: partPrincipal,
      interest: partInterest,
      paidAt: new Date("2026-08-02T00:00:00.000Z"),
      syncSuffix: "pay-parciales-1",
    });
    await payInstallment({
      company,
      saleId: sale.id,
      saleSyncId: sale.syncId,
      clientId: c5.id,
      clientSyncId: c5.syncId,
      installment: target.inst,
      principal: secondPrincipal,
      interest: 0,
      paidAt: new Date("2026-08-15T00:00:00.000Z"),
      method: "transferencia",
      syncSuffix: "pay-parciales-2",
    });
    await payInstallment({
      company,
      saleId: sale.id,
      saleSyncId: sale.syncId,
      clientId: c5.id,
      clientSyncId: c5.syncId,
      installment: target.inst,
      principal: lastPrincipal,
      interest: lastInterest,
      paidAt: new Date("2026-08-28T00:00:00.000Z"),
      syncSuffix: "pay-parciales-3",
    });

    await prisma.sale.update({
      where: { id: sale.id },
      data: { balance: money(financed - target.principal), version: 2 },
    });
    summary.push({
      cliente: "UAT 05 PARCIALES",
      operacion: "Cuota 1 pagada con 3 abonos parciales",
      saldo: money(financed - target.principal),
    });
  }

  // --- 06 LIQUIDADA: todas las cuotas pagadas ---------------------------
  const c6 = await createClient(
    company,
    "client-liquidada",
    "UAT 06 LIQUIDADA",
    "999-0000007-7",
    "8090000007",
  );
  {
    const { sale, schedule } = await createFinancedSale({
      company,
      clientId: c6.id,
      clientSyncId: c6.syncId,
      lotId: lots.l6.id,
      lotSyncId: lots.l6.syncId,
      saleSyncSuffix: "sale-liquidada",
      saleDate: new Date("2026-04-01T00:00:00.000Z"),
      price: 180000,
      initialPaid: 18000,
      count: 2,
    });
    for (let i = 0; i < schedule.length; i += 1) {
      const item = schedule[i];
      await payInstallment({
        company,
        saleId: sale.id,
        saleSyncId: sale.syncId,
        clientId: c6.id,
        clientSyncId: c6.syncId,
        installment: item.inst,
        principal: item.principal,
        interest: item.interest,
        paidAt: addMonths(new Date("2026-04-05T00:00:00.000Z"), i),
        syncSuffix: `pay-liquidada-${i + 1}`,
      });
    }
    await prisma.sale.update({
      where: { id: sale.id },
      data: { balance: 0, status: "pagada", version: 2 },
    });
    summary.push({
      cliente: "UAT 06 LIQUIDADA",
      operacion: "2 cuotas pagadas, saldo 0 (liquidada)",
      saldo: 0,
    });
  }

  // --- 07 CANCELADA: venta cancelada con un pago anulado ----------------
  const c7 = await createClient(
    company,
    "client-cancelada",
    "UAT 07 CANCELADA",
    "999-0000008-8",
    "8090000008",
  );
  {
    const { sale, schedule } = await createFinancedSale({
      company,
      clientId: c7.id,
      clientSyncId: c7.syncId,
      lotId: lots.l7.id,
      lotSyncId: lots.l7.syncId,
      saleSyncSuffix: "sale-cancelada",
      saleDate: new Date("2026-05-01T00:00:00.000Z"),
      price: 300000,
      initialPaid: 30000,
      count: 2,
      status: "cancelada",
    });
    const payment = await payInstallment({
      company,
      saleId: sale.id,
      saleSyncId: sale.syncId,
      clientId: c7.id,
      clientSyncId: c7.syncId,
      installment: schedule[0].inst,
      principal: schedule[0].principal,
      interest: schedule[0].interest,
      paidAt: new Date("2026-06-02T00:00:00.000Z"),
      syncSuffix: "pay-cancelada-anulada",
    });
    await prisma.payment.update({
      where: { id: payment.id },
      data: {
        annulledAt: new Date("2026-06-10T00:00:00.000Z"),
        annulmentReason: "Pago registrado por error (UAT)",
        version: 2,
      },
    });
    await prisma.installment.update({
      where: { id: schedule[0].inst.id },
      data: {
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        status: "pendiente",
        version: 3,
      },
    });
    // Venta cancelada: la deuda queda extinguida.
    await prisma.sale.update({
      where: { id: sale.id },
      data: { balance: 0, version: 2 },
    });
    summary.push({
      cliente: "UAT 07 CANCELADA",
      operacion: "Venta cancelada con 1 pago ANULADO (recibo anulado)",
      saldo: 0,
    });
  }

  // --- 08 MORA PAGADA: pago con mora + interes + capital ----------------
  const c8 = await createClient(
    company,
    "client-mora-pagada",
    "UAT 08 MORA PAGADA",
    "999-0000009-9",
    "8090000009",
  );
  {
    const { sale, schedule, financed } = await createFinancedSale({
      company,
      clientId: c8.id,
      clientSyncId: c8.syncId,
      lotId: lots.l8.id,
      lotSyncId: lots.l8.syncId,
      saleSyncSuffix: "sale-mora-pagada",
      saleDate: new Date("2026-03-01T00:00:00.000Z"),
      price: 200000,
      initialPaid: 20000,
      count: 2,
    });
    await payInstallment({
      company,
      saleId: sale.id,
      saleSyncId: sale.syncId,
      clientId: c8.id,
      clientSyncId: c8.syncId,
      installment: schedule[0].inst,
      principal: schedule[0].principal,
      interest: schedule[0].interest,
      lateFee: 2500,
      paidAt: new Date("2026-09-15T00:00:00.000Z"),
      method: "transferencia",
      paymentType: "cuota_vencida",
      syncSuffix: "pay-mora-pagada",
    });
    await prisma.sale.update({
      where: { id: sale.id },
      data: { balance: money(financed - schedule[0].principal), version: 2 },
    });
    summary.push({
      cliente: "UAT 08 MORA PAGADA",
      operacion: "Pago con mora 2,500 + interes + capital",
      saldo: money(financed - schedule[0].principal),
    });
  }

  // --- 09 SIN VENTAS ----------------------------------------------------
  await createClient(
    company,
    "client-sin-ventas",
    "UAT 09 SIN VENTAS",
    "999-0000010-0",
    "8090000010",
  );
  summary.push({
    cliente: "UAT 09 SIN VENTAS",
    operacion: "Cliente sin operaciones (editar / desactivar / eliminar)",
    saldo: 0,
  });

  // --- 10 DUPLICADO (documento variante de UAT 01) ----------------------
  // El esquema tiene @@unique([companyId, document]), asi que el "duplicado"
  // usa un documento con el mismo titular pero distinto sufijo: sirve igual
  // para probar la deteccion/fusion de clientes duplicados.
  await createClient(
    company,
    "client-dup",
    "UAT 01 DESECHABLE (DUPLICADO)",
    "999-0000001-2",
    "8090000001",
    "DIRECCION DUPLICADA UAT",
  );
  summary.push({
    cliente: "UAT 10 DUPLICADO",
    operacion: "Mismo titular y telefono que UAT 01, documento variante (fusion)",
    saldo: 0,
  });

  // --- 11 INICIAL: inicial pagada en dos abonos ------------------------
  const c11 = await createClient(
    company,
    "client-inicial",
    "UAT 11 INICIAL",
    "999-0000011-1",
    "8090000011",
  );
  {
    const price = 260000;
    const initialRequired = 60000;
    const firstAbono = 10000;
    const secondAbono = 40000;
    const initialPaid = firstAbono + secondAbono;
    const sale = await prisma.sale.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-sale-inicial`,
        clientId: c11.id,
        clientSyncId: c11.syncId,
        saleDate: new Date("2026-09-01T00:00:00.000Z"),
        status: "activa",
        total: price,
        initialPercentage: 23,
        initialRequiredAmount: initialRequired,
        initialPaid,
        initialPendingAmount: money(initialRequired - initialPaid),
        financedBalance: money(price - initialPaid),
        balance: money(price - initialPaid),
        monthlyInterestRate: 1,
        installmentCount: 0,
        version: 1,
      },
    });
    await prisma.payment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-pay-inicial-1`,
        saleId: sale.id,
        clientId: c11.id,
        saleSyncId: sale.syncId,
        clientSyncId: c11.syncId,
        paidAt: new Date("2026-09-01T00:00:00.000Z"),
        amount: firstAbono,
        method: "efectivo",
        paymentType: "apartado",
        principalApplied: firstAbono,
        interestApplied: 0,
        lateFeeApplied: 0,
        version: 1,
      },
    });
    await prisma.payment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-pay-inicial-2`,
        saleId: sale.id,
        clientId: c11.id,
        saleSyncId: sale.syncId,
        clientSyncId: c11.syncId,
        paidAt: new Date("2026-09-20T00:00:00.000Z"),
        amount: secondAbono,
        method: "transferencia",
        paymentType: "abono_inicial",
        principalApplied: secondAbono,
        interestApplied: 0,
        lateFeeApplied: 0,
        version: 1,
      },
    });
    summary.push({
      cliente: "UAT 11 INICIAL",
      operacion: "Inicial 60,000 pagada en 2 abonos (10,000 + 40,000)",
      saldo: money(price - initialPaid),
    });
  }

  console.log(
    JSON.stringify(
      {
        empresa: "EMPRESA DE PRUEBA UAT",
        clientes: summary.length,
        solares: 9,
        detalle: summary,
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
