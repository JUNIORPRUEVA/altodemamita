/**
 * FASE 03 — E2E de la administracion OWNER de ventas contra PostgreSQL real.
 *
 * Fixture aislado: empresa, OWNER, dos clientes, tres solares y tres ventas.
 * Verifica invariantes: balance == capital pendiente, un solar = una venta
 * activa, cancelacion logica reversible y bloqueo cuando hay pagos activos.
 */
import { PrismaClient } from "@prisma/client";
import { SaleCorrectionService } from "../src/services/saleCorrection.service";

const url = process.env.ACCEPTANCE_DATABASE_URL ?? "";
if (!url) {
  console.error("Falta ACCEPTANCE_DATABASE_URL.");
  process.exit(2);
}
if (!/(127\.0\.0\.1|localhost)/.test(url)) {
  console.error("Rechazado: solo Acceptance local.");
  process.exit(2);
}

const prisma = new PrismaClient({ datasources: { db: { url } } });
const service = new SaleCorrectionService(prisma);
const RUN = `acc-sale-${Date.now()}`;
const results: { name: string; ok: boolean; detail: string }[] = [];

function check(name: string, ok: boolean, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
}

function money(value: unknown): number {
  return Math.round(Number(value ?? 0) * 100) / 100;
}

async function outstandingPrincipal(saleId: string) {
  const rows = await prisma.installment.findMany({
    where: { saleId, deletedAt: null },
    select: { principalAmount: true, paidPrincipalAmount: true },
  });
  return money(
    rows.reduce(
      (sum, row) =>
        sum +
        Math.max(money(row.principalAmount) - money(row.paidPrincipalAmount), 0),
      0,
    ),
  );
}

async function main() {
  const company = await prisma.company.create({
    data: { tenantKey: RUN, name: `Ventas ${RUN}` },
  });
  const owner = await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-owner`,
      email: `${RUN}-owner@acceptance.local`,
      name: "Owner Ventas",
      passwordHash: "not-used",
      role: "OWNER",
      localRole: "admin",
    },
  });
  const clientA = await prisma.client.create({
    data: { companyId: company.id, syncId: `${RUN}-client-a`, name: "Cliente A" },
  });
  const clientB = await prisma.client.create({
    data: { companyId: company.id, syncId: `${RUN}-client-b`, name: "Cliente B" },
  });
  const lot1 = await prisma.lot.create({
    data: { companyId: company.id, syncId: `${RUN}-lot-1`, block: "A", number: "01", status: "vendido" },
  });
  const lot2 = await prisma.lot.create({
    data: { companyId: company.id, syncId: `${RUN}-lot-2`, block: "A", number: "02", status: "disponible" },
  });
  const lot3 = await prisma.lot.create({
    data: { companyId: company.id, syncId: `${RUN}-lot-3`, block: "A", number: "03", status: "vendido" },
  });

  async function createSale(input: {
    suffix: string;
    clientId: string;
    lotId: string;
    lotSyncId: string;
    clientSyncId: string;
    total: number;
    initial: number;
    installments: number;
  }) {
    const financed = money(input.total - input.initial);
    const sale = await prisma.sale.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-sale-${input.suffix}`,
        clientId: input.clientId,
        lotId: input.lotId,
        clientSyncId: input.clientSyncId,
        lotSyncId: input.lotSyncId,
        saleDate: new Date("2026-08-01T00:00:00.000Z"),
        status: financed > 0 ? "activa" : "pagada",
        total: input.total,
        initialRequiredAmount: input.initial,
        initialPaid: input.initial,
        initialPendingAmount: 0,
        financedBalance: financed,
        balance: financed,
        monthlyInterestRate: 0,
        installmentCount: input.installments,
      },
    });
    return sale;
  }

  const sale1 = await createSale({
    suffix: "1",
    clientId: clientA.id,
    lotId: lot1.id,
    lotSyncId: lot1.syncId,
    clientSyncId: clientA.syncId,
    total: 50000,
    initial: 10000,
    installments: 4,
  });
  // Cronograma inicial de 4 cuotas de 10,000.
  for (let index = 0; index < 4; index += 1) {
    await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-s1-inst-${index + 1}`,
        saleId: sale1.id,
        saleSyncId: sale1.syncId,
        installmentNumber: index + 1,
        dueDate: new Date(`${2026}-${(9 + index).toString().padStart(2, "0")}-01T00:00:00.000Z`),
        openingBalance: 40000 - index * 10000,
        principalAmount: 10000,
        interestAmount: 0,
        totalAmount: 10000,
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        endingBalance: 40000 - (index + 1) * 10000,
        status: "pendiente",
      },
    });
  }

  // Venta 2 ocupa el solar 3 (para probar el conflicto de solar).
  const sale2 = await createSale({
    suffix: "2",
    clientId: clientB.id,
    lotId: lot3.id,
    lotSyncId: lot3.syncId,
    clientSyncId: clientB.syncId,
    total: 30000,
    initial: 30000,
    installments: 0,
  });

  // Venta 3 con un pago activo (bloquea cambios de importes y cliente).
  const sale3 = await createSale({
    suffix: "3",
    clientId: clientA.id,
    lotId: lot2.id,
    lotSyncId: lot2.syncId,
    clientSyncId: clientA.syncId,
    total: 20000,
    initial: 20000,
    installments: 0,
  });
  await prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-s3-pay`,
      saleId: sale3.id,
      clientId: clientA.id,
      saleSyncId: sale3.syncId,
      paidAt: new Date("2026-08-01T00:00:00.000Z"),
      amount: 20000,
      method: "efectivo",
      paymentType: "contado",
      principalApplied: 20000,
      interestApplied: 0,
      lateFeeApplied: 0,
    },
  });

  try {
    // ── 1. Preview de financiamiento (sin escribir) ──────────────────────
    const preview = (await service.previewSaleCorrection({
      companyId: company.id,
      saleId: sale1.id,
      action: "update_financing",
      totalPrice: 60000,
      initialPaidAmount: 15000,
      installmentCount: 4,
    })) as any;
    const saleAfterPreview = await prisma.sale.findUnique({ where: { id: sale1.id } });
    check(
      "preview informa el impacto del financiamiento",
      preview?.impact?.totalBefore === 50000 &&
        preview?.impact?.totalAfter === 60000 &&
        preview?.impact?.financedAfter === 45000,
      `antes=${preview?.impact?.totalBefore} despues=${preview?.impact?.totalAfter}`,
    );
    check(
      "el preview no escribe nada",
      money(saleAfterPreview?.total) === 50000,
      String(saleAfterPreview?.total),
    );

    // ── 2. Aplicar financiamiento ────────────────────────────────────────
    await service.applySaleCorrection({
      companyId: company.id,
      saleId: sale1.id,
      action: "update_financing",
      totalPrice: 60000,
      initialPaidAmount: 15000,
      initialRequiredAmount: 15000,
      installmentCount: 5,
      monthlyInterestRate: 1,
      reason: "Reestructuracion solicitada por el cliente",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-fin`,
      expectedSaleVersion: sale1.version,
    });
    const sale1After = await prisma.sale.findUnique({ where: { id: sale1.id } });
    const openAfter = await prisma.installment.count({
      where: { saleId: sale1.id, deletedAt: null },
    });
    check(
      "actualiza precio, inicial, financiado y plazo",
      money(sale1After?.total) === 60000 &&
        money(sale1After?.initialPaid) === 15000 &&
        money(sale1After?.financedBalance) === 45000 &&
        openAfter === 5,
      `total=${sale1After?.total} inicial=${sale1After?.initialPaid} cuotas=${openAfter}`,
    );
    check(
      "el saldo sigue coincidiendo con el capital de las cuotas",
      money(sale1After?.balance) === (await outstandingPrincipal(sale1.id)),
      `balance=${sale1After?.balance} cuotas=${await outstandingPrincipal(sale1.id)}`,
    );
    const oldInstallments = await prisma.installment.count({
      where: { saleId: sale1.id, deletedAt: { not: null } },
    });
    check(
      "el cronograma anterior se conserva como historia (soft delete)",
      oldInstallments === 4,
      String(oldInstallments),
    );

    // ── 3. Bloqueos con pagos activos ────────────────────────────────────
    let payBlock = "";
    try {
      await service.applySaleCorrection({
        companyId: company.id,
        saleId: sale3.id,
        action: "update_financing",
        totalPrice: 25000,
        reason: "intento con pagos",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-fin-pay`,
      });
    } catch (error: any) {
      payBlock = String(error?.code ?? "");
    }
    check(
      "con pagos activos no se cambian importes (409)",
      payBlock === "SALE_HAS_ACTIVE_PAYMENTS",
      payBlock,
    );

    let clientBlock = "";
    try {
      await service.applySaleCorrection({
        companyId: company.id,
        saleId: sale3.id,
        action: "change_client",
        clientId: clientB.id,
        reason: "intento con pagos",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-client-pay`,
      });
    } catch (error: any) {
      clientBlock = String(error?.code ?? "");
    }
    check(
      "con pagos activos no se cambia el cliente (409)",
      clientBlock === "SALE_HAS_ACTIVE_PAYMENTS",
      clientBlock,
    );

    // ── 4. Cambio de cliente ─────────────────────────────────────────────
    await service.applySaleCorrection({
      companyId: company.id,
      saleId: sale1.id,
      action: "change_client",
      clientId: clientB.id,
      reason: "Titular corregido",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-client`,
    });
    const saleClient = await prisma.sale.findUnique({ where: { id: sale1.id } });
    check(
      "cambia el cliente del contrato",
      saleClient?.clientId === clientB.id,
      String(saleClient?.clientId),
    );

    // ── 5. Cambio de solar y conflicto de solar ocupado ──────────────────
    let lotBlock = "";
    try {
      await service.applySaleCorrection({
        companyId: company.id,
        saleId: sale1.id,
        action: "change_lot",
        lotId: lot3.id,
        reason: "intento sobre solar ocupado",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-lot-busy`,
      });
    } catch (error: any) {
      lotBlock = String(error?.code ?? "");
    }
    check(
      "un solar ocupado por otra venta activa se rechaza (409)",
      lotBlock === "LOT_ALREADY_ASSIGNED",
      lotBlock,
    );

    // ── 6. Cancelacion logica reversible ─────────────────────────────────
    await service.applySaleCorrection({
      companyId: company.id,
      saleId: sale1.id,
      action: "cancel",
      reason: "Cliente desiste de la compra",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-cancel`,
    });
    const cancelled = await prisma.sale.findUnique({ where: { id: sale1.id } });
    const lot1AfterCancel = await prisma.lot.findUnique({ where: { id: lot1.id } });
    const activeInstAfterCancel = await prisma.installment.count({
      where: { saleId: sale1.id, deletedAt: null },
    });
    check(
      "la cancelacion es logica y libera el solar",
      cancelled?.status === "cancelada" &&
        cancelled?.deletedAt !== null &&
        money(cancelled?.balance) === 0 &&
        lot1AfterCancel?.status === "disponible" &&
        activeInstAfterCancel === 0,
      `estado=${cancelled?.status} solar=${lot1AfterCancel?.status}`,
    );
    const snapshot = ((cancelled?.raw ?? {}) as any).cancellationSnapshot;
    check(
      "guarda snapshot para poder restaurar",
      !!snapshot && snapshot.statusBefore === "activa",
      String(snapshot?.statusBefore),
    );

    let cancelTwice = "";
    try {
      await service.applySaleCorrection({
        companyId: company.id,
        saleId: sale1.id,
        action: "cancel",
        reason: "doble cancelacion",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-cancel-2`,
      });
    } catch (error: any) {
      cancelTwice = String(error?.code ?? "");
    }
    check("no se puede cancelar dos veces (409)", cancelTwice === "SALE_ALREADY_CANCELLED", cancelTwice);

    // ── 7. Restauracion ──────────────────────────────────────────────────
    await service.applySaleCorrection({
      companyId: company.id,
      saleId: sale1.id,
      action: "restore",
      reason: "Cliente reconsidero la compra",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-restore`,
    });
    const restored = await prisma.sale.findUnique({ where: { id: sale1.id } });
    const restoredInstallments = await prisma.installment.count({
      where: { saleId: sale1.id, deletedAt: null },
    });
    const lot1AfterRestore = await prisma.lot.findUnique({ where: { id: lot1.id } });
    check(
      "restaura la venta cancelada con su cronograma y su solar",
      restored?.status === "activa" &&
        restored?.deletedAt === null &&
        money(restored?.balance) === (await outstandingPrincipal(sale1.id)) &&
        restoredInstallments === 5 &&
        lot1AfterRestore?.status === "vendido",
      `estado=${restored?.status} cuotas=${restoredInstallments} solar=${lot1AfterRestore?.status}`,
    );

    let restoreTwice = "";
    try {
      await service.applySaleCorrection({
        companyId: company.id,
        saleId: sale1.id,
        action: "restore",
        reason: "restaurar una venta activa",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-restore-2`,
      });
    } catch (error: any) {
      restoreTwice = String(error?.code ?? "");
    }
    check(
      "no se restaura una venta que no esta cancelada (409)",
      restoreTwice === "SALE_NOT_CANCELLED",
      restoreTwice,
    );

    // ── 8. Motivo, version y auditoria ───────────────────────────────────
    let reasonCode = "";
    try {
      await service.applySaleCorrection({
        companyId: company.id,
        saleId: sale1.id,
        action: "change_client",
        clientId: clientA.id,
        reason: "   ",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-noreason`,
      });
    } catch (error: any) {
      reasonCode = String(error?.code ?? "");
    }
    check("exige motivo", reasonCode === "CORRECTION_REASON_REQUIRED", reasonCode);

    let versionCode = "";
    try {
      await service.applySaleCorrection({
        companyId: company.id,
        saleId: sale1.id,
        action: "change_client",
        clientId: clientA.id,
        reason: "version obsoleta",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-ver`,
        expectedSaleVersion: 999,
      });
    } catch (error: any) {
      versionCode = String(error?.code ?? "");
    }
    check("version obsoleta (409)", versionCode === "SALE_VERSION_CONFLICT", versionCode);

    const audit = (await service.getSaleCorrectionHistory({
      companyId: company.id,
      saleId: sale1.id,
    })) as any;
    const history = Array.isArray(audit?.history) ? audit.history : [];
    check(
      "la auditoria registra financiamiento, cliente, cancelacion y restauracion",
      history.some((entry: any) => entry.action === "update_financing") &&
        history.some((entry: any) => entry.action === "change_client") &&
        history.some((entry: any) => entry.action === "cancel") &&
        history.some((entry: any) => entry.action === "restore"),
      `${history.length} evento(s)`,
    );

    // ── 9. Invariante final ──────────────────────────────────────────────
    const finalSale = await prisma.sale.findUnique({ where: { id: sale1.id } });
    check(
      "invariante final: balance == capital pendiente",
      money(finalSale?.balance) === (await outstandingPrincipal(sale1.id)),
      `balance=${finalSale?.balance} cuotas=${await outstandingPrincipal(sale1.id)}`,
    );
    check(
      "la venta 2 conserva su solar intacto",
      (await prisma.lot.findUnique({ where: { id: lot3.id } }))?.status === "vendido",
    );
    void sale2;
  } finally {
    const ids = [company.id];
    await prisma.authoritativeOperation.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.lateFeeWaiver.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.lateFeeSnapshot.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.payment.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.installment.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.sale.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.lot.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.client.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.user.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.company.deleteMany({ where: { id: { in: ids } } });
  }

  const failed = results.filter((r) => !r.ok);
  console.log(`\nRESULTADO: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    for (const f of failed) console.log(` - ${f.name} ${f.detail}`);
    process.exitCode = 1;
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
